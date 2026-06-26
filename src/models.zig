const std = @import("std");

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

pub const NewPostArgs = struct {
    title: []const u8 = "",
    description: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    draft: bool = false,
};

pub const NewPageArgs = struct {
    title: []const u8 = "",
    slug: ?[]const u8 = null,
    draft: bool = false,
    menus: []const []const u8 = &.{},
};

pub const ServeArgs = struct {
    port: ?u16 = null,
    bind: ?[]const u8 = null,
    open: bool = false,
    no_drafts: bool = false,
};

pub const BuildArgs = struct {
    source: ?[]const u8 = null,
    destination: ?[]const u8 = null,
    build_drafts: bool = false,
    minify: bool = false,
    clear_dir: bool = false,
};

pub const GlobalArgs = struct {
    version: bool = false,
    help: bool = false,
};

pub const CommandResult = union(enum) {
    build: BuildArgs,
    serve: ServeArgs,
    new: union(enum) { post: NewPostArgs, page: NewPageArgs },
};

pub const stabilis_cli = modelsCli.Cli{
    .SharedResultT = GlobalArgs,
    .shared_flags = &.{
        .{ .long = "--help", .short = "-h", .field = "help", .terminal = true, .help = "Show help" },
        .{ .long = "--version", .short = "-v", .field = "version", .terminal = true, .help = "Print version" },
    },
    .CommandResultT = CommandResult,
    .commands = &.{
        .{
            .name = "serve",
            .help = "Build and serve the site locally",
            .body = .{
                .command = modelsCli.CommandOptions{
                    .Result = ServeArgs,
                    .flags = &.{
                        .{ .long = "--port", .short = "-p", .field = "port", .help = "Port to serve on" },
                        .{ .long = "--bind", .short = "-b", .field = "bind", .help = "IP Address bind" },
                        .{ .long = "--open", .short = "-o", .field = "open", .help = "Open browser after serving" },
                        .{ .long = "--no-drafts", .short = "-n", .field = "no_drafts", .help = "Don't include draft content" },
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
                    .Result = BuildArgs,
                    .flags = &.{
                        .{ .long = "--dest", .short = "-d", .field = "destination", .help = "Output directory destination" },
                        .{ .long = "--build-drafts", .short = "-b", .field = "build_drafts", .help = "Include draft content" },
                        .{ .long = "--minify", .short = "-m", .field = "minify", .help = "Minify the output" },
                        .{ .long = "--clear-dir", .short = "-c", .field = "clear_dir", .help = "Clear destination directory" },
                    },
                    .positionals = &.{"source"},
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
                                .Result = NewPostArgs,
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
                                .Result = NewPageArgs,
                                .flags = &.{
                                    .{ .long = "--slug", .short = "-s", .field = "slug", .help = "URL-friendly identifier (defaults to title)" },
                                    .{ .long = "--menus", .short = "-m", .field = "menus", .help = "Comma-separated list of menus this page appears in" },
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
};
