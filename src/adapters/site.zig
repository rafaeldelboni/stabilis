const std = @import("std");

const debug = @import("../debug.zig");
const models = @import("../models.zig");
const File = models.File;
const MenuItem = models.MenuItem;
const MapEntries = models.MapEntries;
const Templates = models.Templates;
const YamlNode = models.YamlNode;
const Site = models.Site;

pub fn parse(
    arena: *std.heap.ArenaAllocator,
    config: MapEntries,
    files: []const File,
) !Site {
    const allocator = arena.allocator();
    // sequence
    // parse confg MapEntry array (title, base_url, menu_main)
    // parse files File array
    _ = files;
    // on each file detect type and
    //    parse templates
    //    parse pages
    //    parse posts
    //    parse posts
    var main_menu: std.ArrayList(MenuItem) = .empty;
    for (config.get("menu").?.map.get("main").?.list) |entry| {
        try main_menu.append(allocator, .{
            .name = entry.map.get("name").?.string,
            .url = entry.map.get("url").?.string,
        });
    }
    return Site{
        .title = config.get("title").?.string,
        .base_url = config.get("base_url").?.string,
        .menu_main = main_menu.items,
        .templates = std.StringHashMap([]const u8).init(allocator),
        .pages = &.{},
        .posts = &.{},
    };
}

test "smoke test" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const walkDirResult = [_]File{
        .{ .cwd_path = "/home/delboni/Workspaces/zig/stabilis", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/content/posts", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/content/posts/_index.md", .file_ext = ".md", .file_name = "_index.md" },
        .{ .cwd_path = "/home/delboni/Workspaces/zig/stabilis", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/content/posts", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/content/posts/hello-world.md", .file_ext = ".md", .file_name = "hello-world.md" },
        .{ .cwd_path = "/home/delboni/Workspaces/zig/stabilis", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/content", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/content/_index.md", .file_ext = ".md", .file_name = "_index.md" },
        .{ .cwd_path = "/home/delboni/Workspaces/zig/stabilis", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/partials", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/partials/header.html", .file_ext = ".html", .file_name = "header.html" },
        .{ .cwd_path = "/home/delboni/Workspaces/zig/stabilis", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/page.html", .file_ext = ".html", .file_name = "page.html" },
        .{ .cwd_path = "/home/delboni/Workspaces/zig/stabilis", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/home.html", .file_ext = ".html", .file_name = "home.html" },
        .{ .cwd_path = "/home/delboni/Workspaces/zig/stabilis", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/post.html", .file_ext = ".html", .file_name = "post.html" },
        .{ .cwd_path = "/home/delboni/Workspaces/zig/stabilis", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/post-list.html", .file_ext = ".html", .file_name = "post-list.html" },
        .{ .cwd_path = "/home/delboni/Workspaces/zig/stabilis", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/site.yaml", .file_ext = ".yaml", .file_name = "site.yaml" },
    };

    var home_map = MapEntries.init(arena.allocator());
    try home_map.put("name", .{ .string = "Home" });
    try home_map.put("url", .{ .string = "/" });

    var posts_map = MapEntries.init(arena.allocator());
    try posts_map.put("name", .{ .string = "Posts" });
    try posts_map.put("url", .{ .string = "/posts/" });

    var main_map = MapEntries.init(arena.allocator());
    try main_map.put("main", .{ .list = &[_]YamlNode{
        .{ .map = home_map },
        .{ .map = posts_map },
    } });

    var config = MapEntries.init(arena.allocator());
    try config.put("title", .{ .string = "Example Blog" });
    try config.put("base_url", .{ .string = "http://localhost:8000" });
    try config.put("menu", .{ .map = main_map });

    const results = try parse(&arena, config, &walkDirResult);
    try debug.printJson(&arena, results);
}
