const std = @import("std");

const config = @import("../logic/config.zig");
const logic = @import("../logic/site.zig");
const models = @import("../models.zig");
const ContentEntry = models.ContentEntry;
const Context = models.Context;
const File = models.File;
const MapEntries = models.MapEntries;
const Tag = models.Tag;
const Tags = models.Tags;
const Templates = models.Templates;
const Page = models.Page;
const PageKind = models.PageKind;
const ImageSpec = models.ImageSpec;
const Site = models.Site;
const frontmatter = @import("frontmatter.zig");
const markdown = @import("markdown.zig");
const string = @import("string.zig");
const yaml_lexer = @import("yaml_lexer.zig");

fn parseSlug(arena: *std.heap.ArenaAllocator, file: File, page: ContentEntry) ![]const u8 {
    if (std.mem.eql(u8, file.file_name, "_index.md")) return "";
    if (page.frontmatter.slug) |slug| return slug;
    if (page.frontmatter.title) |title| return try string.parseSlug(arena, title);
    var file_name = std.mem.splitScalar(u8, file.file_name, '.');
    return file_name.first();
}

fn buildUrl(arena: *std.heap.ArenaAllocator, page_kind: PageKind, slug: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    switch (page_kind) {
        .post => return try std.Io.Dir.path.join(allocator, &.{ config.post_url_prefix, slug }),
        .page => return try std.Io.Dir.path.join(allocator, &.{ "/", slug }),
        .home => return "/",
        .post_list => return config.post_url_prefix,
        .tag_post_list => return try std.Io.Dir.path.join(allocator, &.{ config.tag_post_list_url_prefix, slug }),
    }
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

fn parseMenuEntryContext(allocator: std.mem.Allocator, name: []const u8, url: []const u8) !Context {
    var ctx: Context = .{};
    try ctx.map.put(allocator, "name", .{ .string = name });
    try ctx.map.put(allocator, "url", .{ .string = url });
    return ctx;
}

fn parseTagContext(arena: *std.heap.ArenaAllocator, tag: []const u8) !Context {
    const allocator = arena.allocator();
    var tag_context: Context = .{};
    const tag_slug = try string.parseSlug(arena, tag);
    try tag_context.map.put(allocator, "title", .{ .string = tag });
    try tag_context.map.put(allocator, "slug", .{ .string = tag_slug });
    try tag_context.map.put(allocator, "url", .{ .string = try buildUrl(arena, .tag_post_list, tag_slug) });
    return tag_context;
}

fn parseTagPage(arena: *std.heap.ArenaAllocator, tags: *Tags, tag_context: Context, index: usize) !void {
    const allocator = arena.allocator();
    const tag_slug = tag_context.map.get("slug").?.string;
    if (tags.map.getPtr(tag_slug)) |current_tag|
        try current_tag.indexes.append(allocator, index)
    else {
        var indexes: std.ArrayList(usize) = .empty;
        try indexes.append(allocator, index);
        const tag_page = Page{ .kind = .tag_post_list, .context = tag_context };
        try tags.map.put(allocator, tag_slug, Tag{ .page = tag_page, .indexes = indexes });
    }
}

/// Parses loaded files into a `Site` (config, templates, pages, posts, menu).
pub fn parse(
    arena: *std.heap.ArenaAllocator,
    files: []const File,
    keep_drafts: bool,
) !Site {
    const allocator = arena.allocator();
    var site_config: MapEntries = .{};
    var templates: Templates = .{};
    var site_title: []const u8 = "";
    var site_base_url: []const u8 = "";
    var pages: std.ArrayList(Page) = .empty;
    var posts: std.ArrayList(Page) = .empty;
    var tags: Tags = .{};
    var page_main_menu: std.ArrayList(Context) = .empty;

    for (files) |file| {
        if (logic.parsePageKind(file)) |page_kind| {
            const page = try frontmatter.parse(arena, file.contents);
            const html = try markdown.toHtml(arena, page.source);
            var context: Context = .{};
            try context.map.put(allocator, "body", .{ .string = html });
            if (page.frontmatter.draft) {
                if (!keep_drafts) continue;
                try context.map.put(allocator, "draft", .{ .bool = true });
            }
            if (page.frontmatter.title) |title| try context.map.put(allocator, "title", .{ .string = title });
            const slug = try parseSlug(arena, file, page);
            try context.map.put(allocator, "slug", .{ .string = slug });
            try context.map.put(allocator, "url", .{ .string = try buildUrl(arena, page_kind, slug) });
            if (page.frontmatter.menus.len > 0) {
                for (page.frontmatter.menus) |menu| {
                    if (std.mem.eql(u8, menu, "main")) {
                        const name = context.map.get("title") orelse context.map.get("slug").?;
                        const url = context.map.get("url").?;
                        try page_main_menu.append(allocator, try parseMenuEntryContext(allocator, name.string, url.string));
                    }
                }
            }
            switch (page_kind) {
                .post => {
                    if (page.frontmatter.author) |author| try context.map.put(allocator, "author", .{ .string = author });
                    if (page.frontmatter.date) |date| try context.map.put(allocator, "date", .{ .string = date });
                    if (page.frontmatter.description) |description| try context.map.put(allocator, "description", .{ .string = description });
                    if (page.frontmatter.cover) |cover| try context.map.put(allocator, "cover", .{ .string = cover });
                    if (page.frontmatter.tags.len > 0) {
                        var tag_outer_context = try std.ArrayList(Context).initCapacity(allocator, page.frontmatter.tags.len);
                        for (page.frontmatter.tags) |tag| {
                            const tag_context = try parseTagContext(arena, tag);
                            try parseTagPage(arena, &tags, tag_context, posts.items.len);
                            tag_outer_context.appendAssumeCapacity(tag_context);
                        }
                        try context.map.put(allocator, "tags", .{ .list = tag_outer_context.items });
                    }
                    if (page.frontmatter.images.len > 0)
                        try context.map.put(allocator, "images", .{ .list = try parseImageList(allocator, page.frontmatter.images) });
                    try posts.append(allocator, Page{ .kind = page_kind, .context = context });
                },
                else => try pages.append(allocator, Page{ .kind = page_kind, .context = context }),
            }
        }
        if (logic.isTemplate(file))
            if (std.mem.cutPrefix(u8, file.rel_path, config.templates_prefix)) |template_key|
                try templates.map.put(allocator, template_key, file.contents);
        if (logic.isConfig(file))
            site_config = try yaml_lexer.parse(arena, file.contents);
    }

    var main_menu: std.ArrayList(Context) = .empty;
    if (site_config.map.count() > 0) {
        site_title = site_config.map.get("title").?.string;
        site_base_url = site_config.map.get("base_url").?.string;
        for (site_config.map.get("menu").?.map.map.get("main").?.list) |entry| {
            try main_menu.append(allocator, try parseMenuEntryContext(
                allocator,
                entry.map.map.get("name").?.string,
                entry.map.map.get("url").?.string,
            ));
        }
    }
    try main_menu.appendSlice(allocator, page_main_menu.items);

    return Site{
        .title = site_title,
        .base_url = site_base_url,
        .menu_main = main_menu.items,
        .templates = templates,
        .pages = pages.items,
        .posts = posts.items,
        .tags = tags,
    };
}

fn testFile(rel_path: []const u8, contents: []const u8) File {
    var split = std.mem.splitBackwardsScalar(u8, rel_path, '/');
    return .{
        .rel_path = rel_path,
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = split.first(),
        .contents = contents,
    };
}

test "parse with only config populates site metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const files = [_]File{
        testFile("site.yaml",
            \\title: My Site
            \\base_url: https://example.com
            \\menu:
            \\  main:
            \\    - { name: About, url: /about }
        ),
    };

    const site = try parse(&arena, &files, false);
    try std.testing.expectEqualStrings("My Site", site.title);
    try std.testing.expectEqualStrings("https://example.com", site.base_url);
    try std.testing.expectEqual(@as(usize, 1), site.menu_main.len);
    try std.testing.expectEqualStrings("About", site.menu_main[0].map.get("name").?.string);
    try std.testing.expectEqualStrings("/about", site.menu_main[0].map.get("url").?.string);
    try std.testing.expectEqual(@as(usize, 0), site.pages.len);
    try std.testing.expectEqual(@as(usize, 0), site.posts.len);
    try std.testing.expectEqual(@as(usize, 0), site.templates.map.count());
}

