---
title: About
slug: about
menus: [main]
---

> stabilis: steady, firm, stable.

## Built with

One external library does the heavy lifting:

- [md4c](https://github.com/mity/md4c) — fast C Markdown parser (CommonMark + GFM), used to render post bodies to HTML.

Everything else is written from scratch in Zig — a few of these may graduate into standalone libraries later:

- **CLI** — a comptime-driven command/flag parser with generated help *(planned to move into its own library)*.
- **YAML lexer** — a small reader for `site.yaml` and Markdown frontmatter.
- **Template engine** — Mustache-style rendering: variables, sections, partials, and HTML escaping.
- **Frontmatter parser** — pulls per-file metadata out of Markdown.

It's all wired together with a functional [ports & adapters](https://blog.ploeh.dk/2016/03/18/functional-architecture-is-ports-and-adapters/) architecture: a pure domain core wrapped in a thin I/O shell.

## Contributing

Found a dead link, a mistake, or an improvement? [Issues](https://github.com/rafaeldelboni/stabilis/issues) and [PRs](https://github.com/rafaeldelboni/stabilis/pulls) are highly encouraged.

## License

This is free and unencumbered software released into the public domain.
For more information, please refer to <http://unlicense.org>
