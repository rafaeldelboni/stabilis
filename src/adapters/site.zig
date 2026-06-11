const std = @import("std");

const debug = @import("../debug.zig");
const models = @import("../models.zig");
const File = models.File;
const MenuItem = models.MenuItem;
const MapEntries = models.MapEntries;
const Templates = models.Templates;
const YamlNode = models.YamlNode;
const Page = models.Page;
const PageKind = models.PageKind;
const Site = models.Site;

fn parsePageKind(file: File) ?PageKind {
    if (std.mem.startsWith(u8, file.rel_path, "content/posts/_index.md")) {
        return PageKind.post_list;
    }
    if (std.mem.startsWith(u8, file.rel_path, "content/posts/")) {
        return PageKind.post;
    }
    if (std.mem.startsWith(u8, file.rel_path, "content/_index.md")) {
        return PageKind.home;
    }
    if (std.mem.startsWith(u8, file.rel_path, "content/")) {
        return PageKind.page;
    }
}

fn parsePage(file: File) !Page {
    _ = file;
    return Page{ .kind = PageKind.page, .context = &{} };
}

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
    for (config.map.get("menu").?.map.map.get("main").?.list) |entry| {
        try main_menu.append(allocator, .{
            .name = entry.map.map.get("name").?.string,
            .url = entry.map.map.get("url").?.string,
        });
    }
    return Site{
        .title = config.map.get("title").?.string,
        .base_url = config.map.get("base_url").?.string,
        .menu_main = main_menu.items,
        .templates = .{},
        .pages = &.{},
        .posts = &.{},
    };
}

test "smoke test" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const walkDirResult = [_]File{
        .{ .rel_path = "content/posts/_index.md", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/content/posts", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/content/posts/_index.md", .file_ext = ".md", .file_name = "_index.md", .contents = "---\ntitle: Posts\ndescription: All blog posts, newest first.\n---\n\nThings I've written.\n" },
        .{ .rel_path = "content/posts/hello-world.md", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/content/posts", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/content/posts/hello-world.md", .file_ext = ".md", .file_name = "hello-world.md", .contents = "---\ntitle: Hello, World\ndate: 2026-06-01T10:00:00Z\ntags: [zig, blogging]\ndescription: First post on the new SSG.\n---\n\n## Getting started\n\nThis is the **first post**. It has:\n\n- Frontmatter with tags\n- A date\n- Markdown body\n\n```zig\nconst std = @import(\"std\");\n\npub fn main() !void {\n    std.debug.print(\"Hello from Zig!\\n\", .{});\n}\n```\n" },
        .{ .rel_path = "content/_index.md", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/content", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/content/_index.md", .file_ext = ".md", .file_name = "_index.md", .contents = "---\ntitle: Welcome\n---\n\n# Hello\n\nThis is a static site built with **stabilis**.\n" },
        .{ .rel_path = "templates/partials/header.html", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/partials", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/partials/header.html", .file_ext = ".html", .file_name = "header.html", .contents = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <title>{{ title }}</title>\n</head>\n<body>\n  <nav>\n    {{# menu_main }}\n    <a href=\"{{ url }}\">{{ name }}</a>\n    {{/ menu_main }}\n  </nav>\n" },
        .{ .rel_path = "templates/page.html", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/page.html", .file_ext = ".html", .file_name = "page.html", .contents = "{{> partials/header.html }}\n\n  <h1>{{ title }}</h1>\n  <div class=\"content\">\n    {{{ body }}}\n  </div>\n\n</body>\n</html>\n" },
        .{ .rel_path = "templates/home.html", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/home.html", .file_ext = ".html", .file_name = "home.html", .contents = "{{> partials/header.html }}\n\n  <h1>{{ title }}</h1>\n  {{{ body }}}\n\n  <h2>Recent posts</h2>\n  <ul>\n    {{# posts }}\n    <li><a href=\"{{ url }}\">{{ title }}</a> \u{2014} {{ date }}</li>\n    {{/ posts }}\n  </ul>\n\n</body>\n</html>\n" },
        .{ .rel_path = "templates/post.html", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/post.html", .file_ext = ".html", .file_name = "post.html", .contents = "{{> partials/header.html }}\n\n  <article>\n    <h1>{{ title }}</h1>\n    <time>{{ date }}</time>\n    {{# tags }}\n    <span class=\"tag\">{{ . }}</span>\n    {{/ tags }}\n    <div class=\"content\">\n      {{{ body }}}\n    </div>\n  </article>\n\n</body>\n</html>\n" },
        .{ .rel_path = "templates/post-list.html", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/templates", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/templates/post-list.html", .file_ext = ".html", .file_name = "post-list.html", .contents = "{{> partials/header.html }}\n\n  <section>\n    <h1>{{ title }}</h1>\n    {{{ body }}}\n    <ul>\n      {{# posts }}\n      <li>\n        <a href=\"{{ url }}\">{{ title }}</a>\n        <time>{{ date }}</time>\n      </li>\n      {{/ posts }}\n    </ul>\n  </section>\n\n</body>\n</html>\n" },
        .{ .rel_path = "site.yaml", .dir_path = "/home/delboni/Workspaces/zig/stabilis/example/", .abs_path = "/home/delboni/Workspaces/zig/stabilis/example/site.yaml", .file_ext = ".yaml", .file_name = "site.yaml", .contents = "title: Example Blog\nbase_url: http://localhost:8000\nmenu:\n  main:\n    - { name: Home, url: / }\n    - { name: Posts, url: /posts/ }\n" },
    };

    var home_map: MapEntries = .{};
    try home_map.map.put(arena.allocator(), "name", .{ .string = "Home" });
    try home_map.map.put(arena.allocator(), "url", .{ .string = "/" });

    var posts_map: MapEntries = .{};
    try posts_map.map.put(arena.allocator(), "name", .{ .string = "Posts" });
    try posts_map.map.put(arena.allocator(), "url", .{ .string = "/posts/" });

    var main_map: MapEntries = .{};
    try main_map.map.put(arena.allocator(), "main", .{ .list = &[_]YamlNode{
        .{ .map = home_map },
        .{ .map = posts_map },
    } });

    var config: MapEntries = .{};
    try config.map.put(arena.allocator(), "title", .{ .string = "Example Blog" });
    try config.map.put(arena.allocator(), "base_url", .{ .string = "http://localhost:8000" });
    try config.map.put(arena.allocator(), "menu", .{ .map = main_map });

    const results = try parse(&arena, config, &walkDirResult);
    debug.printJson(results);
}
