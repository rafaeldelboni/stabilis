const std = @import("std");

const cli_adapter = @import("adapters/cli.zig");
const page = @import("adapters/page.zig");
const site = @import("adapters/site.zig");
const models = @import("models.zig");
const modelsCli = @import("models/cli.zig");
const CommandResult = models.CommandResult;
const Context = models.Context;
const Page = models.Page;
const Site = models.Site;
const BuildArgs = models.BuildArgs;
const cli_help = @import("ports/cli.zig");
const fs_reader = @import("ports/fs_reader.zig");
const fs_writer = @import("ports/fs_writer.zig");

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

fn buildHandler(arena: *std.heap.ArenaAllocator, io: std.Io, args: BuildArgs) !void {
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
    if (out.shared.help or out.shared.version) {
        try cli_help.printHelp(io, args, cli);
        return 0;
    }
    try switch (out.result orelse return 0) {
        .build => |build_args| buildHandler(&arena, io, build_args),
        .serve => |serve_args| std.debug.print("serve not implemented: {any}\n", .{serve_args}),
        .new => |new_args| switch (new_args) {
            .post => std.debug.print("new post not implemented: {any}\n", .{new_args.post}),
            .page => std.debug.print("new page not implemented: {any}\n", .{new_args.page}),
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
