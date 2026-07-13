const std = @import("std");

const time = @import("../adapters/time.zig");
const config_adapter = @import("../adapters/config.zig");
const config = @import("../logic/config.zig");
const logic = @import("../logic/site.zig");
const models = @import("../models.zig");
const Config = models.Config;
const ContentEntry = models.ContentEntry;
const Context = models.Context;
const DateTime = models.DateTime;
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

fn buildUrl(arena: *std.heap.ArenaAllocator, cfg: *const Config, page_kind: PageKind, slug: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    return switch (page_kind) {
        .post => try std.Io.Dir.path.join(allocator, &.{ cfg.post_url_prefix[1..], slug }),
        .page => slug,
        .home => "",
        .post_list => cfg.post_url_prefix[1..],
        .tag_post_list => try std.Io.Dir.path.join(allocator, &.{ cfg.tag_post_list_url_prefix[1..], slug }),
        .atom_feed => "feed.atom",
    };
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

/// Records post `index` under `tag`, creating the tag's page on first sight.
/// Returns the tag's context so the post's tag-link list can reuse it.
fn upsertTag(arena: *std.heap.ArenaAllocator, cfg: *const Config, tags: *Tags, tag: []const u8, index: usize) !Context {
    const allocator = arena.allocator();
    const tag_slug = try string.parseSlug(arena, tag);
    const tag_entry = try tags.map.getOrPut(allocator, tag_slug);
    if (!tag_entry.found_existing) {
        var tag_context: Context = .{};
        try tag_context.map.put(allocator, "title", .{ .string = tag });
        try tag_context.map.put(allocator, "slug", .{ .string = tag_slug });
        try tag_context.map.put(allocator, "url", .{ .string = try buildUrl(arena, cfg, .tag_post_list, tag_slug) });
        tag_entry.value_ptr.* = .{ .page = .{ .kind = .tag_post_list, .context = tag_context }, .indexes = .empty };
    }
    try tag_entry.value_ptr.indexes.append(allocator, index);
    return tag_entry.value_ptr.page.context;
}

/// Parses loaded files into a `Site` (config, templates, pages, posts, menu).
pub fn parse(
    arena: *std.heap.ArenaAllocator,
    cfg: *const Config,
    files: []const File,
    keep_drafts: bool,
    now: DateTime,
    version: []const u8,
) !Site {
    const allocator = arena.allocator();
    const base_path = try config_adapter.basePath(allocator, cfg.base_uri);
    const domain = if (cfg.base_uri.host) |host| switch (host) {
        .raw, .percent_encoded => |s| s,
    } else "localhost";

    var templates: Templates = .{};
    var pages: std.ArrayList(Page) = .empty;
    var posts: std.ArrayList(Page) = .empty;
    var tags: Tags = .{};
    var page_main_menu: std.ArrayList(Context) = .empty;

    for (files) |file| {
        if (logic.parsePageKind(cfg, file)) |page_kind| {
            const page = try frontmatter.parse(arena, file.contents);
            const html = try markdown.toHtml(arena, base_path, page.source);
            var context: Context = .{};
            try context.map.put(allocator, "page_kind", .{ .string = std.enums.tagName(PageKind, page_kind) orelse "page" });
            try context.map.put(allocator, "body", .{ .string = html });
            if (page.frontmatter.draft) {
                if (!keep_drafts) continue;
                try context.map.put(allocator, "draft", .{ .bool = true });
            }
            if (page.frontmatter.title) |title| try context.map.put(allocator, "title", .{ .string = title });
            const slug = try parseSlug(arena, file, page);
            try context.map.put(allocator, "slug", .{ .string = slug });
            try context.map.put(allocator, "url", .{ .string = try buildUrl(arena, cfg, page_kind, slug) });
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
                    if (page.frontmatter.date) |date| {
                        try context.map.put(allocator, "date", .{ .string = try time.toIsoString(arena, date) });
                        try context.map.put(allocator, "date_human", .{ .string = try time.toHumanString(arena, date) });
                    }
                    if (page.frontmatter.description) |description| try context.map.put(allocator, "description", .{ .string = description });
                    if (page.frontmatter.cover) |cover| try context.map.put(allocator, "cover", .{ .string = cover });
                    if (page.frontmatter.tags.len > 0) {
                        var tag_outer_context = try std.ArrayList(Context).initCapacity(allocator, page.frontmatter.tags.len);
                        for (page.frontmatter.tags) |tag|
                            tag_outer_context.appendAssumeCapacity(try upsertTag(arena, cfg, &tags, tag, posts.items.len));
                        try context.map.put(allocator, "tags", .{ .list = tag_outer_context.items });
                    }
                    if (page.frontmatter.images.len > 0)
                        try context.map.put(allocator, "images", .{ .list = try parseImageList(allocator, page.frontmatter.images) });
                    try posts.append(allocator, Page{ .kind = page_kind, .context = context });
                },
                .post_list => {
                    try pages.append(allocator, Page{ .kind = page_kind, .context = context });
                    // synthetically create a page to generate the atom feed
                    var feed_context: Context = .{ .map = try context.map.clone(allocator) };
                    try feed_context.map.put(allocator, "page_kind", .{ .string = "atom_feed" });
                    try feed_context.map.put(allocator, "url", .{ .string = try buildUrl(arena, cfg, .atom_feed, "") });
                    try pages.append(allocator, Page{ .kind = .atom_feed, .context = feed_context });
                },
                else => try pages.append(allocator, Page{ .kind = page_kind, .context = context }),
            }
        }
        if (logic.isTemplate(cfg, file))
            if (std.mem.cutPrefix(u8, file.rel_path, cfg.templates_prefix)) |template_key|
                try templates.map.put(allocator, template_key, file.contents);
    }

    const main_menu = try std.mem.concat(allocator, Context, &.{
        cfg.menu_main,
        page_main_menu.items,
    });

    return Site{
        .title = cfg.title,
        .base_url = cfg.base_url,
        .base_uri = cfg.base_uri,
        .domain = domain,
        .author = cfg.author,
        .description = cfg.description,
        .version = version,
        .now = now,
        .menu_main = main_menu,
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

    var cfg = config.default;
    cfg.title = "My Site";
    cfg.base_url = "https://example.com";
    var about_ctx: Context = .{};
    try about_ctx.map.put(arena.allocator(), "name", .{ .string = "About" });
    try about_ctx.map.put(arena.allocator(), "url", .{ .string = "/about" });
    cfg.menu_main = &.{about_ctx};

    const site = try parse(&arena, &cfg, &.{}, false, .{
        .sec = 2,
        .min = 30,
        .hour = 18,
        .day = 13,
        .month = 12,
        .year = 2003,
    }, "test");
    try std.testing.expectEqualStrings("My Site", site.title);
    try std.testing.expectEqualStrings("https://example.com", site.base_url);
    try std.testing.expectEqual(@as(i16, 2003), site.now.year);
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

    const cfg = config.default;
    const files = [_]File{};
    const site = try parse(&arena, &cfg, &files, false, .{
        .sec = 2,
        .min = 30,
        .hour = 18,
        .day = 13,
        .month = 12,
        .year = 2003,
    }, "test");

    try std.testing.expectEqualStrings("", site.title);
    try std.testing.expectEqualStrings("", site.base_url);
    try std.testing.expectEqual(@as(i16, 2003), site.now.year);
    try std.testing.expectEqual(@as(usize, 0), site.menu_main.len);
    try std.testing.expectEqual(@as(usize, 0), site.pages.len);
    try std.testing.expectEqual(@as(usize, 0), site.posts.len);
}

