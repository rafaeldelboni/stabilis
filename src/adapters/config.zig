const std = @import("std");

const config = @import("../logic/config.zig");
const models = @import("../models.zig");
const Context = models.Context;
const Config = models.Config;
const MapEntries = models.MapEntries;
const yaml_lexer = @import("yaml_lexer.zig");

fn strField(entries: MapEntries, key: []const u8, fallback: []const u8) []const u8 {
    if (entries.map.get(key)) |node| {
        if (node == .string) return node.string;
    }
    return fallback;
}

/// Normalized path prefix from `uri` (no trailing slash).
/// `http://localhost:8000` → `""`, `https://example.com/sub` → `"/sub"`.
pub fn basePath(allocator: std.mem.Allocator, base_uri: std.Uri) ![]const u8 {
    const path = switch (base_uri.path) {
        .raw, .percent_encoded => |s| s,
    };
    if (path.len == 0) return "";
    var trimmed = path;
    while (trimmed.len > 1 and trimmed[trimmed.len - 1] == '/') trimmed.len -= 1;
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "/")) return "";
    return try allocator.dupe(u8, trimmed);
}

fn parseMenuEntryContext(allocator: std.mem.Allocator, name: []const u8, url: []const u8) !Context {
    var ctx: Context = .{};
    try ctx.map.put(allocator, "name", .{ .string = name });
    const stripped = if (std.mem.startsWith(u8, url, "/")) url[1..] else url;
    try ctx.map.put(allocator, "url", .{ .string = stripped });
    return ctx;
}

test "basePath: empty for host-only url" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("", try basePath(a, try std.Uri.parse("http://localhost:8000")));
    try std.testing.expectEqualStrings("", try basePath(a, try std.Uri.parse("https://example.com")));
}

test "basePath: empty for root url" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("", try basePath(a, try std.Uri.parse("https://example.com/")));
}

test "basePath: single-segment path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("/stabilis", try basePath(a, try std.Uri.parse("https://example.com/stabilis")));
    try std.testing.expectEqualStrings("/stabilis", try basePath(a, try std.Uri.parse("https://example.com/stabilis/")));
}

test "basePath: multi-segment path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("/blog/sub", try basePath(a, try std.Uri.parse("https://example.com/blog/sub")));
    try std.testing.expectEqualStrings("/blog/sub", try basePath(a, try std.Uri.parse("https://example.com/blog/sub/")));
}

pub fn parse(arena: *std.heap.ArenaAllocator, config_file: []const u8) !Config {
    const allocator = arena.allocator();
    const site_config = try yaml_lexer.parse(arena, config_file);

    if (site_config.map.count() == 0) return error.EmptyConfig;

    const site_title =
        if (site_config.map.get("title")) |title| title.string else return error.NoConfigTitle;
    const site_base_url =
        if (site_config.map.get("base_url")) |base_url| base_url.string else return error.NoConfigBaseUrl;
    const site_base_uri = std.Uri.parse(site_base_url) catch std.Uri{ .scheme = "" };
    const site_author = strField(site_config, "author", site_title);
    const site_description = strField(site_config, "description", config.default_description);
    var menu_main: std.ArrayList(Context) = .empty;
    if (site_config.map.get("menu")) |menu| {
        if (menu.map.map.get("main")) |main| {
            for (main.list) |entry| {
                try menu_main.append(allocator, try parseMenuEntryContext(
                    allocator,
                    entry.map.map.get("name").?.string,
                    entry.map.map.get("url").?.string,
                ));
            }
        }
    }

    const content_dir = strField(site_config, "content_dir", config.default.content_dir);
    const templates_dir = strField(site_config, "templates_dir", config.default.templates_dir);
    const static_dir = strField(site_config, "static_dir", config.default.static_dir);
    const posts_dir = strField(site_config, "posts_dir", config.default.posts_dir);
    const content_ext = strField(site_config, "content_ext", config.default.content_ext);
    const index_file_name = strField(site_config, "index_file_name", config.default.index_file_name);
    const output_index = strField(site_config, "output_index", config.default.output_index);
    const template_home_file_name =
        strField(site_config, "template_home_file_name", config.default.template_home_file_name);
    const template_post_file_name =
        strField(site_config, "template_post_file_name", config.default.template_post_file_name);
    const template_page_file_name =
        strField(site_config, "template_page_file_name", config.default.template_page_file_name);
    const template_post_list_file_name =
        strField(site_config, "template_post_list_file_name", config.default.template_post_list_file_name);
    const template_tag_post_list_file_name =
        strField(site_config, "template_tag_post_list_file_name", config.default.template_tag_post_list_file_name);
    const template_atom_feed_file_name =
        strField(site_config, "template_atom_feed_file_name", config.default.template_atom_feed_file_name);
    const post_url_prefix = strField(site_config, "post_url_prefix", config.default.post_url_prefix);

    const home_page_path =
        try std.Io.Dir.path.join(allocator, &.{ content_dir, index_file_name });
    const post_list_path =
        try std.Io.Dir.path.join(allocator, &.{ content_dir, posts_dir, index_file_name });
    const posts_path_prefix = try std.mem.concat(allocator, u8, &.{
        try std.Io.Dir.path.join(allocator, &.{ content_dir, posts_dir }),
        "/",
    });
    const pages_path_prefix = try std.mem.concat(allocator, u8, &.{ content_dir, "/" });
    const templates_prefix = try std.mem.concat(allocator, u8, &.{ templates_dir, "/" });
    const tag_post_list_url_prefix =
        try std.Io.Dir.path.join(allocator, &.{ post_url_prefix, "tags" });

    return Config{
        .title = site_title,
        .base_url = site_base_url,
        .base_uri = site_base_uri,
        .author = site_author,
        .description = site_description,
        .menu_main = menu_main.items,

        .content_dir = content_dir,
        .templates_dir = templates_dir,
        .static_dir = static_dir,
        .posts_dir = posts_dir,
        .content_ext = content_ext,
        .index_file_name = index_file_name,
        .output_index = output_index,
        .template_home_file_name = template_home_file_name,
        .template_post_file_name = template_post_file_name,
        .template_page_file_name = template_page_file_name,
        .template_post_list_file_name = template_post_list_file_name,
        .template_tag_post_list_file_name = template_tag_post_list_file_name,
        .template_atom_feed_file_name = template_atom_feed_file_name,
        .post_url_prefix = post_url_prefix,

        .home_page_path = home_page_path,
        .post_list_path = post_list_path,
        .posts_path_prefix = posts_path_prefix,
        .pages_path_prefix = pages_path_prefix,
        .templates_prefix = templates_prefix,
        .tag_post_list_url_prefix = tag_post_list_url_prefix,
    };
}

