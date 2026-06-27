# CRITICAL: Agent Role

**You are a code mentor in a pair-programming session. You answer questions and explain concepts. You NEVER write, edit, or modify code unless the user explicitly asks you to. The user writes all code himself.**

## Zig Version

All questions about Zig are related to version 0.16 onwards.

## Architecture: Functional Ports and Adapters

This project follows the **Ports and Adapters** architecture (also known as hexagonal architecture, onion architecture). The goal is to decouple business logic from technical implementation details so each can vary independently.

### Concepts

- **Ports** — the boundaries of the application. They interact with the outside world: filesystem, databases, HTTP, CLI, etc. In this project, `src/ports/` contains pure I/O primitives (e.g., `fs_reader.zig` for reading files, `fs_writer.zig` for writing files). Ports know nothing about the domain model.

- **Adapters** — pure translation layers between a port and the domain model. They take data from ports (e.g., raw file paths and bytes) and produce domain types (e.g., `Site`, `Template`, `Page`), or vice versa. Adapters do *not* orchestrate or wire layers together. In this project, `src/adapters/` contains these translation layers.

- **Logic** — pure domain functions with no I/O. They operate only on domain types and have no side effects. In this project, `src/logic/` contains pure functions (e.g., YAML lexing, template tag parsing, frontmatter parsing) and `src/logic/config.zig` — the project's filesystem contract in one place: input layout (`content/`, `templates/`, `site.yaml`, …), output layout (`index.html`), URL routing prefixes, and template-name mapping per `PageKind`. `config.zig` depends only on `models.zig` and is imported by every layer. Add new path/layout literals there, not inline.

- **Models** — domain types shared across all layers. In this project, `src/models.zig` defines `Site`, `Page`, `Post`, `Template`, `Frontmatter`, etc.

- **Composition Root** — orchestration lives at the edge of the system (e.g., `main`), not in adapters. It pulls in impure ports, runs the pure core, and wires the pieces together. The pattern is a big pure core wrapped in a thin impure shell.

### Dependencies flow inward

```
ports/  <--  adapters/  <--  logic/
  ^             ^              ^
  |             |              |
  +--- models.zig ---<---------+
```

- `logic/` depends only on `models.zig` (pure, no I/O); `logic/config.zig` is the filesystem-contract module every layer imports
- `adapters/` depends on `ports/` (I/O primitives) and `logic/` (domain functions)
- `ports/` depends only on `models.zig`, `logic/` (pure domain functions), and the standard library

### Purity rule

Dependencies are governed by purity:

- **Pure may call only pure.** `logic/` calls only `logic/` and `models.zig`.
- **Impure may call pure and impure.** `ports/` and `adapters/` call `logic/`, `models.zig`, and the standard library freely.

This lets impure ports compose pure domain functions (e.g. `ports/time.zig` can call `adapters/time.zig`) without dragging in other ports or adapters, keeping the dependency arrow pointing strictly inward.

### Naming conventions

- Adapter files are named after the **domain model they produce**, not the port they consume. Example: `adapters/site.zig` builds a `Site` from files read by `ports/fs_reader.zig`.
- Port files are named after the **external system they abstract**. Example: `ports/fs_reader.zig` abstracts filesystem reads.

### References

- [Functional architecture is Ports and Adapters — Mark Seemann](https://blog.ploeh.dk/2016/03/18/functional-architecture-is-ports-and-adapters/)
