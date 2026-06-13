const std = @import("std");

const models = @import("../models.zig");
const File = models.File;
const PageKind = models.PageKind;

pub const config_path = "site.yaml";
pub const post_list_path = "content/posts/_index.md";
pub const home_page_path = "content/_index.md";
pub const templates_path_prefix = "templates/";
pub const posts_path_prefix = "content/posts/";
pub const pages_path_prefix = "content/";

/// Returns true if `file` is the site configuration file ("site.yaml").
pub fn isConfig(file: File) bool {
    return std.mem.eql(u8, file.rel_path, config_path);
}

/// Returns true if `file` is a template (under "templates/").
pub fn isTemplate(file: File) bool {
    return std.mem.startsWith(u8, file.rel_path, templates_path_prefix);
}

/// Returns true if `file` is the post list index ("content/posts/_index.md").
pub fn isPostList(file: File) bool {
    return std.mem.eql(u8, file.rel_path, post_list_path);
}

/// Returns true if `file` is a blog post (under "content/posts/").
pub fn isPost(file: File) bool {
    return std.mem.startsWith(u8, file.rel_path, posts_path_prefix);
}

/// Returns true if `file` is the home page ("content/_index.md").
pub fn isHomePage(file: File) bool {
    return std.mem.eql(u8, file.rel_path, home_page_path);
}

/// Returns true if `file` is a content page (under "content/").
pub fn isPage(file: File) bool {
    return std.mem.startsWith(u8, file.rel_path, pages_path_prefix);
}

/// Returns PageKind given `file`
pub fn parsePageKind(file: File) ?PageKind {
    if (isPostList(file)) return PageKind.post_list;
    if (isPost(file)) return PageKind.post;
    if (isHomePage(file)) return PageKind.home;
    if (isPage(file)) return PageKind.page;
    return null;
}

test "parsePageKind: home, post, page, post_list" {
    try std.testing.expectEqual(PageKind.home, parsePageKind(.{
        .rel_path = "content/_index.md",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }).?);
    try std.testing.expectEqual(PageKind.post, parsePageKind(.{
        .rel_path = "content/posts/my-post.md",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }).?);
    try std.testing.expectEqual(PageKind.post_list, parsePageKind(.{
        .rel_path = "content/posts/_index.md",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }).?);
    try std.testing.expectEqual(PageKind.page, parsePageKind(.{
        .rel_path = "content/about.md",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }).?);
}

test "parsePageKind: non-content files return null" {
    try std.testing.expect(parsePageKind(.{
        .rel_path = "site.yaml",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }) == null);
    try std.testing.expect(parsePageKind(.{
        .rel_path = "templates/home.html",
        .dir_path = "",
        .abs_path = "",
        .file_ext = "",
        .file_name = "",
        .contents = "",
    }) == null);
    try std.testing.expect(parsePageKind(.{
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
    try std.testing.expect(isTemplate(.{ .rel_path = "templates/base.html", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(isTemplate(.{ .rel_path = "templates/", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isTemplate(.{ .rel_path = "content/templates/", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isTemplate(.{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}

test "isPostList" {
    try std.testing.expect(isPostList(.{ .rel_path = "content/posts/_index.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPostList(.{ .rel_path = "content/posts/other.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPostList(.{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}

test "isPost" {
    try std.testing.expect(isPost(.{ .rel_path = "content/posts/my-post.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(isPost(.{ .rel_path = "content/posts/", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPost(.{ .rel_path = "content/_index.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPost(.{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}

test "isHomePage" {
    try std.testing.expect(isHomePage(.{ .rel_path = "content/_index.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isHomePage(.{ .rel_path = "content/posts/_index.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isHomePage(.{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}

test "isPage" {
    try std.testing.expect(isPage(.{ .rel_path = "content/about.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(isPage(.{ .rel_path = "content/posts/my-post.md", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPage(.{ .rel_path = "templates/home.html", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
    try std.testing.expect(!isPage(.{ .rel_path = "", .dir_path = "", .abs_path = "", .file_ext = "", .file_name = "", .contents = "" }));
}
