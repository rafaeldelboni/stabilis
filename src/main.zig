const std = @import("std");
const build_options = @import("build_options");

const cli_adapter = @import("adapters/cli.zig");
const frontmatter = @import("adapters/frontmatter.zig");
const page = @import("adapters/page.zig");
const site = @import("adapters/site.zig");
const config = @import("logic/config.zig");
const models = @import("models.zig");
const CommandsResult = models.CommandsResult;
const Context = models.Context;
const Frontmatter = models.Frontmatter;
const Page = models.Page;
const Site = models.Site;
const BuildResult = models.BuildResult;
const NewPostResult = models.NewPostResult;
const NewPageResult = models.NewPageResult;
const modelsCli = @import("models/cli.zig");
const cli_help = @import("ports/cli.zig");
const fs_reader = @import("ports/fs_reader.zig");
const fs_writer = @import("ports/fs_writer.zig");
const printer = @import("ports/printer.zig");
const str = @import("adapters/string.zig");
const time = @import("ports/time.zig");

fn newPageHandler(arena: *std.heap.ArenaAllocator, io: std.Io, args: NewPageResult, source_dir: []const u8) !void {
    const allocator = arena.allocator();
    const slug = args.slug orelse try str.parseSlug(arena, args.title);
    const fm = Frontmatter{
        .title = args.title,
        .date = time.now(io),
        .slug = slug,
        .draft = args.draft,
        .menus = args.menus,
    };
    const file_header = try frontmatter.frontmatterToYamlString(arena, fm);
    const file_body = try std.mem.concat(allocator, u8, &.{ "\n## ", args.title, "\n" });
    const file = try std.mem.concat(allocator, u8, &.{ file_header, file_body });
    const file_path = try std.Io.Dir.path.join(allocator, &.{
        source_dir, config.content_dir, try std.mem.concat(allocator, u8, &.{ slug, config.content_ext }),
    });
    try fs_writer.writeFileDeep(io, file, file_path);
    try printer.print(io, "Created page: {s}\n", .{file_path});
}

fn newPostHandler(arena: *std.heap.ArenaAllocator, io: std.Io, args: NewPostResult, source_dir: []const u8) !void {
    const allocator = arena.allocator();
    const slug = try str.parseSlug(arena, args.title);
    const fm = Frontmatter{
        .title = args.title,
        .date = time.now(io),
        .description = args.description,
        .slug = slug,
        .draft = args.draft,
        .tags = args.tags,
    };
    const file_header = try frontmatter.frontmatterToYamlString(arena, fm);
    const file_body = try std.mem.concat(allocator, u8, &.{ "\n## ", args.title, "\n\n", args.description orelse "" });
    const file = try std.mem.concat(allocator, u8, &.{ file_header, file_body });
    const file_path = try std.Io.Dir.path.join(allocator, &.{
        source_dir, config.content_dir, config.posts_dir, try std.mem.concat(allocator, u8, &.{ slug, config.content_ext }),
    });
    try fs_writer.writeFileDeep(io, file, file_path);
    try printer.print(io, "Created post: {s}\n", .{file_path});
}

fn renderSite(
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    output_dir: []const u8,
    site_data: Site,
) !void {
    const allocator = arena.allocator();

    var post_list = try std.ArrayList(Context).initCapacity(allocator, site_data.posts.len);
    for (site_data.posts) |post| try post_list.append(allocator, post.context);

    const all_pages = try std.mem.concat(allocator, Page, &.{ site_data.posts, site_data.pages });
    for (all_pages) |p|
        try fs_writer.writePage(arena, io, output_dir, p, post_list.items, site_data);

    for (site_data.tags.map.values()) |tag| {
        var tagged = try allocator.alloc(Context, tag.indexes.items.len);
        for (tag.indexes.items, 0..) |idx, i| tagged[i] = site_data.posts[idx].context;
        try fs_writer.writePage(arena, io, output_dir, tag.page, tagged, site_data);
    }
}

fn buildHandler(arena: *std.heap.ArenaAllocator, io: std.Io, args: BuildResult, source_dir: []const u8) !void {
    const output_dir = args.destination orelse models.default_output_dir;

    if (args.clear_dir) try fs_writer.deleteDir(io, output_dir);

    const files = try fs_reader.loadFiles(arena, io, source_dir);

    const site_data = try site.parse(arena, files, args.build_drafts);
    if (site_data.posts.len == 0 and site_data.pages.len == 0) return error.NoFilesFound;

    try renderSite(arena, io, output_dir, site_data);

    const static_source = try std.Io.Dir.path.join(arena.allocator(), &.{ source_dir, config.static_dir });

    fs_writer.copyDir(io, arena, static_source, output_dir) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    try printer.print(io, "Site from: {s} created on: {s}\n", .{ source_dir, output_dir });
}

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    var diag = modelsCli.Diagnostics{};
    const cli = models.stabilis_cli;
    const args = try init.minimal.args.toSlice(arena.allocator());

    const out = cli_adapter.parse(&arena, args, cli, &diag) catch |err| {
        if (err != error.NoCommand) try cli_help.printDiagError(io, &diag, err);
        try cli_help.printHelp(io, args, cli);
        return 2;
    };
    if (out.flags.version) {
        try printer.printVersion(io, cli.name, build_options.version);
        return 0;
    }
    if (out.flags.help) {
        try cli_help.printHelp(io, args, cli);
        return 0;
    }

    const source_dir = out.flags.source_dir orelse "./";

    _ = switch (out.commands orelse return 0) {
        .build => |build_args| buildHandler(&arena, io, build_args, source_dir),
        .serve => |serve_args| printer.errPrint(io, "serve not implemented: {any}\n", .{serve_args}),
        .new => |new_args| switch (new_args) {
            .post => newPostHandler(&arena, io, new_args.post, source_dir),
            .page => newPageHandler(&arena, io, new_args.page, source_dir),
        },
    } catch |err| {
        if (err == error.NoFilesFound or err == error.FileNotFound)
            try printer.errPrint(io, "No {s} files found on: {s}\n", .{ cli.name, source_dir })
        else
            try printer.errPrint(io, "error: {}\n", .{err});
        return 2;
    };
    return 0;
}

test {
    _ = @import("adapters/cli.zig");
    _ = @import("adapters/frontmatter.zig");
    _ = @import("adapters/markdown.zig");
    _ = @import("adapters/page.zig");
    _ = @import("adapters/site.zig");
    _ = @import("adapters/string.zig");
    _ = @import("adapters/template.zig");
    _ = @import("adapters/time.zig");
    _ = @import("adapters/yaml_lexer.zig");
    _ = @import("logic/config.zig");
    _ = @import("logic/frontmatter.zig");
    _ = @import("logic/site.zig");
    _ = @import("logic/template.zig");
    _ = @import("logic/yaml_lexer.zig");
    _ = @import("ports/cli.zig");
    _ = @import("ports/fs_reader.zig");
    _ = @import("ports/fs_writer.zig");
    _ = @import("ports/printer.zig");
    _ = @import("ports/time.zig");
    _ = @import("models.zig");
}
