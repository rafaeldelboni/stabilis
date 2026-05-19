const std = @import("std");
const Io = std.Io;

const md4c = @cImport({
    @cInclude("md4c.h");
    @cInclude("md4c-html.h");
});

pub fn main(init: std.process.Init) !void {
    // components
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    const md = try readInput(arena, io, "test.md");
    std.debug.print("Markdown: {s}\n", .{md});
    const html_src: []u8 = try markdownToHtml(arena, md);
    std.debug.print("Html: {s}", .{html_src});
    try writeFile(io, html_src, "test.html");

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }
}

fn readInput(allocator: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    return try std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited);
}

fn writeFile(io: Io, data: []const u8, path: []const u8) !void {
    return std.Io.Dir.writeFile(std.Io.Dir.cwd(), io, .{
        .sub_path = path,
        .data = data,
    });
}

// md4c callback context
const MdCtx = struct {
    list: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,
    failed: bool = false,

    fn callback(text: [*c]const u8, size: c_uint, userdata: ?*anyopaque) callconv(.c) void {
        const ctx: *MdCtx = @ptrCast(@alignCast(userdata.?));
        ctx.list.appendSlice(ctx.allocator, text[0..size]) catch {
            ctx.failed = true;
        };
    }
};

fn markdownToHtml(allocator: std.mem.Allocator, md: []const u8) ![]u8 {
    var ctx = MdCtx{ .allocator = allocator };
    errdefer ctx.list.deinit(allocator);
    const rc = md4c.md_html(md.ptr, @intCast(md.len), MdCtx.callback, &ctx, md4c.MD_DIALECT_GITHUB, 0);
    if (rc != 0) return error.Md4cParseError;
    if (ctx.failed) return error.Md4cParseError;
    return ctx.list.toOwnedSlice(allocator);
}
