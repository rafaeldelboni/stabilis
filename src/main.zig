const std = @import("std");
const build_options = @import("build_options");

const cli_adapter = @import("adapters/cli.zig");
const frontmatter = @import("adapters/frontmatter.zig");
const page = @import("adapters/page.zig");
const site = @import("adapters/site.zig");
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
const str = @import("string.zig");
const time = @import("time.zig");

fn writePage(
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    output_dir: []const u8,
    page_data: Page,
    post_list: []Context,
    site_data: Site,
) !void {
    const file_path = try page.parseFilePath(arena, output_dir, page_data);
    const html = try page.parseHtml(arena, page_data, post_list, site_data);
    try fs_writer.writeFileDeep(io, html, file_path);
}

fn newPageHandler(arena: *std.heap.ArenaAllocator, io: std.Io, args: NewPageResult) !void {
    const allocator = arena.allocator();
    const output_dir = "./"; // TODO as arg?
    const slug = args.slug orelse try str.parseSlug(arena, args.title);
    const fm = Frontmatter{
        .title = args.title,
        .date = try time.toString(arena, time.now(io)),
        .slug = slug,
        .draft = args.draft,
        .menus = args.menus,
    };
    const file_header = try frontmatter.frontmatterToYamlString(arena, fm);
    const file_body = try std.mem.concat(allocator, u8, &.{ "\n## ", args.title, "\n"});
    const file = try std.mem.concat(allocator, u8, &.{ file_header, file_body });
    const file_path = try std.Io.Dir.path.join(allocator, &.{
        output_dir, "content", try std.mem.concat(allocator, u8, &.{ slug, ".md" }),
    });
    try fs_writer.writeFileDeep(io, file, file_path);
}

fn newPostHandler(arena: *std.heap.ArenaAllocator, io: std.Io, args: NewPostResult) !void {
    const allocator = arena.allocator();
    const output_dir = "./"; // TODO as arg?
    const slug = try str.parseSlug(arena, args.title);
    const fm = Frontmatter{
        .title = args.title,
        .date = try time.toString(arena, time.now(io)),
        .description = args.description,
        .slug = slug,
        .draft = args.draft,
        .tags = args.tags,
    };
    const file_header = try frontmatter.frontmatterToYamlString(arena, fm);
    const file_body = try std.mem.concat(allocator, u8, &.{ "\n## ", args.title, "\n\n", args.description orelse "" });
    const file = try std.mem.concat(allocator, u8, &.{ file_header, file_body });
    const file_path = try std.Io.Dir.path.join(allocator, &.{
        output_dir, "content", "posts", try std.mem.concat(allocator, u8, &.{ slug, ".md" }),
    });
    try fs_writer.writeFileDeep(io, file, file_path);
}

fn buildHandler(arena: *std.heap.ArenaAllocator, io: std.Io, args: BuildResult) !void {
    const allocator = arena.allocator();

    const output_dir = args.destination orelse "public";
    const input_dir = args.source orelse "example";

    if (args.clear_dir) try fs_writer.deleteDir(io, output_dir);

    const files = try fs_reader.walkDir(io, arena, input_dir);
    const site_data = try site.parse(arena, files, args.build_drafts);

    var post_list = try std.ArrayList(Context).initCapacity(allocator, site_data.posts.len);
    for (site_data.posts) |post| try post_list.append(allocator, post.context);

    for (site_data.posts) |p|
        try writePage(arena, io, output_dir, p, post_list.items, site_data);

    for (site_data.pages) |p|
        try writePage(arena, io, output_dir, p, post_list.items, site_data);

    std.debug.print("Site from: {s}/ created on: {s}/\n", .{ input_dir, output_dir });
}

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    var diag = modelsCli.Diagnostics{};
    const cli = models.stabilis_cli;
    const args = try init.minimal.args.toSlice(arena.allocator());

    const out = cli_adapter.parse(&arena, args, cli, &diag) catch |err| {
        try cli_help.printDiagError(io, &diag, err);
        try cli_help.printHelp(io, args, cli);
        return 2;
    };
    if (out.flags.version) {
        std.debug.print("stabilis {s}\n", .{build_options.version});
        return 0;
    }
    if (out.flags.help) {
        try cli_help.printHelp(io, args, cli);
        return 0;
    }
    try switch (out.commands orelse return 0) {
        .build => |build_args| buildHandler(&arena, io, build_args),
        .serve => |serve_args| std.debug.print("serve not implemented: {any}\n", .{serve_args}),
        .new => |new_args| switch (new_args) {
            .post => newPostHandler(&arena, io, new_args.post),
            .page => newPageHandler(&arena, io, new_args.page),
        },
    };
    return 0;
}

test {
    _ = @import("adapters/cli.zig");
    _ = @import("adapters/frontmatter.zig");
    _ = @import("adapters/markdown.zig");
    _ = @import("adapters/site.zig");
    _ = @import("adapters/template.zig");
    _ = @import("adapters/yaml_lexer.zig");
    _ = @import("logic/frontmatter.zig");
    _ = @import("logic/site.zig");
    _ = @import("logic/template.zig");
    _ = @import("logic/yaml_lexer.zig");
    _ = @import("ports/cli.zig");
    _ = @import("ports/fs_reader.zig");
    _ = @import("ports/fs_writer.zig");
    _ = @import("models.zig");
    _ = @import("string.zig");
}