test "parse post populates posts list with frontmatter in context" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cfg = config.default;
    const files = [_]File{
        testFile("content/posts/hello.md",
            \\---
            \\title: Hello World
            \\date: 2026-06-01T10:00:00Z
            \\tags: [zig, ssg]
            \\draft: true
            \\---
            \\## Intro
            \\Body text.
        ),
    };

    const site = try parse(&arena, &cfg, &files, true, .{
        .sec = 2,
        .min = 30,
        .hour = 18,
        .day = 13,
        .month = 12,
        .year = 2003,
    }, "test");
    try std.testing.expectEqual(@as(usize, 1), site.posts.len);
    try std.testing.expectEqual(@as(usize, 0), site.pages.len);

    const post = site.posts[0];
    try std.testing.expectEqual(PageKind.post, post.kind);
    try std.testing.expectEqualStrings("post", post.context.map.get("page_kind").?.string);
    try std.testing.expectEqualStrings("Hello World", post.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("2026-06-01T10:00:00Z", post.context.map.get("date").?.string);
    try std.testing.expectEqualStrings("zig", post.context.map.get("tags").?.list[0].map.get("title").?.string);
    try std.testing.expectEqualStrings("ssg", post.context.map.get("tags").?.list[1].map.get("title").?.string);
    try std.testing.expectEqual(true, post.context.map.get("draft").?.bool);
    try std.testing.expect(std.mem.containsAtLeast(u8, post.context.map.get("body").?.string, 1, "<h2>"));
    try std.testing.expectEqualStrings("hello-world", post.context.map.get("slug").?.string);
    try std.testing.expectEqualStrings("posts/hello-world", post.context.map.get("url").?.string);
}

