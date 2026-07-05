const std = @import("std");

const config = @import("config.zig");
const models = @import("../models.zig");
const Config = models.Config;
const File = models.File;
const PageKind = models.PageKind;

/// Returns true if `file` is the site configuration file ("site.yaml").
pub fn isConfig(file: File) bool {
    return std.mem.eql(u8, file.rel_path, config.config_file);
}

/// Returns true if `file` is a template (under "templates/").
pub fn isTemplate(cfg: *const Config, file: File) bool {
    return std.mem.startsWith(u8, file.rel_path, cfg.templates_prefix);
}

/// Returns true if `file` is the post list index ("content/posts/_index.md").
pub fn isPostList(cfg: *const Config, file: File) bool {
    return std.mem.eql(u8, file.rel_path, cfg.post_list_path);
}

/// Returns true if `file` is a blog post (under "content/posts/").
pub fn isPost(cfg: *const Config, file: File) bool {
    return std.mem.startsWith(u8, file.rel_path, cfg.posts_path_prefix);
}

/// Returns true if `file` is the home page ("content/_index.md").
pub fn isHomePage(cfg: *const Config, file: File) bool {
    return std.mem.eql(u8, file.rel_path, cfg.home_page_path);
}

/// Returns true if `file` is a content page (under "content/").
pub fn isPage(cfg: *const Config, file: File) bool {
    return std.mem.startsWith(u8, file.rel_path, cfg.pages_path_prefix);
}

/// Returns PageKind given `file`
pub fn parsePageKind(cfg: *const Config, file: File) ?PageKind {
    if (isPostList(cfg, file)) return PageKind.post_list;
    if (isPost(cfg, file)) return PageKind.post;
    if (isHomePage(cfg, file)) return PageKind.home;
    if (isPage(cfg, file)) return PageKind.page;
    return null;
}

test "parsePageKind: home, post, page, post_list" {
    try std.testing.expectEqual(PageKind.home, parsePageKind(&config.default, .{
        .rel_path = "content/_index.md",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }).?);
    try std.testing.expectEqual(PageKind.post, parsePageKind(&config.default, .{
        .rel_path = "content/posts/my-post.md",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }).?);
    try std.testing.expectEqual(PageKind.post_list, parsePageKind(&config.default, .{
        .rel_path = "content/posts/_index.md",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }).?);
    try std.testing.expectEqual(PageKind.page, parsePageKind(&config.default, .{
        .rel_path = "content/about.md",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }).?);
}

test "parsePageKind: non-content files return null" {
    try std.testing.expect(parsePageKind(&config.default, .{
        .rel_path = "site.yaml",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }) == null);
    try std.testing.expect(parsePageKind(&config.default, .{
        .rel_path = "templates/home.html",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }) == null);
    try std.testing.expect(parsePageKind(&config.default, .{
        .rel_path = "README.md",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }) == null);
}

test "isConfig" {
    try std.testing.expect(isConfig(.{ .rel_path = "site.yaml", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isConfig(.{ .rel_path = "other.yaml", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isConfig(.{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}

test "isTemplate" {
    try std.testing.expect(isTemplate(&config.default, .{ .rel_path = "templates/base.html", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(isTemplate(&config.default, .{ .rel_path = "templates/", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isTemplate(&config.default, .{ .rel_path = "content/templates/", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isTemplate(&config.default, .{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}

test "isPostList" {
    try std.testing.expect(isPostList(&config.default, .{ .rel_path = "content/posts/_index.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPostList(&config.default, .{ .rel_path = "content/posts/other.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPostList(&config.default, .{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}

test "isPost" {
    try std.testing.expect(isPost(&config.default, .{ .rel_path = "content/posts/my-post.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(isPost(&config.default, .{ .rel_path = "content/posts/", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPost(&config.default, .{ .rel_path = "content/_index.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPost(&config.default, .{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}

test "isHomePage" {
    try std.testing.expect(isHomePage(&config.default, .{ .rel_path = "content/_index.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isHomePage(&config.default, .{ .rel_path = "content/posts/_index.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isHomePage(&config.default, .{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}

test "isPage" {
    try std.testing.expect(isPage(&config.default, .{ .rel_path = "content/about.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(isPage(&config.default, .{ .rel_path = "content/posts/my-post.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPage(&config.default, .{ .rel_path = "templates/home.html", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPage(&config.default, .{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}
