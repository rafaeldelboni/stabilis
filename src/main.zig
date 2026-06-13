const std = @import("std");

const frontmatter = @import("adapters/frontmatter.zig");
const markdown = @import("adapters/markdown.zig");
const site = @import("adapters/site.zig");
const template = @import("adapters/template.zig");
const yaml_lexer = @import("adapters/yaml_lexer.zig");
const debug = @import("debug.zig");
const models = @import("models.zig");
const Context = models.Context;
const fs_reader = @import("ports/fs_reader.zig");
const fs_writer = @import("ports/fs_writer.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(init.gpa);
    const allocator = arena.allocator();
    defer arena.deinit();

    const output_dir = "public";

    const files = try fs_reader.walkDir(io, &arena, "example/");
    std.debug.print("Files: {s}\n", .{try debug.dumpJson(arena.allocator(), files)});
    const site_data = try site.parse(&arena, files);
    std.debug.print("Site: {s}\n", .{try debug.dumpJson(arena.allocator(), site_data)});

    var posts_list = std.ArrayList(Context).initCapacity(allocator, site_data.posts.len) catch unreachable;
    for (site_data.posts) |post| try posts_list.append(allocator, post.context);

    for (site_data.posts) |post| {
        var context: Context = post.context;
        try context.map.put(allocator, "posts", .{ .list = posts_list.items });
        try context.map.put(allocator, "menu_main", .{ .list = site_data.menu_main });
        const post_template = try template.pageKindToTemplate(post.kind, site_data.templates);
        const html = try template.render(&arena, post_template, site_data.templates, context);
        const post_slug = if (context.map.get("slug")) |v| v.string else error.PostSlugNotFound;
        const post_file_path = try std.Io.Dir.path.join(allocator, &.{ output_dir, "posts", try post_slug, "index.html" });
        std.debug.print("{s}\n", .{post_file_path});
        try fs_writer.writeFileDeep(io, html, post_file_path);
    }
}

test {
    _ = @import("adapters/frontmatter.zig");
    _ = @import("adapters/markdown.zig");
    _ = @import("adapters/site.zig");
    _ = @import("adapters/template.zig");
    _ = @import("adapters/yaml_lexer.zig");
    _ = @import("logic/frontmatter.zig");
    _ = @import("logic/site.zig");
    _ = @import("logic/template.zig");
    _ = @import("logic/yaml_lexer.zig");
    _ = @import("ports/fs_reader.zig");
    _ = @import("ports/fs_writer.zig");
    _ = @import("models.zig");
    _ = @import("string.zig");
}
