const std = @import("std");

const markdown = @import("adapters/markdown.zig");
const frontmatter = @import("adapters/frontmatter.zig");
const fs_reader = @import("ports/fs_reader.zig");
const fs_writer = @import("ports/fs_writer.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator: std.mem.Allocator = init.arena.allocator();

    // ── Port: read raw data from disk ──
    const raw_file = try fs_reader.readFile(io, allocator, "test.md");
    std.debug.print("Raw File: {s}\n", .{raw_file});

    // ── Adapter: transform markdown → HTML ──
    const html = try markdown.toHtml(allocator, raw_file);
    std.debug.print("Html: {s}", .{html});

    // ── Port: write rendered output to disk ──
    try fs_writer.writeFile(io, html, "test.html");
}
