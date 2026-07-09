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

menu:
  main:
    - { name: Home, url: / }
    - { name: Posts, url: /posts/ }
```

## Build

```bash
stabilis build example -d public    # build ./example into ./public
zig build run -- build -S example   # or straight from source
```

## Serve

Build and serve locally while you write:

```bash
stabilis serve -S example
```

## Scaffold content

```bash
stabilis new post "Hello World"     # → content/posts/hello-world.md
stabilis new page "About"           # → content/about.md
```

Add `-h` to any command for its options, or run `stabilis --version`.