test "parse page (non-post) goes to pages list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cfg = config.default;
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

    const site = try parse(&arena, &cfg, &files, false, .{
        .sec = 2,
        .min = 30,
        .hour = 18,
        .day = 13,
        .month = 12,
        .year = 2003,
    }, "test");
    try std.testing.expectEqual(@as(usize, 0), site.posts.len);
    try std.testing.expectEqual(@as(usize, 1), site.pages.len);
    try std.testing.expectEqual(PageKind.page, site.pages[0].kind);
    try std.testing.expectEqualStrings("page", site.pages[0].context.map.get("page_kind").?.string);
    try std.testing.expectEqualStrings("About Us", site.pages[0].context.map.get("title").?.string);
    try std.testing.expect(std.mem.containsAtLeast(u8, site.pages[0].context.map.get("body").?.string, 1, "<h1>"));
    try std.testing.expectEqualStrings("about-us", site.pages[0].context.map.get("url").?.string);

    try std.testing.expectEqual(@as(usize, 1), site.menu_main.len);
}

test "parse loads templates into templates map" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cfg = config.default;
    const files = [_]File{
        testFile("templates/base.html", "<html>{{ body }}</html>"),
        testFile("templates/partials/nav.html", "<nav>{{ items }}</nav>"),
    };

    const site = try parse(&arena, &cfg, &files, false, .{
        .sec = 2,
        .min = 30,
        .hour = 18,
        .day = 13,
        .month = 12,
        .year = 2003,
    }, "test");
    try std.testing.expectEqual(@as(usize, 2), site.templates.map.count());
    try std.testing.expectEqualStrings("<html>{{ body }}</html>", site.templates.map.get("base.html").?);
    try std.testing.expectEqualStrings("<nav>{{ items }}</nav>", site.templates.map.get("partials/nav.html").?);
}