test "parse empty files returns defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const files = [_]File{};
    const site = try parse(&arena, &files, false);
    try std.testing.expectEqualStrings("", site.title);
    try std.testing.expectEqualStrings("", site.base_url);
    try std.testing.expectEqual(@as(usize, 0), site.menu_main.len);
    try std.testing.expectEqual(@as(usize, 0), site.pages.len);
    try std.testing.expectEqual(@as(usize, 0), site.posts.len);
}

test "parse post populates posts list with frontmatter in context" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const files = [_]File{
        testFile("content/posts/hello.md",
            \\---
            \\title: Hello World
            \\date: 2026-06-01
            \\tags: [zig, ssg]
            \\draft: true
            \\---
            \\## Intro
            \\Body text.
        ),
    };

    const site = try parse(&arena, &files, true);
    try std.testing.expectEqual(@as(usize, 1), site.posts.len);
    try std.testing.expectEqual(@as(usize, 0), site.pages.len);

    const post = site.posts[0];
    try std.testing.expectEqual(PageKind.post, post.kind);
    try std.testing.expectEqualStrings("Hello World", post.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("2026-06-01", post.context.map.get("date").?.string);
    try std.testing.expectEqualStrings("zig", post.context.map.get("tags").?.list[0].map.get("title").?.string);
    try std.testing.expectEqualStrings("ssg", post.context.map.get("tags").?.list[1].map.get("title").?.string);
    try std.testing.expectEqual(true, post.context.map.get("draft").?.bool);
    try std.testing.expect(std.mem.containsAtLeast(u8, post.context.map.get("body").?.string, 1, "<h2>"));
    try std.testing.expectEqualStrings("hello-world", post.context.map.get("slug").?.string);
    try std.testing.expectEqualStrings("/posts/hello-world", post.context.map.get("url").?.string);
}

