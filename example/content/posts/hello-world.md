---
title: Hello, World
date: 2026-06-01T10:00:00Z
tags: [zig, blogging]
description: First post on the new SSG.
---

## Getting started

This is the **first post**. It has:

- Frontmatter with tags
- A date
- Markdown body

```zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello from Zig!\n", .{});
}
```

## Text and emphasis

Such hello much world, *consectetur adipisicing elit*, sed do eiusmod tempor
incididunt ut **labore et dolore magna aliqua**. ***Duis aute irure dolor*** in
reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
~~Excepteur sint occaecat~~ cupidatat non proident.

---

### Lists

Unordered, with nesting:

- item-1
  - sub-item-1
  - sub-item-2
- item-2
  - sub-item-3
  - sub-item-4
- item-3

Ordered, with nesting:

1. item-1
   1. sub-item-1
   2. sub-item-2
2. item-2
   1. sub-item-3
   2. sub-item-4
3. item-3

### Tables

Table Header-1 | Table Header-2 | Table Header-3
:--- | :---: | ---:
Table Data-1 | Table Data-2 | Table Data-3
TD-4 | Td-5 | TD-6

### Images

You can drop images right in:

![GitHub Logo](https://cloud.githubusercontent.com/assets/5456665/13322882/e74f6626-dc00-11e5-921d-f6d024a01eaa.png "GitHub")

### Links

A bare URL like https://github.com/rafaeldelboni/stabilis is **not** auto-linked,
but this is: [stabilis](https://github.com/rafaeldelboni/stabilis).
