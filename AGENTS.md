# Plan & Decisions

A personal-blog static-site generator written in Zig 0.16+, porting the spirit
of [nota](https://github.com/rafaeldelboni/nota) (the Fulcro+Pathom CLJS
template currently powering rafael.delboni.cc) into a fast, low-footprint,
FP-flavored hexagonal SSG.

This document is the handoff to a future mentor-agent session. Read it
end-to-end before suggesting code. **The user wants to write the code himself
and use the agent as a Zig mentor, not as a code generator.**

---

## 1. User profile (for the mentor agent)

- 15+ years writing software professionally, mostly in high-level languages
  (Clojure/CLJS, JVM, Node/JS).
- **Zero Zig experience.** Comfortable with systems concepts (memory,
  pointers, stack vs. heap) from general programming maturity but has never
  written allocator-aware code as a daily idiom.
- Prefers functional style: pure functions first, immutability by default,
  composition over inheritance. Coming from Clojure — values data
  orientation, small composable primitives, and treating I/O as something
  that happens at the edges.
- Likes hexagonal / ports-and-adapters. Dislikes ambient mutable state and
  large framework lock-in (current Fulcro setup is what's being moved away
  from).
- Wants to **understand** Zig, not just produce Zig output. Mentor should
  explain *why* idiomatic Zig looks the way it does (allocators-as-parameters,
  errors-as-values, comptime, `Io`-as-parameter) before suggesting how to
  apply it.

### Mentor expectations

- Explain Zig idioms when they first appear. Don't assume; don't over-explain
  general programming.
- When the user proposes a pattern from another language, evaluate whether
  Zig has a cleaner native form before importing the pattern wholesale.
- Default to letting the user write code. Offer corrections and direction.
  Only produce full snippets when explicitly asked.
- Call out memory ownership in every code example: who allocates, who frees.
- Warn proactively about Zig footguns: `defer` ordering, error-set inference,
  pointer aliasing, `@constCast`, integer overflow, the difference between
  `[]T` and `[*]T`, etc.

---

## 2. Goals & non-goals

**Goals**

- Static HTML output deployable to GitHub Pages (current hosting stays).
- Markdown source (GFM-flavored) with YAML frontmatter, written in nvim.
- CLI for content management (`new post`, `new page`, `new gallery`).
- Dev server with hot reload while writing.
- RSS feed generation.
- Image galleries — both as dedicated pages and as inline components in
  posts.
- Generic in-markdown component system (galleries, post lists, ToCs, etc.).
- Migration from the current `nota` setup (Fulcro/Pathom + `src/data.edn`
  registry + markdown files under `resources/public/posts|pages/`).
- Low memory + fast build — natural consequences of the language choice,
  not the primary motivation.

**Non-goals**

- Comments, search, analytics, or any client-side dynamic feature beyond a
  lightbox.
- Theme/template ecosystem. One bespoke template for this site.
- Cross-platform parity at first. Develop on macOS, ensure Linux works for
  CI, ignore Windows.

---

## 3. Architectural principles

### 3.1 Functional ports & adapters

