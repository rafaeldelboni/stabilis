const std = @import("std");

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

pub fn toHtml(allocator: std.mem.Allocator, md: []const u8) ![]u8 {
    var ctx = MdCtx{ .allocator = allocator };
    errdefer ctx.list.deinit(allocator);
    const rc = md4c.md_html(md.ptr, @intCast(md.len), MdCtx.callback, &ctx, md4c.MD_DIALECT_GITHUB, 0);
    if (rc != 0) return error.Md4cParseError;
    if (ctx.failed) return error.Md4cParseError;
    return ctx.list.toOwnedSlice(allocator);
}