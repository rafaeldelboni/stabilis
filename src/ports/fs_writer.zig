const std = @import("std");
const Io = std.Io;

const models = @import("../models.zig");
const Context = models.Context;
const Page = models.Page;
const Site = models.Site;
const page = @import("../adapters/page.zig");

pub fn writeFile(io: Io, data: []const u8, path: []const u8) !void {
    return std.Io.Dir.writeFile(std.Io.Dir.cwd(), io, .{
        .sub_path = path,
        .data = data,
    });
}

pub fn writeFileDeep(io: Io, data: []const u8, path: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |dir_path| {
        try std.Io.Dir.createDirPath(std.Io.Dir.cwd(), io, dir_path);
    }
    try writeFile(io, data, path);
}

pub fn deleteDir(io: Io, path: []const u8) !void {
    try std.Io.Dir.deleteTree(std.Io.Dir.cwd(), io, path);
}

pub fn writePage(
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    output_dir: []const u8,
    page_data: Page,
    post_list: []Context,
    site_data: Site,
) !void {
    const file_path = try page.parseFilePath(arena, output_dir, page_data);
    const html = try page.parseHtml(arena, page_data, post_list, site_data);
    try writeFileDeep(io, html, file_path);
}
