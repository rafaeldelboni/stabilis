---
title: stabilis
---

A static site generator written in Zig — Markdown in, static HTML out, no backend.

## Prerequisites

To build from source you need [Zig](https://ziglang.org/download/) `0.16.0` or newer. Prefer a prebuilt binary? Skip straight to Install — no toolchain required.

## Install

Installs to `/usr/local/bin` by default (prefix with `sudo`, or pass `--dir ~/.local/bin`):

```bash
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash
```

With options:

```bash
curl -fsSL .../install.sh | bash -s -- --dir ~/.local/bin
curl -fsSL .../install.sh | bash -s -- --version v0.1.0
```

## Configure

Stabilis reads a `site.yaml` at the root of your source directory. Only `title` and `base_url` are required; everything else falls back to sensible defaults.

```yaml
title: Example Blog
base_url: https://example.com

# Optional — author appears in the Atom feed and falls back to title if missing
author: John Doe

# Optional — site description, used as the feed subtitle
description: A blog built with stabilis

menu:
  main:
    - { name: Home, url: / }
    - { name: Posts, url: /posts/ }
```

## Atom feed

Stabilis generates an Atom 1.0 feed at `feed.atom` alongside the post list page. The feed includes:

- Feed-level: title, self-link, updated timestamp, author, generator (with version), copyright, subtitle, ID
- Per entry: title, link, ID, published/updated dates, categories (from tags), summary (from frontmatter `description`), content (entity-escaped HTML)

Feed readers discover it via the `<link rel="alternate" type="application/atom+xml">` in the page header.

## Init

Scaffold a new site from the bundled example:

```bash
stabilis init -d my-blog    # → ./my-blog with a working example site
```

When run from a release binary it downloads the matching example tarball; when run from source it copies the local `example/` directory. Refuses to init into a directory that already exists.

## Build

```bash
stabilis build -S example -d public    # build ./example into ./public
stabilis build -S example -u https://example.com/blog    # override base_url
zig build run -- build -S example   # or straight from source
```

`-u`/`--base-url` overrides the `base_url` from `site.yaml` — useful when deploying to a subdirectory (e.g. GitHub Pages). The path component becomes the prefix for all generated links.

## Serve

Build and serve locally while you write:

```bash
stabilis serve -S example
stabilis serve -S example -p 3000 -b 0.0.0.0    # custom port and bind
```

## Scaffold content

```bash
stabilis new post "Hello World"     # → content/posts/hello-world.md
stabilis new page "About"           # → content/about.md
```

Both refuse to overwrite an existing file. Add `-h` to any command for its options, or run `stabilis --version`.
