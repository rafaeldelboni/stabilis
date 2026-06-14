const std = @import("std");

const frontmatter = @import("adapters/frontmatter.zig");
const markdown = @import("adapters/markdown.zig");
const page = @import("adapters/page.zig");
const site = @import("adapters/site.zig");
const template = @import("adapters/template.zig");
const yaml_lexer = @import("adapters/yaml_lexer.zig");
const models = @import("models.zig");
const Context = models.Context;
const Page = models.Page;
const Site = models.Site;
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

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(init.gpa);
    const allocator = arena.allocator();
    defer arena.deinit();

    var args = init.minimal.args.iterate();
    _ = args.skip(); // skip program name
    const output_dir = args.next() orelse "public";
    const input_dir = args.next() orelse "example";

    try fs_writer.deleteDir(io, output_dir); // TODO toogle via cli

    const files = try fs_reader.walkDir(io, &arena, input_dir);
    const site_data = try site.parse(&arena, files);

    var post_list = try std.ArrayList(Context).initCapacity(allocator, site_data.posts.len);
    for (site_data.posts) |post| try post_list.append(allocator, post.context);

    for (site_data.posts) |p|
        try writePage(&arena, io, output_dir, p, post_list.items, site_data);

    for (site_data.pages) |p|
        try writePage(&arena, io, output_dir, p, post_list.items, site_data);

    std.debug.print("Site from: {s}/ created on: {s}/\n", .{ input_dir, output_dir });
}

test {
    _ = @import("adapters/frontmatter.zig");
    _ = @import("adapters/markdown.zig");
    _ = @import("adapters/site.zig");
    _ = @import("adapters/template.zig");
    _ = @import("adapters/yaml_lexer.zig");
    _ = @import("logic/frontmatter.zig");
    _ = @import("logic/site.zig");
    _ = @import("logic/template.zig");
    _ = @import("logic/yaml_lexer.zig");
    _ = @import("ports/fs_reader.zig");
    _ = @import("ports/fs_writer.zig");
    _ = @import("models.zig");
    _ = @import("string.zig");
}