test "parse: site metadata and default layout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const yaml =
        \\title: Example Blog
        \\base_url: http://localhost:8000
        \\author: Jane Doe
        \\description: A blog built with stabilis
        \\menu:
        \\  main:
        \\    - { name: Home, url: / }
        \\    - { name: Posts, url: /posts/ }
    ;

    const cfg = try parse(&arena, yaml);

    // site metadata from yaml
    try std.testing.expectEqualStrings("Example Blog", cfg.title);
    try std.testing.expectEqualStrings("http://localhost:8000", cfg.base_url);
    try std.testing.expectEqualStrings("Jane Doe", cfg.author);
    try std.testing.expectEqualStrings("A blog built with stabilis", cfg.description);
    try std.testing.expectEqual(@as(usize, 2), cfg.menu_main.len);
    try std.testing.expectEqualStrings("Home", cfg.menu_main[0].map.get("name").?.string);
    try std.testing.expectEqualStrings("", cfg.menu_main[0].map.get("url").?.string);
    try std.testing.expectEqualStrings("Posts", cfg.menu_main[1].map.get("name").?.string);
    try std.testing.expectEqualStrings("posts/", cfg.menu_main[1].map.get("url").?.string);

    // layout primitives fall back to static defaults (not in yaml)
    try std.testing.expectEqualStrings("content", cfg.content_dir);
    try std.testing.expectEqualStrings("posts", cfg.posts_dir);
    try std.testing.expectEqualStrings("_index.md", cfg.index_file_name);
    try std.testing.expectEqualStrings("/posts", cfg.post_url_prefix);

    // composed paths built from resolved primitives
    try std.testing.expectEqualStrings("content/_index.md", cfg.home_page_path);
    try std.testing.expectEqualStrings("content/posts/_index.md", cfg.post_list_path);
    try std.testing.expectEqualStrings("content/posts/", cfg.posts_path_prefix);
    try std.testing.expectEqualStrings("content/", cfg.pages_path_prefix);
    try std.testing.expectEqualStrings("templates/", cfg.templates_prefix);
    try std.testing.expectEqualStrings("/posts/tags", cfg.tag_post_list_url_prefix);
}

test "parse: yaml overrides layout primitive" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const yaml =
        \\title: T
        \\base_url: http://x
        \\menu:
        \\  main:
        \\    - { name: Home, url: / }
        \\posts_dir: blog
    ;

    const cfg = try parse(&arena, yaml);

    // primitive overridden
    try std.testing.expectEqualStrings("blog", cfg.posts_dir);

    // composed paths reflect the override
    try std.testing.expectEqualStrings("content/blog/_index.md", cfg.post_list_path);
    try std.testing.expectEqualStrings("content/blog/", cfg.posts_path_prefix);

    // non-overridden primitive still falls back
    try std.testing.expectEqualStrings("content", cfg.content_dir);
    try std.testing.expectEqualStrings("content/_index.md", cfg.home_page_path);
}

test "parse: author falls back to title when missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const yaml =
        \\title: My Site
        \\base_url: http://x
        \\menu:
        \\  main:
        \\    - { name: Home, url: / }
    ;

    const cfg = try parse(&arena, yaml);
    try std.testing.expectEqualStrings("My Site", cfg.author);
    try std.testing.expectEqualStrings("", cfg.description);
}
