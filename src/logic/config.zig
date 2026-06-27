const std = @import("std");
const models = @import("../models.zig");
const PageKind = models.PageKind;

pub const config_file = "site.yaml";
pub const content_dir = "content";
pub const templates_dir = "templates";
pub const posts_dir = "posts";
pub const content_ext = ".md";
pub const index_file_name = "_index.md";

pub const home_page_path = "content/_index.md";
pub const post_list_path = "content/posts/_index.md";
pub const posts_path_prefix = "content/posts/";
pub const pages_path_prefix = "content/";
pub const templates_prefix = "templates/";

pub const output_index = "index.html";

pub const post_url_prefix = "/posts";

pub fn templateNameFor(kind: PageKind) []const u8 {
    return switch (kind) {
        .home => "home.html",
        .post => "post.html",
        .page => "page.html",
        .post_list => "post-list.html",
    };
}

test "templateNameFor: each kind" {
    try std.testing.expectEqualStrings("home.html", templateNameFor(.home));
    try std.testing.expectEqualStrings("post.html", templateNameFor(.post));
    try std.testing.expectEqualStrings("page.html", templateNameFor(.page));
    try std.testing.expectEqualStrings("post-list.html", templateNameFor(.post_list));
}
