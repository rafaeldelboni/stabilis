const std = @import("std");

const frontmatter = @import("adapters/frontmatter.zig");
const markdown = @import("adapters/markdown.zig");
const site = @import("adapters/site.zig");
const template = @import("adapters/template.zig");
const yaml_lexer = @import("adapters/yaml_lexer.zig");
const debug = @import("debug.zig");
const models = @import("models.zig");
const Context = models.Context;
const Page = models.Page;
const Site = models.Site;
const fs_reader = @import("ports/fs_reader.zig");
const fs_writer = @import("ports/fs_writer.zig");

fn buildFilePath(
    arena: *std.heap.ArenaAllocator,
    output_dir: []const u8,
    page: Page,
) ![]const u8 {
    const allocator = arena.allocator();
    switch (page.kind) {
        .post => {
            const post_slug = page.context.map.get("slug").?.string;
            return try std.Io.Dir.path.join(allocator, &.{ output_dir, "posts", post_slug, "index.html" });
        },
        .page => {
            const page_slug = page.context.map.get("slug").?.string;
            return try std.Io.Dir.path.join(allocator, &.{ output_dir, "posts", page_slug, "index.html" });
        },
        .home => return try std.Io.Dir.path.join(allocator, &.{ output_dir, "index.html" }),
        .post_list => return try std.Io.Dir.path.join(allocator, &.{ output_dir, "posts", "index.html" }),
    }
}

fn parsePageIntoHtml(
    arena: *std.heap.ArenaAllocator,
    page: Page,
    posts_list: []Context,
    site_data: Site,
) ![]const u8 {
    const allocator = arena.allocator();
    var context: Context = page.context;
    try context.map.put(allocator, "posts", .{ .list = posts_list });
    try context.map.put(allocator, "menu_main", .{ .list = site_data.menu_main });
    const post_template = try template.pageKindToTemplate(page.kind, site_data.templates);
    return try template.render(arena, post_template, site_data.templates, context);
}

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

    var posts_list = try std.ArrayList(Context).initCapacity(allocator, site_data.posts.len);
    for (site_data.posts) |post| try posts_list.append(allocator, post.context);

    for (site_data.posts) |post| {
        const file_path = try buildFilePath(&arena, output_dir, post);
        const html = try parsePageIntoHtml(&arena, post, posts_list.items, site_data);
        try fs_writer.writeFileDeep(io, html, file_path);
    }

    // TODO
    // for (site_data.pages) |page| {
    //     const file_path = try buildFilePath(&arena, output_dir, page);
    //     const html = try parsePageIntoHtml(&arena, page, posts_list.items, site_data);
    //     try fs_writer.writeFileDeep(io, html, file_path);
    // }
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
