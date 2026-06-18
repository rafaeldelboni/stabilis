const std = @import("std");

pub const SliceBetween = struct {
    content: []const u8,
    open_index: usize,
    close_index: usize,
};

pub const File = struct {
    rel_path: []const u8,
    dir_path: []const u8,
    abs_path: []const u8,
    file_ext: []const u8,
    file_name: []const u8,
    contents: []const u8,
};

pub const DateTime = struct {
    sec: u6, // [0, 60]
    min: u6, // [0, 59]
    hour: u5, // [0, 23]
    day: u5, // [1, 31]
    month: u4, // [1, 12]
    year: i16, // C.E.
};

pub const MapEntries = std.json.ArrayHashMap(YamlNode);

pub const YamlNode = union(enum) {
    string: []const u8,
    boolean: bool,
    list: []const YamlNode,
    map: MapEntries,
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

pub const PageKind = enum {
    home,
    post,
    page,
    post_list,
};

pub const Templates = std.json.ArrayHashMap([]const u8);

pub const Context = std.json.ArrayHashMap(CtxValue);

pub const Page = struct {
    kind: PageKind,
    context: Context,
};

pub const Site = struct {
    title: []const u8,
    base_url: []const u8,
    templates: Templates,
    pages: []const Page,
    posts: []const Page,
    menu_main: []Context,
};

pub const CtxValue = union(enum) {
    string: []const u8,
    list: []const Context,
    bool: bool,
};

pub const Command = union(enum) {
    build: BuildArgs,
    new: NewSub,
    serve: ServeArgs,
    version,
    help,
};

pub const NewSub = union(enum) {
    post: NewPostArgs,
    page: NewPageArgs,
    help,
};

pub const NewPostArgs = struct {
    title: []const u8,
    description: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    draft: bool = false,
    help: bool = false,
};

pub const NewPageArgs = struct {
    title: []const u8,
    slug: ?[]const u8 = null,
    draft: bool = false,
    menus: []const []const u8 = &.{},
    help: bool = false,
};

pub const ServeArgs = struct {
    port: ?u16 = null,
    bind: ?[]const u8 = null,
    open: bool = false,
    build_drafts: bool = true,
    help: bool = false,
};

pub const BuildArgs = struct {
    source: ?[]const u8 = null,
    destination: ?[]const u8 = null,
    build_drafts: bool = false,
    minify: bool = false,
    clean_destination_dir: bool = false,
    help: bool = false,
};
