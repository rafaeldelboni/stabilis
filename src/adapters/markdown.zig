const std = @import("std");

const string = @import("../adapters/string.zig");

const md4c = @cImport({
    @cInclude("md4c.h");
    @cInclude("md4c-html.h");
});

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

pub fn toHtml(arena: *std.heap.ArenaAllocator, base_path: []const u8, md: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    var ctx = MdCtx{ .allocator = allocator };
    const rc = md4c.md_html(md.ptr, @intCast(md.len), MdCtx.callback, &ctx, md4c.MD_DIALECT_GITHUB, 0);
    if (rc != 0) return error.Md4cParseError;
    if (ctx.failed) return error.Md4cParseError;
    return try string.prefixRootRelativeUrls(arena, ctx.list.items, base_path);
}
