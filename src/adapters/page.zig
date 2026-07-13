const std = @import("std");

const config = @import("../logic/config.zig");
const config_adapter = @import("config.zig");
const template = @import("template.zig");
const models = @import("../models.zig");
const Context = models.Context;
const Page = models.Page;
const Site = models.Site;
const Templates = models.Templates;

/// Builds the output file path for a page, varying by page kind.
pub fn parseFilePath(
    arena: *std.heap.ArenaAllocator,
    output_dir: []const u8,
    output_index: []const u8,
    page: Page,
) ![]const u8 {
    const allocator = arena.allocator();
    const url = page.context.map.get("url").?.string;
    return switch (page.kind) {
        .atom_feed => try std.Io.Dir.path.join(allocator, &.{ output_dir, url }),
        else => try std.Io.Dir.path.join(allocator, &.{ output_dir, url, output_index }),
    };
}

/// Renders a page by merging its context with site data and applying the matching template.
pub fn parse(
    arena: *std.heap.ArenaAllocator,
    page: Page,
    posts_list: []Context,
    site_data: Site,
) ![]const u8 {
    const allocator = arena.allocator();
    var context: Context = .{ .map = try page.context.map.clone(allocator) };
    try context.map.put(allocator, "base_url", .{ .string = site_data.base_url });
    try context.map.put(allocator, "posts", .{ .list = posts_list });
    try context.map.put(allocator, "menu_main", .{ .list = site_data.menu_main });
    try context.map.put(allocator, "base_path", .{ .string = try config_adapter.basePath(allocator, site_data.base_uri) });
    try context.map.put(allocator, "year", .{ .string = try std.fmt.allocPrint(allocator, "{d}", .{site_data.now.year}) });
    try context.map.put(allocator, "site_version", .{ .string = site_data.version });
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

test "parseFilePath atom feed is single file without index wrapper" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var context: Context = .{};
    try context.map.put(allocator, "url", .{ .string = "feed.atom" });

    const page: Page = .{ .kind = .atom_feed, .context = context };
    const result = try parseFilePath(&arena, "public", "index.html", page);
    try std.testing.expectEqualStrings("public/feed.atom", result);
}

test "parse renders page with template and context" {
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
        .author = "",
        .description = "",
        .version = "test",
        .now = .{ .sec = 0, .min = 0, .hour = 0, .day = 1, .month = 1, .year = 2003 },
        .templates = templates,
        .pages = &.{},
        .posts = &.{},
        .tags = .{},
        .menu_main = &.{},
    };

    const result = try parse(&arena, page, &.{}, site);
    try std.testing.expectEqualStrings("<h1>About</h1><p>Hello</p>", result);
}

test "parse renders atom feed with feed-specific context from page" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var page_context: Context = .{};
    try page_context.map.put(allocator, "site_title", .{ .string = "My Blog" });
    try page_context.map.put(allocator, "site_author", .{ .string = "Jane Doe" });
    try page_context.map.put(allocator, "site_description", .{ .string = "" });
    try page_context.map.put(allocator, "updated", .{ .string = "2003-12-13T18:30:02Z" });

    const page: Page = .{ .kind = .atom_feed, .context = page_context };

    var templates: Templates = .{};
    try templates.map.put(allocator, "feed.atom", "<feed><title>{{ site_title }}</title><updated>{{ updated }}</updated>" ++
        "<author><name>{{ site_author }}</name></author>" ++
        "<generator uri=\"https://github.com/rafaeldelboni/stabilis\" version=\"{{ site_version }}\">stabilis</generator>" ++
        "<rights>Copyright {{ year }} {{ site_author }}</rights>" ++
        "<subtitle>{{ site_description }}</subtitle>" ++
        "<id>{{ base_url }}/</id><link href=\"{{ base_url }}\"/></feed>");

    const site: Site = .{
        .title = "My Blog",
        .base_url = "example.com",
        .base_uri = try std.Uri.parse("https://example.com"),
        .author = "Jane Doe",
        .description = "",
        .version = "test",
        .now = .{ .sec = 2, .min = 30, .hour = 18, .day = 13, .month = 12, .year = 2003 },
        .templates = templates,
        .pages = &.{},
        .posts = &.{},
        .tags = .{},
        .menu_main = &.{},
    };

    const result = try parse(&arena, page, &.{}, site);
    try std.testing.expectEqualStrings(
        "<feed><title>My Blog</title><updated>2003-12-13T18:30:02Z</updated>" ++
            "<author><name>Jane Doe</name></author>" ++
            "<generator uri=\"https://github.com/rafaeldelboni/stabilis\" version=\"test\">stabilis</generator>" ++
            "<rights>Copyright 2003 Jane Doe</rights>" ++
            "<subtitle></subtitle>" ++
            "<id>example.com/</id><link href=\"example.com\"/></feed>",
        result,
    );
}
