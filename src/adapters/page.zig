const std = @import("std");

const config = @import("../logic/config.zig");
const config_adapter = @import("config.zig");
const template = @import("template.zig");
const models = @import("../models.zig");
const Context = models.Context;
const Page = models.Page;
const Site = models.Site;
const Templates = models.Templates;

/// Builds the output file path for a page as `output_dir/url/index.html`.
pub fn parseFilePath(
    arena: *std.heap.ArenaAllocator,
    output_dir: []const u8,
    output_index: []const u8,
    page: Page,
) ![]const u8 {
    const allocator = arena.allocator();
    const url = page.context.map.get("url").?.string;
    return try std.Io.Dir.path.join(allocator, &.{ output_dir, url, output_index });
}

/// Renders a page into HTML by merging its context with posts and menu, then applying the matching template.
pub fn parseHtml(
    arena: *std.heap.ArenaAllocator,
    page: Page,
    posts_list: []Context,
    site_data: Site,
) ![]const u8 {
    const allocator = arena.allocator();
    var context: Context = .{ .map = try page.context.map.clone(allocator) };
    try context.map.put(allocator, "posts", .{ .list = posts_list });
    try context.map.put(allocator, "menu_main", .{ .list = site_data.menu_main });
    try context.map.put(allocator, "base_path", .{ .string = try config_adapter.basePath(allocator, site_data.base_uri) });
    const post_template = try template.pageKindToTemplate(page.kind, site_data.templates);
    return try template.render(arena, post_template, site_data.templates, context);
}

test "parseFilePath builds output_dir/url/index.html" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var context: Context = .{};
    try context.map.put(allocator, "url", .{ .string = "posts/hello" });

    const page: Page = .{ .kind = .post, .context = context };
    const result = try parseFilePath(&arena, "public", "index.html", page);
    try std.testing.expectEqualStrings("public/posts/hello/index.html", result);
}

test "parseFilePath with root url" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var context: Context = .{};
    try context.map.put(allocator, "url", .{ .string = "" });

    const page: Page = .{ .kind = .home, .context = context };
    const result = try parseFilePath(&arena, "public", "index.html", page);
    try std.testing.expectEqualStrings("public/index.html", result);
}

test "parseHtml renders page with template and context" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var page_context: Context = .{};
    try page_context.map.put(allocator, "title", .{ .string = "About" });
    try page_context.map.put(allocator, "body", .{ .string = "<p>Hello</p>" });

    const page: Page = .{ .kind = .page, .context = page_context };

    var templates: Templates = .{};
    try templates.map.put(allocator, "page.html", "<h1>{{ title }}</h1>{{{ body }}}");

    const site: Site = .{
        .title = "Test",
        .base_url = "",
        .base_uri = .{ .scheme = "" },
        .templates = templates,
        .pages = &.{},
        .posts = &.{},
        .tags = .{},
        .menu_main = &.{},
    };

    const result = try parseHtml(&arena, page, &.{}, site);
    try std.testing.expectEqualStrings("<h1>About</h1><p>Hello</p>", result);
}