Following [Mark Seemann's insight](https://blog.ploeh.dk/2016/03/18/functional-architecture-is-ports-and-adapters/):
good functional design *is* the ports and adapters architecture. The key
discipline is **purity at the center, impurity at the edges**. No vtables,
no interfaces — just plain functions, with the type signature telling you
whether a function touches the outside world.

The build is a **pipeline of pure transformations** with I/O only at the
ports:

```
[Port]  ──read──▶  [Adapter]  ──parse──▶  [Logic]  ──decide──▶  [Adapter]  ──render──▶  [Port]
  │                                                                                              │
  │ read disk, serve HTTP,                                                                        │
  │ watch files             parse text → domain          route, resolve,            domain →
  │ (impure)                models (pure)               build Site index            HTML/text (pure)
  │                                                                                              │
  ▼                                                                                              ▼
 Sources                                                                                   RenderedPages
```

Five layers, from outside to inside:

1. **Ports** — impure I/O boundaries. Functions that take `std.Io` and
   touch disk, network, or the process environment. The only impure code.
2. **Adapters** — pure functions that translate between external formats
   and the domain model. Parsing YAML text into `Frontmatter` structs,
   rendering `Site` data into HTML strings. No I/O, no side effects.
3. **Logic** — pure decision functions. Routing, content resolution,
   shortcode dispatch. Take domain data in, return domain data out.
4. **Models** — domain data structures. `PageKind`, `Frontmatter`,
   `Page`, `Site`, `SiteConfig`. Tagged unions and structs — no
   behaviour, just shape.
5. **Controller** — the orchestrator (in `main.zig`). Calls ports to
   get data in, passes it through adapters and logic, calls ports to
   push data out. The only place where impure and pure coexist.

The guarantee: any function that doesn't take `std.Io` is pure. If you
can't see `Io` in the signature, the function is deterministic and
side-effect-free. This is the same discipline Haskell enforces with `IO`
types, but in Zig it's by convention — the architecture makes the pit of
success obvious.

The shape "function takes inputs, returns owned output" maps naturally to
Zig: take an `Allocator`, take input, return `!OwnedThing`. Caller frees.
This is referential transparency with explicit resource management.

### 3.2 Arenas are the FP trick

For each unit of work (a single page render, a single build pass), allocate
from a `std.heap.ArenaAllocator`. Inside the arena, the function behaves as
if it had a garbage collector — allocate freely, intermediate slices live
as long as needed, no per-allocation `defer` ceremony. When the page is
written, drop the arena. **One free, many allocs.** Faster than a tracing
GC and keeps pure functions ergonomic.

Rule of thumb:
- **Long-lived data** (site config, content index) → general-purpose
  allocator (`std.heap.GeneralPurposeAllocator` or `init.gpa`).
- **Per-page scratch** (markdown AST, intermediate strings) → per-page
  arena, drop after write.
- **Build-wide temporaries** (the page list, routing tables) → build-scoped
  arena.

### 3.3 Errors as values

Zig's `!T` (error union) *is* `Either Error T` from ML-family languages.
Use it everywhere. Don't invent a custom `Result` type. Don't panic in
library code. Propagate via `try`; recover via `catch`.

### 3.4 Tagged unions for ADTs

`union(enum)` is Zig's algebraic data type. Use it for anything with a
fixed set of shapes:

```zig
const Page = union(enum) {
    post: PostMeta,
    page: PageMeta,
    gallery: GalleryMeta,
    home,
};
```

`switch` on the tag is exhaustive — the compiler errors if you forget a
case. This is your pattern matching.

### 3.5 No globals, no singletons

Everything is passed explicitly: `Allocator`, `Io`, configuration. Zig
already wants this; the FP discipline is "do it consistently."

### 3.6 What FP idioms to skip in Zig

- **Don't build a Monad abstraction.** Error unions + tagged unions cover
  what you'd reach for. Stay direct.
- **Don't replicate Haskell typeclasses via comptime.** Comptime can do it,
  but the code becomes inscrutable. Use plain structs with method fields
  or vtables when polymorphism is genuinely needed.
- **Don't go point-free.** Zig reads better with explicit named
  intermediates.
- **No higher-kinded types, no laziness, no persistent data structures.**
  Don't try to recreate them. Arenas + copy-on-write where needed.

---

## 4. Stack decisions

| Concern | Choice | Rationale |
|---|---|---|
| Language | **Zig 0.16+** | New `std.Io` interface; landed early 2026. Bleeding edge but the SSG only needs `Io.Threaded`, the stable subset. Expect API churn in 0.17. |
| Markdown parser | **md4c** via `@cImport` | ~3K LOC C lib, MIT, callback-based API maps cleanly to Zig structs. GFM via flags. C-interop is itself a Zig learning exercise. |
| Frontmatter | **YAML subset, hand-rolled** | Standard syntax (Jekyll/Hugo/Astro convention), no third-party YAML lib needed. Supports flat key/value, lists, strings/ints/bools — ~150 lines of Zig. Good parsing exercise. |
| Templating | **Custom, ~100–200 lines** | Mustache-lite: `{{ var }}`, `{{# section }}`, `{{> partial }}`. Building it teaches comptime + string handling. |
| CLI parsing | **`zig-clap`** (third-party) or hand-rolled | ~5 subcommands; either is fine. Start hand-rolled, switch if it gets messy. |
| HTTP (dev only) | **`std.http.Server` + `Io.Threaded`** | Localhost, low concurrency. Fits the new `Io` story perfectly. |
| Browser reload | **Server-Sent Events (SSE)** | One-way "reload now" signal. Just `text/event-stream`, no WebSocket library needed. |
| File watching | v0: shell out to **`watchexec`**. v1: native **`kqueue` (macOS) / `inotify` (Linux)** | Defer native watching — get the rest working first. |
| Image processing (optional) | **libvips** or **stb_image_resize** via `@cImport` | Only for thumbnails. Deferred. |
| Build system | **Zig's own `build.zig`** | Native. Learning `build.zig` is part of the curve. |
| Output target | Static HTML + CSS + tiny JS → **GitHub Pages** | Keep current CNAME / hosting. |

---

## 5. Content model & page resolution

### 5.1 Directory layout

```
zig-nota-site/
├── site.yaml                  # site config: title, base URL, menu, sections
├── content/
│   ├── _index.md              # home page (content + metadata)
│   ├── posts/
│   │   ├── _index.md          # optional: section description above /posts/
│   │   ├── hello-world.md
│   │   └── another-post.md
│   ├── pages/
│   │   ├── about.md
│   │   └── now.md
│   └── galleries/
│       ├── _index.md          # optional: section description above /galleries/
│       └── trip-2025/
│           ├── _index.md      # gallery title, description, image order
│           ├── 01.jpg
│           ├── 02.jpg
│           └── ...
├── templates/
│   ├── home.html
│   ├── post.html
│   ├── page.html
│   ├── posts-list.html
│   ├── gallery.html
│   └── partials/
│       ├── header.html
│       └── footer.html
├── static/
│   ├── css/
│   ├── js/gallery.js          # lightbox JS
│   └── img/
└── dist/                      # build output (gitignored)
```

### 5.2 The `_index.md` convention (from Hugo / Zola)

The underscore prefix signals "this file is metadata *about the folder
itself*, not a leaf page *inside* the folder." Without it, you'd have
ambiguity: is `posts/index.md` the page at `/posts/index/` or the
descriptor for `/posts/`?

Three uses in zig-nota:

1. `content/_index.md` → the home page. Its content is rendered into the
   home template; its frontmatter sets the home title and meta tags.
2. `content/<section>/_index.md` → optional. If present, its content is
   rendered above the auto-generated section listing.
3. `content/galleries/<name>/_index.md` → the gallery descriptor. Its
   frontmatter holds title, description, and (optionally) image
   ordering/captions. Its content is rendered as the gallery's intro
   prose.

Leaf pages don't get an underscore. `posts/hello-world.md` is a leaf.

### 5.3 Frontmatter (YAML)

```markdown
---
title: Hello, World
date: 2026-05-18T10:00:00Z
tags: [zig, blogging]
description: First post on the new SSG.
menus: []
---

# Hello!

Body markdown starts here.
```

Fields:
- `title` (required for posts/pages)
- `date` (RFC3339; defaults to file mtime if omitted)
- `tags` (list of strings; optional)
- `description` (string; used in RSS and meta tags)
- `menus` (list of strings; e.g. `[main]` to add to main menu)
- `slug` (string; defaults to filename without extension)
- `draft` (bool; if true, excluded unless `--drafts` flag)

For gallery `_index.md` files, additional fields:
- `cover` (string; filename of cover image)
- `images` (list; optional explicit ordering and captions — if omitted,
  files are sorted alphabetically with empty captions)

```yaml
---
title: Trip 2025
date: 2025-08-12
description: A week in the mountains.
cover: 03.jpg
images:
  - { file: 01.jpg, caption: Arriving at dusk }
  - { file: 02.jpg, caption: }
  - { file: 03.jpg, caption: The cabin }
---
```

**Override semantics (for migration):** all fields are optional. Defaults
come from filename (slug) and mtime (date). Anything in frontmatter wins.
This is the migration path: copy `data.edn` entries into frontmatter, no
more central registry.

### 5.4 Page kinds & resolution

| File path | Kind | Output URL | Template |
|---|---|---|---|
| `content/_index.md` | `home` | `/` | `home.html` |
| `content/posts/foo.md` | `post` | `/posts/foo/` | `post.html` |
| `content/posts/_index.md` | `section_list` | (rendered into `/posts/`) | `posts-list.html` |
| `content/pages/about.md` | `page` | `/about/` | `page.html` |
| `content/galleries/trip-2025/_index.md` | `gallery` | `/galleries/trip-2025/` | `gallery.html` |
| (auto) | `section_list` | `/posts/`, `/galleries/` | `posts-list.html` |

### 5.5 Template binding (how a source file maps to a template)

Not magic — a deterministic, code-level mapping in the SSG. Two pieces:

**1. File path → page kind** (inferred by the SSG from where the file
sits):

```
content/_index.md                     → kind = home
content/posts/_index.md               → kind = section_list (of /posts/)
content/posts/<anything>.md           → kind = post
content/pages/<anything>.md           → kind = page
content/galleries/_index.md           → kind = section_list (of /galleries/)
content/galleries/<dir>/_index.md     → kind = gallery
```

**2. Kind → template name** (hardcoded dispatch):

```zig
fn templateFor(kind: PageKind) []const u8 {
    return switch (kind) {
        .home         => "home.html",
        .post         => "post.html",
        .page         => "page.html",
        .section_list => "posts-list.html",
        .gallery      => "gallery.html",
    };
}
```

That's the whole "binding" — a `switch` statement. No filename matching,
no glob magic.

**For section lists**, the SSG does extra work because they're composite —
prose from `_index.md` plus an auto-generated listing of siblings:

```zig
// when kind == .section_list:
const ctx = SectionListContext{
    .site         = site_config,
    .section      = parseFrontmatter(index_md),     // title, description
    .section_html = renderMarkdown(index_md_body),  // prose
    .posts        = gatherSiblings("content/posts/"),
};
const html = templater.render("posts-list.html", ctx);
```

The template sees both halves:

```html
<!-- posts-list.html -->
<h1>{{ section.title }}</h1>
{{{ section_html }}}              <!-- the _index.md prose, raw HTML -->
<ul>
  {{# posts }}
  <li><a href="{{ url }}">{{ title }}</a> — {{ date }}</li>
  {{/ posts }}
</ul>
```

So: **the SSG owns the binding.** `_index.md` doesn't declare its template
anywhere — the SSG just *knows* (via the `switch`) that `section_list`
uses `posts-list.html`, and *knows* (via convention) that section pages
get prose from `_index.md` and a list from sibling files.

**Future flexibility** (not v1): allow `layout: foo.html` in frontmatter
to override the default template, and/or a template lookup hierarchy
(`layouts/posts/list.html` overrides `layouts/list.html`). Hugo and Zola
do this. We can add it when we hit a case that needs it.

### 5.6 Menus

Two ways, additive:

1. **Config-driven** (primary, explicit):
   ```yaml
   # site.yaml
   title: rafael.delboni.cc
   base_url: https://rafael.delboni.cc
   menu:
     main:
       - { name: Home,      url: / }
       - { name: Posts,     url: /posts/ }
       - { name: About,     url: /about/ }
       - { name: Galleries, url: /galleries/ }
   ```

2. **Frontmatter opt-in** (additive):
   Any page with `menus: [main]` is appended to that menu with `name = title`.
   Useful for occasional pages without editing `site.yaml`.

Templates receive the resolved menu (config + opt-ins) and iterate it in
the header partial.

### 5.7 Section listings

`/posts/` and `/galleries/` are auto-generated from the files in those
directories. Sorted by date descending. Drafts excluded by default.
Rendered via `posts-list.html` (and optionally a separate
`galleries-list.html`).

If `_index.md` exists in the section folder, its content is rendered above
the listing (see 5.5).

---

## 6. Shortcodes (in-markdown components)

A first-class component system: write `{{< name args... >}}` in any
markdown body, and the SSG expands it to HTML during a pre-processing pass
before md4c sees the document. CommonMark passes raw block HTML through
unchanged, so the expanded HTML survives parsing.

### 6.1 Built-in shortcodes (v1)

| Shortcode | Effect |
|---|---|
| `{{< gallery "trip-2025" >}}` | Inline a gallery from `content/galleries/trip-2025/` |
| `{{< post-list limit=10 >}}` | Render the N most recent posts as `<ul>` |
| `{{< post-list tag="zig" limit=5 >}}` | Filter by tag |
| `{{< page-list >}}` | List all (non-draft) pages |
| `{{< toc >}}` | Auto-generate table of contents from headings in this page |
| `{{< asset "diagrams/foo.svg" >}}` | Inline an SVG / asset with correct path |

### 6.2 Architecture

Each shortcode is a pure function:

```zig
pub const Shortcode = fn (
    allocator: Allocator,
    args: ShortcodeArgs,
    ctx: SiteContext,
) anyerror![]const u8;  // returns HTML
```

Registered in a comptime-known map:

```zig
const shortcodes = std.StaticStringMap(Shortcode).initComptime(.{
    .{ "gallery",   galleryShortcode },
    .{ "post-list", postListShortcode },
    .{ "page-list", pageListShortcode },
    .{ "toc",       tocShortcode },
    .{ "asset",     assetShortcode },
});
```

Pre-processing pass: scan markdown line-by-line, find `{{< name ... >}}`,
parse args, look up handler, call, splice result. Adding a new shortcode =
add one function and one map entry.

### 6.3 Arg syntax

Positional and keyword args:
```
{{< post-list limit=10 tag="zig" >}}
{{< gallery "trip-2025" >}}
{{< toc depth=3 >}}
```

Keep it simple: space-separated, quoted strings for values with spaces.
Parse with a small hand-rolled lexer (similar in spirit to the YAML
parser — another tight Zig exercise).

---

## 7. Architecture: ports & adapters in Zig

Following [Mark Seemann's insight](https://blog.ploeh.dk/2016/03/18/functional-architecture-is-ports-and-adapters/):
functional architecture *is* ports and adapters. The discipline is purity
at the center, impurity at the edges. In Zig, the signal is `std.Io` — if
a function takes `Io`, it's a port (impure). If it doesn't, it's pure.

There are no vtable interfaces, no dependency injection containers, no
abstract factories. Just functions, with the type signature telling you
whether they touch the outside world.

### 7.1 The five layers

```
┌─────────────────────────────────────────────────────────┐
│  Controller (main.zig)                                  │
│  The only place impure and pure coexist. Orchestrates   │
│  the pipeline: calls ports, feeds data through adapters  │
│  and logic, calls ports to write results out.            │
├─────────────────────────────────────────────────────────┤
│  Ports (impure — all take std.Io)                       │
│  Read content from disk, write HTML to disk, watch       │
│  files, serve HTTP. These are the boundaries.           │
├─────────────────────────────────────────────────────────┤
│  Adapters (pure — translate external ↔ domain)          │
│  Parse YAML text → Frontmatter. Render Site → HTML.     │
│  Parse markdown → HTML. No I/O, no side effects.        │
├─────────────────────────────────────────────────────────┤
│  Logic (pure — decisions on domain data)                 │
│  Route filepaths to URLs. Resolve menus. Dispatch        │
│  shortcodes. Build the Site index. No I/O.               │
├─────────────────────────────────────────────────────────┤
│  Models (pure — data structures only)                   │
│  PageKind, Frontmatter, Page, Site, SiteConfig.         │
│  Tagged unions and structs. No behaviour, just shape.   │
└─────────────────────────────────────────────────────────┘
```

### 7.2 Ports (impure)

Every port function takes `std.Io` as a parameter. That's the contract —
if you see `Io` in the signature, the function talks to the outside world.

- **`fs_reader`** — walk `content/` and read source files. Returns raw
  bytes; does no parsing.
- **`fs_writer`** — write rendered HTML to `dist/`.
- **`http_server`** — dev server + SSE reload signal.
- **`watcher`** — detect file changes (v0: shell out to `watchexec`;
  v2: native `kqueue`/`inotify`).

### 7.3 Adapters (pure transforms)

Adapters translate between external formats and the domain model. They are
pure functions: take data in, return data out. No `Io`, no `Allocator`
needed for the transform itself (scratch allocations use an arena the
caller provides).

- **`frontmatter`** — raw text → `Frontmatter` struct
- **`markdown`** — raw markdown bytes → HTML string (md4c wrapper)
- **`template`** — domain data + template text → final HTML
- **`config`** — raw YAML text → `SiteConfig` struct
- **`rss`** — `[]Post` → RSS XML string

### 7.4 Logic (pure decisions)

Logic functions take domain data in, return domain data out. No I/O, no
parsing, no rendering — just decisions.

- **`route`** — filepath → `PageKind` → output URL
- **`resolve`** — build `Site` index from parsed pages, resolve menus
- **`shortcode`** — registry + arg parsing + dispatch (the expansion
  itself may call adapters, but the dispatch decision is pure)

### 7.5 Models (data structures)

Plain structs and tagged unions. No methods, no behaviour.

- `PageKind` — tagged union: `.home`, `.post`, `.page`, `.gallery`,
  `.section_list`
- `Frontmatter` — parsed metadata from YAML header
- `Page` — a fully resolved content unit (kind + frontmatter + body)
- `Site` — the complete content index (all pages, menus, config)
- `SiteConfig` — parsed from `site.yaml`

### 7.6 Controller (orchestrator)

`main.zig` is the controller — the only file where impure and pure
coexist. It calls ports to get data in, passes data through adapters and
logic, and calls ports to push data out.

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    // ── Port: read raw data from disk ──
    const raw_sources = try fs_reader.readContentDir(io, allocator, "content/");
    const raw_config = try fs_reader.readFile(io, allocator, "site.yaml");

    // ── Adapter: parse into domain model ──
    const site_config = try config.parse(allocator, raw_config);
    var pages = std.ArrayList(Page).init(allocator);
    for (raw_sources) |src| {
        const fm = try frontmatter.parse(allocator, src.frontmatter_text);
        const html = try markdown.toHtml(allocator, src.body);
        const kind = route.pageKind(src.filepath);
        try pages.append(Page{ .kind = kind, .fm = fm, .body = html });
    }

    // ── Logic: build site index ──
    const site = try resolve.buildSite(allocator, pages.items, site_config);

    // ── Adapter: render each page ──
    for (site.pages) |page| {
        const html = try template.render(allocator, page, site);
        // ── Port: write to disk ──
        try fs_writer.writePage(io, page.url_path, html);
    }
}
```

Notice the shape: port → adapter → logic → adapter → port. The impure
calls are at the edges. The interior of the pipeline is entirely pure.
`Io` only appears when we talk to disk.

### 7.7 File structure

```
src/
├── main.zig                  # Controller: CLI entry, pipeline orchestration
├── models.zig                # PageKind, Frontmatter, Page, Site, SiteConfig
├── logic/                    # Pure decisions (no Io, no parsing)
│   ├── route.zig             # filepath → PageKind → URL
│   ├── resolve.zig           # build Site index, resolve menus
│   └── shortcode.zig         # shortcode registry, arg parsing, dispatch
├── adapters/                 # Pure transforms (external format ↔ domain)
│   ├── frontmatter.zig       # raw text → Frontmatter
│   ├── markdown.zig          # md bytes → HTML (md4c wrapper)
│   ├── template.zig          # domain data + template → HTML
│   ├── rss.zig               # []Post → RSS XML
│   └── config.zig            # raw YAML → SiteConfig
└── ports/                    # Impure I/O (all take std.Io)
    ├── fs_reader.zig          # walk content/, read files
    ├── fs_writer.zig          # write HTML to dist/
    ├── http_server.zig        # dev server + SSE reload
    └── watcher.zig            # file change detection
```

The import discipline enforces the architecture:
- `logic/` imports only `models` and other `logic/` files.
- `adapters/` imports only `models` and `logic/`.
- `ports/` imports only `models` — they hand raw data to the controller,
  which passes it to adapters.
- `main.zig` imports everything — it's the composition root.

No file in `logic/` or `adapters/` ever imports from `ports/`. If it does,
the architecture is violated.

### 7.8 What's NOT a port or adapter

- The markdown parser (md4c). It's a C library we call directly from the
  `markdown` adapter. Wrapping it in a port adds indirection for zero
  benefit — we're committed to md4c.
- The template engine. Small custom impl, no reason to abstract.
- Shortcodes. They *are* the extension surface; no port needed.

### 7.9 How `std.Io` fits

In Zig 0.16, any function doing I/O takes an `Io` parameter (like
`Allocator`). Port functions are `Io`-aware; adapter and logic functions
never are:

```zig
// Port — takes Io (impure)
pub fn readContentDir(io: std.Io, allocator: Allocator, root: []const u8) ![]RawSource { ... }

// Adapter — no Io (pure)
pub fn parseFrontmatter(allocator: Allocator, text: []const u8) !Frontmatter { ... }

// Logic — no Io (pure)
pub fn pageKind(filepath: []const u8) PageKind { ... }
```

Use `std.Io.Threaded` everywhere — stable, well-tested. The whole pipeline
can run on a thread pool: each page renders in parallel.

---

## 8. CLI surface

```
zig-nota new post "Title" [-d "description"] [-t "tag1,tag2"]
zig-nota new page "Title" [-s slug]
zig-nota new gallery "Title"
zig-nota build [--drafts] [--out dist/]
zig-nota serve [--port 8000]
zig-nota migrate <path-to-data.edn> <path-to-current-content/>
```

- `new` commands prompt for confirmation (mirroring current `bb new:post`).
- `build` wipes and rebuilds `dist/`.
- `serve` runs `build` once, then watches and rebuilds on change.
- `migrate` is one-shot: reads `data.edn`, converts each entry to YAML
  frontmatter, prepends it to the corresponding `.md`. Run once, delete
  data.edn.

---

## 9. Dev workflow (`serve`)

```
┌──────────┐    fs change     ┌──────────┐   rebuild    ┌──────────┐
│  nvim    │ ───────────────▶ │ Watcher  │ ───────────▶ │ Builder  │
└──────────┘                  └──────────┘              └─────┬────┘
                                                              │ writes
                                                              ▼
                                                       ┌──────────┐
┌──────────┐  SSE "reload"    ┌──────────┐  serves     │ MemOutput│
│ Browser  │ ◀─────────────── │  HTTP    │ ◀────────── │  (memory)│
└──────────┘                  └──────────┘             └──────────┘
       ▲
       │  location.reload() on SSE message
```

Browser-side: inject this snippet into pages only during `serve`:
```html
<script>
  new EventSource('/__dev').onmessage = () => location.reload();
</script>
```

Server-side: hold open the `/__dev` connection. On rebuild, write a single
`data:` line to all open connections.

---

## 10. Migration plan (from current `nota`)

Current state:
- Markdown files at `resources/public/posts/*.md` and
  `resources/public/pages/*.md`
- Metadata in `src/data.edn` (single EDN map with posts, pages, tags)

Steps (one-shot, scripted):

1. **Parse** `src/data.edn`. Easiest: write the migration script in
   **Babashka**, not Zig. The user is fluent in bb and EDN.
2. **For each post entry**: read source markdown, build YAML frontmatter
   from EDN keys (`:post/name → title`, `:post/timestamp → date` (epoch
   ms → RFC3339), `:post/tags → tags`, `:post/description → description`,
   `:slug/id → slug`), prepend to body, write to `content/posts/<slug>.md`.
3. **Same for pages** under `content/pages/`.
4. **Tags**: nota's tag-name override is niche. Skip for v1.
5. **Verify**: run `zig-nota build`, diff output URLs against current
   sitemap. Slugs should match.

Resist the urge to write the migration in Zig "for consistency." Zig is
for the SSG; bb is for the one-shot.

---

## 11. Milestones

### v0 — "It renders one post" (weekend)
- Read a single `.md` from a hardcoded path
- Parse YAML frontmatter (hand-rolled subset)
- Render body via md4c (CommonMark only, no GFM)
- Substitute into a single hardcoded HTML template
- Write to `dist/index.html`
- **Goal:** prove md4c bindings work, prove templating works, feel out
  arena allocators.

### v1 — "Functional blog" (1–2 weeks)
- Multiple content kinds (post, page, home, gallery)
- `_index.md` resolution for home, sections, galleries
- Section listing pages
- Menus (config + frontmatter opt-in)
- RSS feed
- GFM extensions (tables, strikethrough, task lists, autolinks)
- All CLI `new` commands
- `migrate` command works against real data.edn
- Shortcodes: `post-list`, `page-list`, `toc`
- **Goal:** deployable replacement for the current blog.

### v2 — "Developer experience" (1 week)
- `serve` subcommand
- File watcher (v0: shell out; v1: native kqueue/inotify)
- SSE-based browser reload
- Incremental builds (only rebuild changed pages)
- **Goal:** writing a post end-to-end feels good.

### v3 — "Polish" (open-ended)
- Gallery shortcode + lightbox JS
- Image optimization (thumbnails via libvips)
- Maybe: search index (lunr-style, build-time)

---

## 12. Zig-specific gotchas (mentor reference)

- **`defer` runs in reverse order.** `defer free(a); defer free(b)` frees
  `b` first.
- **Allocator passing is non-optional.** Functions that allocate take
  `Allocator` as a parameter by convention. Returning allocated memory
  transfers ownership.
- **`[]const u8` vs `[*:0]const u8`.** Slices know their length; C strings
  are null-terminated pointers. Be deliberate at the C boundary.
- **Error sets are inferred.** A function returning `!T` infers its error
  set from all `try` calls inside. Naming the set explicitly (`MyError!T`)
  is good practice once it stabilizes.
- **`comptime` is regular code that runs at compile time.** Not macros.
  Same syntax, same type system.
- **`@cImport` resolves C headers at compile time.** The result is a
  Zig namespace; functions become regular functions.
- **No string type.** Strings are `[]const u8`. Immutable byte slices.
  Compare with `std.mem.eql(u8, a, b)`, not `==`.
- **No null by default.** Optionals are `?T`. Unwrap with `orelse` or
  `if (opt) |val| { ... }`.
- **`unreachable` is a panic in Debug, UB in ReleaseFast.** Use only when
  you've proven the case can't happen.
- **Integer types are explicit.** No implicit widening. `@intCast`, `@as`,
  `@truncate`.
- **`std.heap.ArenaAllocator` is your FP best friend.** Every per-unit
  pure-ish function gets one.

---

## 13. Open questions

1. **Template engine**: hand-rolled vs port a small existing template DSL?
   (Recommendation: hand-rolled — small enough, great Zig exercise.)
2. **CSS pipeline**: keep Sass, simplify to plain CSS, or move to Tailwind /
   Lightning CSS? (Open. Personal preference.)
3. **Repo location**: new repo `zig-nota` (the framework) and
   `rafael.delboni.cc` stays as the content/config? Or merge them?
   (Recommendation: split — same separation the current `nota` template
   enforces.)
4. **License**: Unlicense (current site) or something else for the SSG?
   (Open.)

---

## 14. References

- [Mark Seemann — Functional architecture is Ports and Adapters](https://blog.ploeh.dk/2016/03/18/functional-architecture-is-ports-and-adapters/)
- [Zig 0.16 release notes](https://ziglang.org/download/0.16.0/release-notes.html)
- [Andrew Kelley — Zig's New Async I/O (text version)](https://andrewkelley.me/post/zig-new-async-io-text-version.html)
- [Loris Cro — Zig's New Async I/O](https://kristoff.it/blog/zig-new-async-io/)
- [md4c (markdown parser, MIT C lib)](https://github.com/mity/md4c)
- [zig-clap — CLI arg parsing](https://github.com/Hejsil/zig-clap)
- [PhotoSwipe — vanilla JS lightbox](https://photoswipe.com/)
- [Hugo content organization (`_index.md` convention reference)](https://gohugo.io/content-management/organization/)
- [nota (current template)](https://github.com/rafaeldelboni/nota)
- [Current blog repo](https://github.com/rafaeldelboni/rafaeldelboni.github.io)
