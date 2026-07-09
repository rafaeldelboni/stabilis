# stabilis

> stabilis: steady, firm, stable.

A static site generator written in Zig Markdown in, static HTML out, no backend.

## Prerequisites

Building from source needs [Zig](https://ziglang.org/download/) `0.16.0` or newer. Prefer a prebuilt binary? The installer below needs no toolchain.

## Installation

Installs to `/usr/local/bin` by default; prefix with `sudo`, or use `--dir ~/.local/bin` to avoid that.

```bash
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash
```

Or with options:

```bash
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash -s -- --dir ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash -s -- --version v0.1.0
```

## Usage

```bash
# installed binary
stabilis [command] [options]
stabilis build example -d public

# straight from source
zig build run -- [command] [options]
zig build run -- build -S example
```

### Commands

```
stabilis - A static site generator

stabilis <command>

Commands:
  serve      Build and serve the site locally
  build      Build the site
  new        Scaffold new content
    post       Scaffold new post
    page       Scaffold new page

Global options:
    -S, --source-dir   Source directory [string]
    -h, --help         Show help [boolean]
    -v, --version      Print version [boolean]
```

## Configuration

Stabilis reads a `site.yaml` at the root of your source directory. `title` and `base_url` are required; everything else falls back to the built-in defaults shown below.

```yaml
# Required
title: Example Blog
base_url: https://example.com

# Optional menu
menu:
  main:
    - { name: Home, url: / }
    - { name: Posts, url: /posts/ }

# Optional layout overrides (defaults shown)
content_dir: content
templates_dir: templates
static_dir: static
posts_dir: posts
content_ext: .md
index_file_name: _index.md
output_index: index.html
post_url_prefix: /posts
template_home_file_name: home.html
template_post_file_name: post.html
template_page_file_name: page.html
template_post_list_file_name: post-list.html
template_tag_post_list_file_name: tag-post-list.html
```

## Built with

One external library does the heavy lifting:

- [md4c](https://github.com/mity/md4c) — fast C Markdown parser (CommonMark + GFM), used to render post bodies to HTML.

Everything else is written from scratch in Zig, a few of these may graduate into standalone libraries later:

- **CLI** — a comptime-driven command/flag parser with generated help *(planned to move into its own library)*.
- **YAML lexer** — a small reader for `site.yaml` and Markdown frontmatter.
- **Template engine** — Mustache-style rendering: variables, sections, partials, and HTML escaping.
- **Frontmatter parser** — pulls per-file metadata out of Markdown.

It's wired together with a functional ports & adapters architecture.

## TODO

Progress is tracked in [TODO.md](TODO.md).

## Contributing

Development commands, the architecture, and code conventions live in [CONTRIBUTING.md](CONTRIBUTING.md).  
Issues and PRs are highly encouraged.

## License

This is free and unencumbered software released into the public domain.  
See [LICENSE](LICENSE) or <https://unlicense.org>.
