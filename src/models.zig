const std = @import("std");

pub const SliceBetween = struct {
    content: []const u8,
    open_index: usize,
    close_index: usize,
};

pub const File = struct {
    cwd_path: []const u8,
    dir_path: []const u8,
    abs_path: []const u8,
    file_ext: []const u8,
    file_name: []const u8,
};

pub const DateTime = struct {
    sec: u6, // [0, 60]
    min: u6, // [0, 59]
    hour: u5, // [0, 23]
    day: u5, // [1, 31]
    month: u4, // [1, 12]
    year: i16, // C.E.
};

pub const MapEntry = struct {
    key: []const u8,
    value: YamlNode,
};

pub const YamlNode = union(enum) {
    string: []const u8,
    boolean: bool,
    list: []const YamlNode,
    map: []const MapEntry,
    datetime: DateTime,
    null,
};

pub const ImageSpec = struct {
    file: []const u8,
    caption: ?[]const u8,
};

pub const Frontmatter = struct {
    title: ?[]const u8 = null,
    author: ?[]const u8 = null,
    date: ?[]const u8 = null,
    slug: ?[]const u8 = null,
    description: ?[]const u8 = null,
    draft: bool = false,
    cover: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    menus: []const []const u8 = &.{},
    images: []const ImageSpec = &.{},
};

pub const ContentEntry = struct { frontmatter: Frontmatter, source: []const u8 };

pub const PageKind = union(enum) {
    home,
    post,
    page,
    post_list,
};

pub const Templates = std.StringHashMap([]const u8);

pub const Page = struct {
    kind: PageKind = .page,
    frontmatter: Frontmatter,
    body_html: []const u8,
    url: []const u8,
    source_path: []const u8,
};

pub const Post = struct {
    kind: PageKind = .post,
    frontmatter: Frontmatter,
    body_html: []const u8,
    url: []const u8,
    source_path: []const u8,
};

pub const MenuItem = struct {
    name: []const u8,
    url: []const u8,
};

pub const Site = struct {
    title: []const u8,
    base_url: []const u8,
    templates: Templates,
    pages: []const Page,
    posts: []const Post,
    menu_main: []const MenuItem,
};

pub const CtxValue = union(enum) {
    string: []const u8,
    list: []const std.StringHashMap(CtxValue),
};
