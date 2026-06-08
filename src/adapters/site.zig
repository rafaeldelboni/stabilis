const std = @import("std");

const debug = @import("../debug.zig");
const models = @import("../models.zig");
const File = models.File;
const MapEntry = models.MapEntry;
const Templates = models.Templates;
const YamlNode = models.YamlNode;
const Site = models.Site;

pub fn parse(
    arena: *std.heap.ArenaAllocator,
    config: []const MapEntry,
    files: []const File,
) !Site {
    const allocator = arena.allocator();
    // sequence
    // parse confg MapEntry array (title, base_url, menu_main)
    _ = config;
    // parse files File array
    _ = files;
    // on each file detect type and
    //    parse templates
    //    parse pages
    //    parse posts
    //    parse posts
    return Site{
        .title = "banana blog",
        .base_url = "banana/url",
        .menu_main = &.{},
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

    const config = [_]MapEntry{
        .{ .key = "title", .value = .{ .string = "Example Blog" } },
        .{ .key = "base_url", .value = .{ .string = "http://localhost:8000" } },
        .{ .key = "menu", .value = .{
            .map = &[_]MapEntry{
                .{ .key = "main", .value = .{
                    .list = &[_]YamlNode{
                        .{ .map = &[_]MapEntry{
                            .{ .key = "name", .value = .{ .string = "Home" } },
                            .{ .key = "url", .value = .{ .string = "/" } },
                        } },
                        .{ .map = &[_]MapEntry{
                            .{ .key = "name", .value = .{ .string = "Posts" } },
                            .{ .key = "url", .value = .{ .string = "/posts/" } },
                        } },
                    },
                } },
            },
        } },
    };

    const results = try parse(&arena, &config, &walkDirResult);
    try debug.printJson(&arena, results);
}