test "parse page (non-post) goes to pages list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const files = [_]File{
        testFile("content/about.md",
            \\---
            \\title: About Us
            \\menus: [main]
            \\---
            \\# About
            \\We make things.
        ),
    };

    const site = try parse(&arena, &files, false);
    try std.testing.expectEqual(@as(usize, 0), site.posts.len);
    try std.testing.expectEqual(@as(usize, 1), site.pages.len);
    try std.testing.expectEqual(PageKind.page, site.pages[0].kind);
    try std.testing.expectEqualStrings("About Us", site.pages[0].context.map.get("title").?.string);
    try std.testing.expect(std.mem.containsAtLeast(u8, site.pages[0].context.map.get("body").?.string, 1, "<h1>"));
    try std.testing.expectEqualStrings("/about-us", site.pages[0].context.map.get("url").?.string);

    try std.testing.expectEqual(@as(usize, 1), site.menu_main.len);
}

test "parse loads templates into templates map" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const files = [_]File{
        testFile("templates/base.html", "<html>{{ body }}</html>"),
        testFile("templates/partials/nav.html", "<nav>{{ items }}</nav>"),
    };

    const site = try parse(&arena, &files, false);
    try std.testing.expectEqual(@as(usize, 2), site.templates.map.count());
    try std.testing.expectEqualStrings("<html>{{ body }}</html>", site.templates.map.get("base.html").?);
    try std.testing.expectEqualStrings("<nav>{{ items }}</nav>", site.templates.map.get("partials/nav.html").?);
}

test "parse post with images builds image context list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const files = [_]File{
        testFile("content/posts/gallery.md",
            \\---
            \\title: Gallery
            \\images:
            \\  - { file: a.jpg, caption: "First" }
            \\  - { file: b.jpg, caption: "Second" }
            \\---
            \\Look at these.
        ),
    };

    const site = try parse(&arena, &files, false);
    const images = site.posts[0].context.map.get("images").?.list;
    try std.testing.expectEqual(@as(usize, 2), images.len);
    try std.testing.expectEqualStrings("a.jpg", images[0].map.get("file").?.string);
    try std.testing.expectEqualStrings("First", images[0].map.get("caption").?.string);
    try std.testing.expectEqualStrings("b.jpg", images[1].map.get("file").?.string);
    try std.testing.expectEqualStrings("Second", images[1].map.get("caption").?.string);
}

