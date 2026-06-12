const std = @import("std");

const debug = @import("../debug.zig");
const logic = @import("../logic/site.zig");
const models = @import("../models.zig");
const Context = models.Context;
const File = models.File;
const MenuItem = models.MenuItem;
const MapEntries = models.MapEntries;
const Templates = models.Templates;
const YamlNode = models.YamlNode;
const Page = models.Page;
const PageKind = models.PageKind;
const ImageSpec = models.ImageSpec;
const Site = models.Site;
const frontmatter = @import("frontmatter.zig");
const markdown = @import("markdown.zig");
const yaml_lexer = @import("yaml_lexer.zig");

fn parsePageKind(file: File) ?PageKind {
    if (logic.isPostList(file)) return PageKind.post_list;
    if (logic.isPost(file)) return PageKind.post;
    if (logic.isHomePage(file)) return PageKind.home;
    if (logic.isPage(file)) return PageKind.page;
    return null;
}

fn parsePage(file: File) !Page {
    _ = file;
    return Page{ .kind = PageKind.page, .context = &{} };
}

fn parseStringList(allocator: std.mem.Allocator, list: []const []const u8) ![]Context {
    var outer_context = try std.ArrayList(Context).initCapacity(allocator, list.len);
    for (list) |item| {
        var inner_context: Context = .{};
        try inner_context.map.put(allocator, ".", .{ .string = item });
        outer_context.appendAssumeCapacity(inner_context);
    }
    return outer_context.items;
}

fn parseImageList(allocator: std.mem.Allocator, images: []const ImageSpec) ![]Context {
    var outer_context = try std.ArrayList(Context).initCapacity(allocator, images.len);
    for (images) |image| {
        var inner_context: Context = .{};
        try inner_context.map.put(allocator, "file", .{ .string = image.file });
        if (image.caption) |caption| {
            try inner_context.map.put(allocator, "caption", .{ .string = caption });
        }
        outer_context.appendAssumeCapacity(inner_context);
    }
    return outer_context.items;
}

pub fn parse(
    arena: *std.heap.ArenaAllocator,
    files: []const File,
) !Site {
    const allocator = arena.allocator();
    var config: MapEntries = .{};
    var templates: Templates = .{};
    var site_title: []const u8 = "";
    var site_base_url: []const u8 = "";
    var pages: std.ArrayList(Page) = .empty;
    var posts: std.ArrayList(Page) = .empty;

    for (files) |file| {
        if (parsePageKind(file)) |page_kind| {
            const page = try frontmatter.parse(arena, file.contents);
            const html = try markdown.toHtml(arena, page.source);
            var context: Context = .{};
            try context.map.put(allocator, "body", .{ .string = html });
            if (page.frontmatter.title) |title| try context.map.put(allocator, "title", .{ .string = title });
            try switch (page_kind) {
                .post => {
                    if (page.frontmatter.author) |author| try context.map.put(allocator, "author", .{ .string = author });
                    if (page.frontmatter.date) |date| try context.map.put(allocator, "date", .{ .string = date });
                    if (page.frontmatter.slug) |slug| try context.map.put(allocator, "slug", .{ .string = slug });
                    if (page.frontmatter.description) |description| try context.map.put(allocator, "description", .{ .string = description });
                    if (page.frontmatter.draft) try context.map.put(allocator, "draft", .{ .bool = true });
                    if (page.frontmatter.cover) |cover| try context.map.put(allocator, "cover", .{ .string = cover });
                    if (page.frontmatter.tags.len > 0)
                        try context.map.put(allocator, "tags", .{ .list = try parseStringList(allocator, page.frontmatter.tags) });
                    if (page.frontmatter.menus.len > 0)
                        try context.map.put(allocator, "menus", .{ .list = try parseStringList(allocator, page.frontmatter.menus) });
                    if (page.frontmatter.images.len > 0)
                        try context.map.put(allocator, "images", .{ .list = try parseImageList(allocator, page.frontmatter.images) });
                    try posts.append(allocator, Page{ .kind = page_kind, .context = context });
                },
                else => pages.append(allocator, Page{ .kind = page_kind, .context = context }),
            };
        }
        if (logic.isTemplate(file))
            if (std.mem.cutPrefix(u8, file.rel_path, logic.templates_path_prefix)) |template_key|
                try templates.map.put(allocator, template_key, file.contents);
        if (logic.isConfig(file))
            config = try yaml_lexer.parse(arena, file.contents);
    }
    var main_menu: std.ArrayList(MenuItem) = .empty;
    if (config.map.count() > 0) {
        site_title = config.map.get("title").?.string;
        site_base_url = config.map.get("base_url").?.string;
        for (config.map.get("menu").?.map.map.get("main").?.list) |entry| {
            try main_menu.append(allocator, .{
                .name = entry.map.map.get("name").?.string,
                .url = entry.map.map.get("url").?.string,
            });
        }
    }
    return Site{
        .title = site_title,
        .base_url = site_base_url,
        .menu_main = main_menu.items,
        .templates = templates,
        .pages = pages.items,
        .posts = posts.items,
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

    const results = try parse(&arena, &walkDirResult);
    debug.printJson(results);
}
