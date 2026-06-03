const std = @import("std");

const frontmatter = @import("adapters/frontmatter.zig");
const markdown = @import("adapters/markdown.zig");
const yaml_lexer = @import("adapters/yaml_lexer.zig");
const debug = @import("debug.zig");
const fs_reader = @import("ports/fs_reader.zig");
const fs_writer = @import("ports/fs_writer.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const raw_file = try fs_reader.readFile(io, &arena, "test.md");
    std.debug.print("Raw: {s}\n", .{raw_file});

    const content = try frontmatter.parse(&arena, raw_file);
    const frontmatter_meta = content.frontmatter;
    std.debug.print("Frontmatter: {s}\n", .{try debug.dumpJson(arena.allocator(), frontmatter_meta)});
    const html = try markdown.toHtml(&arena, content.source);
    std.debug.print("Html: {s}", .{html});

    try fs_writer.writeFile(io, html, "test.html");
}

test {
    _ = @import("adapters/yaml_lexer.zig");
    _ = @import("adapters/frontmatter.zig");
    _ = @import("adapters/markdown.zig");
    _ = @import("string.zig");
    _ = @import("models.zig");
    _ = @import("ports/fs_reader.zig");
    _ = @import("ports/fs_writer.zig");
}