test "smoke: full site with config, pages, posts, templates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const files = [_]File{
        testFile("site.yaml",
            \\title: Example Blog
            \\base_url: http://localhost:8000
            \\menu:
            \\  main:
            \\    - { name: Home, url: / }
            \\    - { name: Posts, url: /posts/ }
        ),
        testFile("content/_index.md",
            \\---
            \\title: Welcome
            \\---
            \\# Hello
            \\This is a static site built with **stabilis**.
        ),
        testFile("content/posts/_index.md",
            \\---
            \\title: Posts
            \\description: All blog posts, newest first.
            \\---
            \\Things I've written.
        ),
        testFile("content/posts/hello-world.md",
            \\---
            \\title: Hello, World
            \\date: 2026-06-01T10:00:00Z
            \\tags: [zig, blogging]
            \\description: First post on the new SSG.
            \\---
            \\## Getting started
            \\This is the **first post**.
        ),
        testFile("content/posts/draft-hello.md",
            \\---
            \\title: Draft Hello World
            \\date: 2026-06-01
            \\tags: [zig, ssg]
            \\draft: true
            \\---
            \\## Intro
            \\Body text.
        ),
        testFile("content/about.md",
            \\---
            \\title: About Us
            \\menus: [main]
            \\---
            \\# About
            \\We make things.
        ),
        testFile("templates/partials/header.html", "<!DOCTYPE html>\n<html>\n<head><title>{{ title }}</title></head>\n<body>\n<nav>{{# menu_main }}<a href=\"{{ url }}\">{{ name }}</a>{{/ menu_main }}</nav>\n"),
        testFile("templates/home.html", "{{> partials/header.html }}\n<h1>{{ title }}</h1>\n{{{ body }}}\n<h2>Recent posts</h2>\n<ul>\n{{# posts }}<li><a href=\"{{ url }}\">{{ title }}</a></li>\n{{/ posts }}</ul>\n</body></html>\n"),
        testFile("templates/post.html", "{{> partials/header.html }}\n<h1>{{ title }}</h1>\n<span>{{ date }}</span>\n{{{ body }}}\n</body></html>\n"),
        testFile("templates/page.html", "{{> partials/header.html }}\n<h1>{{ title }}</h1>\n<div class=\"content\">\n{{{ body }}}\n</div>\n</body></html>\n"),
        testFile("templates/post-list.html", "{{> partials/header.html }}\n<h1>{{ title }}</h1>\n{{{ body }}}\n<ul>{{# posts }}<li><a href=\"{{ url }}\">{{ title }}</a></li>{{/ posts }}</ul>\n</body></html>\n"),
    };

    const site = try parse(&arena, &files, false);

    // site metadata
    try std.testing.expectEqualStrings("Example Blog", site.title);
    try std.testing.expectEqualStrings("http://localhost:8000", site.base_url);

    // menu
    try std.testing.expectEqual(@as(usize, 3), site.menu_main.len);
    try std.testing.expectEqualStrings("Home", site.menu_main[0].map.get("name").?.string);
    try std.testing.expectEqualStrings("/", site.menu_main[0].map.get("url").?.string);
    try std.testing.expectEqualStrings("Posts", site.menu_main[1].map.get("name").?.string);
    try std.testing.expectEqualStrings("/posts/", site.menu_main[1].map.get("url").?.string);
    try std.testing.expectEqualStrings("About Us", site.menu_main[2].map.get("name").?.string);
    try std.testing.expectEqualStrings("/about-us", site.menu_main[2].map.get("url").?.string);

    // pages: home + post_list + about (both under content/ but not content/posts/)
    try std.testing.expectEqual(@as(usize, 3), site.pages.len);

    const home_page = site.pages[0];
    try std.testing.expectEqual(PageKind.home, home_page.kind);
    try std.testing.expectEqualStrings("Welcome", home_page.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("/", home_page.context.map.get("url").?.string);
    try std.testing.expect(std.mem.containsAtLeast(u8, home_page.context.map.get("body").?.string, 1, "<h1>"));

    const about_page = site.pages[2];
    try std.testing.expectEqual(PageKind.page, about_page.kind);
    try std.testing.expectEqualStrings("About Us", about_page.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("/about-us", about_page.context.map.get("url").?.string);
    try std.testing.expect(std.mem.containsAtLeast(u8, about_page.context.map.get("body").?.string, 1, "<h1>"));

    // posts
    try std.testing.expectEqual(@as(usize, 1), site.posts.len);

    const post = site.posts[0];
    try std.testing.expectEqual(PageKind.post, post.kind);
    try std.testing.expectEqualStrings("Hello, World", post.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("2026-06-01T10:00:00Z", post.context.map.get("date").?.string);
    try std.testing.expectEqualStrings("First post on the new SSG.", post.context.map.get("description").?.string);
    try std.testing.expectEqualStrings("/posts/hello-world", post.context.map.get("url").?.string);
    try std.testing.expect(std.mem.containsAtLeast(u8, post.context.map.get("body").?.string, 1, "<h2>"));

    const tags = post.context.map.get("tags").?.list;
    try std.testing.expectEqual(@as(usize, 2), tags.len);
    try std.testing.expectEqualStrings("zig", tags[0].map.get("title").?.string);
    try std.testing.expectEqualStrings("blogging", tags[1].map.get("title").?.string);

    // site tags
    try std.testing.expectEqual(@as(usize, 2), site.tags.map.count());
    const zig_tag = site.tags.map.get("zig").?;
    try std.testing.expectEqualStrings("zig", zig_tag.page.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("/posts/tags/zig", zig_tag.page.context.map.get("url").?.string);
    try std.testing.expectEqual(PageKind.tag_post_list, zig_tag.page.kind);
    try std.testing.expectEqual(@as(usize, 1), zig_tag.indexes.items.len);
    try std.testing.expectEqual(@as(usize, 0), zig_tag.indexes.items[0]);

    // templates
    try std.testing.expect(site.templates.map.get("partials/header.html") != null);
    try std.testing.expect(site.templates.map.get("home.html") != null);
    try std.testing.expect(site.templates.map.get("post.html") != null);
    try std.testing.expect(site.templates.map.get("post-list.html") != null);
}