test "parse post with images builds image context list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cfg = config.default;
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

    const site = try parse(&arena, &cfg, &files, false, .{
        .sec = 2,
        .min = 30,
        .hour = 18,
        .day = 13,
        .month = 12,
        .year = 2003,
    }, "test");
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

    var cfg = config.default;
    cfg.title = "Example Blog";
    cfg.base_url = "http://localhost:8000";
    cfg.author = "John Doe";
    var home_ctx: Context = .{};
    try home_ctx.map.put(arena.allocator(), "name", .{ .string = "Home" });
    try home_ctx.map.put(arena.allocator(), "url", .{ .string = "" });
    var posts_ctx: Context = .{};
    try posts_ctx.map.put(arena.allocator(), "name", .{ .string = "Posts" });
    try posts_ctx.map.put(arena.allocator(), "url", .{ .string = "posts/" });
    cfg.menu_main = &.{ home_ctx, posts_ctx };

    const files = [_]File{
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
        testFile("templates/feed.atom", "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\">\n  <title>{{ site_title }}</title>\n  <link href=\"{{ base_url }}\"/>\n  <link rel=\"self\" href=\"{{ base_url }}/feed.atom\"/>\n  <updated>{{ updated }}</updated>\n  <author><name>{{ site_author }}</name></author>\n  <generator uri=\"https://github.com/rafaeldelboni/stabilis\" version=\"{{ site_version }}\">stabilis</generator>\n  <rights>Copyright {{ year }} {{ site_author }}</rights>\n  <subtitle>{{ site_description }}</subtitle>\n  <id>urn:{{ domain }}</id>\n  {{# posts sort=date desc top=10 }}\n  <entry>\n    <title>{{ title }}</title>\n    <link href=\"{{ base_url }}/{{ url }}\"/>\n    <id>urn:{{ domain }}:{{ page_kind }}:{{ slug }}</id>\n    <published>{{ date }}</published>\n    <updated>{{ date }}</updated>\n    {{# tags }}<category term=\"{{ slug }}\" label=\"{{ title }}\"/>{{/ tags }}\n    <summary>{{ description }}</summary>\n    <content type=\"html\"><![CDATA[{{{ body }}}]]></content>\n  </entry>\n  {{/ posts }}\n</feed>\n"),
    };

    const site = try parse(&arena, &cfg, &files, false, .{
        .sec = 2,
        .min = 30,
        .hour = 18,
        .day = 13,
        .month = 12,
        .year = 2003,
    }, "test");

    // site metadata
    try std.testing.expectEqualStrings("Example Blog", site.title);
    try std.testing.expectEqualStrings("http://localhost:8000", site.base_url);
    try std.testing.expectEqualStrings("John Doe", site.author);
    try std.testing.expectEqualStrings("test", site.version);
    try std.testing.expectEqual(@as(i16, 2003), site.now.year);

    // menu
    try std.testing.expectEqual(@as(usize, 3), site.menu_main.len);
    try std.testing.expectEqualStrings("Home", site.menu_main[0].map.get("name").?.string);
    try std.testing.expectEqualStrings("", site.menu_main[0].map.get("url").?.string);
    try std.testing.expectEqualStrings("Posts", site.menu_main[1].map.get("name").?.string);
    try std.testing.expectEqualStrings("posts/", site.menu_main[1].map.get("url").?.string);
    try std.testing.expectEqualStrings("About Us", site.menu_main[2].map.get("name").?.string);
    try std.testing.expectEqualStrings("about-us", site.menu_main[2].map.get("url").?.string);

    // pages: home + post_list + atom_feed + about
    try std.testing.expectEqual(@as(usize, 4), site.pages.len);

    const home_page = site.pages[0];
    try std.testing.expectEqual(PageKind.home, home_page.kind);
    try std.testing.expectEqualStrings("home", home_page.context.map.get("page_kind").?.string);
    try std.testing.expectEqualStrings("Welcome", home_page.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("", home_page.context.map.get("url").?.string);
    try std.testing.expect(std.mem.containsAtLeast(u8, home_page.context.map.get("body").?.string, 1, "<h1>"));

    const post_list_page = site.pages[1];
    try std.testing.expectEqual(PageKind.post_list, post_list_page.kind);
    try std.testing.expectEqualStrings("post_list", post_list_page.context.map.get("page_kind").?.string);
    try std.testing.expectEqualStrings("Posts", post_list_page.context.map.get("title").?.string);

    const feed_page = site.pages[2];
    try std.testing.expectEqual(PageKind.atom_feed, feed_page.kind);
    try std.testing.expectEqualStrings("atom_feed", feed_page.context.map.get("page_kind").?.string);
    try std.testing.expectEqualStrings("Posts", feed_page.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("feed.atom", feed_page.context.map.get("url").?.string);

    const about_page = site.pages[3];
    try std.testing.expectEqual(PageKind.page, about_page.kind);
    try std.testing.expectEqualStrings("page", about_page.context.map.get("page_kind").?.string);
    try std.testing.expectEqualStrings("About Us", about_page.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("about-us", about_page.context.map.get("url").?.string);
    try std.testing.expect(std.mem.containsAtLeast(u8, about_page.context.map.get("body").?.string, 1, "<h1>"));

    // posts
    try std.testing.expectEqual(@as(usize, 1), site.posts.len);

    const post = site.posts[0];
    try std.testing.expectEqual(PageKind.post, post.kind);
    try std.testing.expectEqualStrings("post", post.context.map.get("page_kind").?.string);
    try std.testing.expectEqualStrings("Hello, World", post.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("2026-06-01T10:00:00Z", post.context.map.get("date").?.string);
    try std.testing.expectEqualStrings("First post on the new SSG.", post.context.map.get("description").?.string);
    try std.testing.expectEqualStrings("posts/hello-world", post.context.map.get("url").?.string);
    try std.testing.expect(std.mem.containsAtLeast(u8, post.context.map.get("body").?.string, 1, "<h2>"));

    const tags = post.context.map.get("tags").?.list;
    try std.testing.expectEqual(@as(usize, 2), tags.len);
    try std.testing.expectEqualStrings("zig", tags[0].map.get("title").?.string);
    try std.testing.expectEqualStrings("blogging", tags[1].map.get("title").?.string);

    // site tags
    try std.testing.expectEqual(@as(usize, 2), site.tags.map.count());
    const zig_tag = site.tags.map.get("zig").?;
    try std.testing.expectEqualStrings("zig", zig_tag.page.context.map.get("title").?.string);
    try std.testing.expectEqualStrings("posts/tags/zig", zig_tag.page.context.map.get("url").?.string);
    try std.testing.expectEqual(PageKind.tag_post_list, zig_tag.page.kind);
    try std.testing.expectEqual(@as(usize, 1), zig_tag.indexes.items.len);
    try std.testing.expectEqual(@as(usize, 0), zig_tag.indexes.items[0]);

    // templates
    try std.testing.expect(site.templates.map.get("partials/header.html") != null);
    try std.testing.expect(site.templates.map.get("home.html") != null);
    try std.testing.expect(site.templates.map.get("post.html") != null);
    try std.testing.expect(site.templates.map.get("post-list.html") != null);
    try std.testing.expect(site.templates.map.get("feed.atom") != null);
}
