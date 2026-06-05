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
