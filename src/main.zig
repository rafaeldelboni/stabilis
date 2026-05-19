const std = @import("std");
const Io = std.Io;

const stabilis = @import("stabilis");

const md4c = @cImport({
    @cInclude("md4c.h");
    @cInclude("md4c-html.h");
});

pub fn main(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // In order to do I/O operations need an `Io` instance.
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

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stabilis.printAnotherMessage(stdout_writer);

    try stdout_writer.flush(); // Don't forget to flush!
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

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}
