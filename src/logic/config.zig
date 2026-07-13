const std = @import("std");

const models = @import("../models.zig");
const Config = models.Config;
const PageKind = models.PageKind;

pub const config_file = "site.yaml";
pub const content_dir = "content";
pub const templates_dir = "templates";
pub const static_dir = "static";
pub const posts_dir = "posts";
pub const content_ext = ".md";
pub const index_file_name = "_index.md";
pub const output_index = "index.html";
pub const template_home_file_name = "home.html";
pub const template_post_file_name = "post.html";
pub const template_page_file_name = "page.html";
pub const template_post_list_file_name = "post-list.html";
pub const template_tag_post_list_file_name = "tag-post-list.html";
pub const template_atom_feed_file_name = "feed.atom";
pub const default_author = "";
pub const default_description = "";

/// All defaults as a `Config` value. Used as fallback by `adapters/config.zig`
pub const default = Config{
    .title = "",
    .base_url = "",
    .base_uri = .{ .scheme = "" },
    .author = default_author,
    .description = default_description,
    .menu_main = &.{},

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

    .home_page_path = content_dir ++ "/" ++ index_file_name,
    .post_list_path = content_dir ++ "/" ++ posts_dir ++ "/" ++ index_file_name,
    .posts_path_prefix = content_dir ++ "/" ++ posts_dir ++ "/",
    .pages_path_prefix = content_dir ++ "/",
    .templates_prefix = templates_dir ++ "/",
    .post_url_prefix = "/" ++ posts_dir,
    .tag_post_list_url_prefix = "/" ++ posts_dir ++ "/tags",
};

/// Returns the template filename for the given page kind.
pub fn templateNameFor(kind: PageKind) []const u8 {
    return switch (kind) {
        .home => template_home_file_name,
        .post => template_post_file_name,
        .page => template_page_file_name,
        .post_list => template_post_list_file_name,
        .tag_post_list => template_tag_post_list_file_name,
        .atom_feed => template_atom_feed_file_name,
    };
}

test "templateNameFor: each kind" {
    try std.testing.expectEqualStrings("home.html", templateNameFor(.home));
    try std.testing.expectEqualStrings("post.html", templateNameFor(.post));
    try std.testing.expectEqualStrings("page.html", templateNameFor(.page));
    try std.testing.expectEqualStrings("post-list.html", templateNameFor(.post_list));
    try std.testing.expectEqualStrings("tag-post-list.html", templateNameFor(.tag_post_list));
    try std.testing.expectEqualStrings("feed.atom", templateNameFor(.atom_feed));
}
