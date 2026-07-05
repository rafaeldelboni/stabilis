const std = @import("std");

pub const Config = struct {
    title: []const u8,
    base_url: []const u8,
    menu_main: []const Context,

    content_dir: []const u8,
    templates_dir: []const u8,
    static_dir: []const u8,
    posts_dir: []const u8,
    content_ext: []const u8,
    index_file_name: []const u8,
    output_index: []const u8,
    template_home_file_name: []const u8,
    template_post_file_name: []const u8,
    template_page_file_name: []const u8,
    template_post_list_file_name: []const u8,
    template_tag_post_list_file_name: []const u8,
    post_url_prefix: []const u8,

    home_page_path: []const u8,
    post_list_path: []const u8,
    posts_path_prefix: []const u8,
    pages_path_prefix: []const u8,
    templates_prefix: []const u8,
    tag_post_list_url_prefix: []const u8,
};

const modelsCli = @import("./models/cli.zig");

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
    sec: ?u6, // [0, 60]
    min: ?u6, // [0, 59]
    hour: ?u5, // [0, 23]
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
    author: ?[]const u8 = null,
    title: ?[]const u8 = null,
    date: ?DateTime = null,
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
    tag_post_list,
};

pub const Templates = std.json.ArrayHashMap([]const u8);

pub const Context = std.json.ArrayHashMap(CtxValue);

pub const Page = struct {
    kind: PageKind,
    context: Context,
};

pub const Tag = struct {
    page: Page,
    indexes: std.ArrayList(usize),
};

pub const Tags = std.json.ArrayHashMap(Tag);

pub const Site = struct {
    title: []const u8,
    base_url: []const u8,
    templates: Templates,
    pages: []const Page,
    posts: []const Page,
    tags: Tags,
    menu_main: []Context,
};

pub const CtxValue = union(enum) {
    string: []const u8,
    list: []const Context,
    bool: bool,
};

pub const NewPostResult = struct {
    title: []const u8 = "",
    description: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    draft: bool = false,
};

pub const NewPageResult = struct {
    title: []const u8 = "",
    slug: ?[]const u8 = null,
    draft: bool = false,
    menus: []const []const u8 = &.{},
};

pub const ServeResult = struct {
    destination: ?[]const u8 = null,
    no_drafts: bool = false,
    port: ?u16 = null,
    bind: ?[]const u8 = null,
    open: bool = false,
};

pub const BuildResult = struct {
    destination: ?[]const u8 = null,
    build_drafts: bool = false,
    minify: bool = false,
    clear_dir: bool = false,
};

pub const default_output_dir = "public";

pub const FlagsResult = struct {
    source_dir: ?[]const u8 = null,
    version: bool = false,
    help: bool = false,
};

pub const CommandsResult = union(enum) {
    build: BuildResult,
    serve: ServeResult,
    new: union(enum) { post: NewPostResult, page: NewPageResult },
};

pub const stabilis_cli = modelsCli.Cli{
    .name = "stabilis",
    .description = "A static site generator",
    .flags = .{
        .Result = FlagsResult,
        .items = &.{
            .{ .long = "--source-dir", .short = "-S", .field = "source_dir", .help = "Source directory" },
            .{ .long = "--help", .short = "-h", .field = "help", .terminal = true, .help = "Show help" },
            .{ .long = "--version", .short = "-v", .field = "version", .terminal = true, .help = "Print version" },
        },
    },
    .commands = .{
        .Result = CommandsResult,
        .items = &.{
            .{
                .name = "serve",
                .help = "Build and serve the site locally",
                .body = .{
                    .command = modelsCli.CommandOptions{
                        .Result = ServeResult,
                        .flags = &.{
                            .{ .long = "--dest", .short = "-d", .field = "destination", .help = "Output directory" },
                            .{ .long = "--no-drafts", .short = "-n", .field = "no_drafts", .help = "Don't include draft content" },
                            .{ .long = "--port", .short = "-p", .field = "port", .help = "Port to serve on" },
                            .{ .long = "--bind", .short = "-b", .field = "bind", .help = "IP address to bind" },
                            .{ .long = "--open", .short = "-o", .field = "open", .help = "Open browser after serving" },
                        },
                        .positionals = &.{},
                    },
                },
            },
            .{
                .name = "build",
                .help = "Build the site",
                .body = .{
                    .command = modelsCli.CommandOptions{
                        .Result = BuildResult,
                        .flags = &.{
                            .{ .long = "--dest", .short = "-d", .field = "destination", .help = "Output directory" },
                            .{ .long = "--build-drafts", .short = "-b", .field = "build_drafts", .help = "Include draft content" },
                            .{ .long = "--minify", .short = "-m", .field = "minify", .help = "Minify the output" },
                            .{ .long = "--clear-dir", .short = "-c", .field = "clear_dir", .help = "Clear destination directory" },
                        },
                        .positionals = &.{},
                    },
                },
            },
            .{
                .name = "new",
                .help = "Scaffold new content",
                .body = .{
                    .sub_commands = &.{
                        .{
                            .name = "post",
                            .help = "Scaffold new post",
                            .body = .{
                                .command = modelsCli.CommandOptions{
                                    .Result = NewPostResult,
                                    .flags = &.{
                                        .{ .long = "--desc", .short = "-d", .field = "description", .help = "One-line description" },
                                        .{ .long = "--tags", .short = "-t", .field = "tags", .help = "Comma-separated tags" },
                                        .{ .long = "--draft", .short = "-D", .field = "draft", .help = "Mark as draft" },
                                    },
                                    .positionals = &.{"title"},
                                },
                            },
                        },
                        .{
                            .name = "page",
                            .help = "Scaffold new page",
                            .body = .{
                                .command = modelsCli.CommandOptions{
                                    .Result = NewPageResult,
                                    .flags = &.{
                                        .{ .long = "--slug", .short = "-s", .field = "slug", .help = "URL-friendly identifier (defaults to title)" },
                                        .{ .long = "--menus", .short = "-m", .field = "menus", .help = "Comma-separated menus" },
                                        .{ .long = "--draft", .short = "-D", .field = "draft", .help = "Mark as draft" },
                                    },
                                    .positionals = &.{"title"},
                                },
                            },
                        },
                    },
                },
            },
        },
    },
};
