const std = @import("std");

pub fn downloadUrlToFilePath(
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    cwd: std.Io.Dir,
    url: []const u8,
    file_path: []const u8,
) !void {
    var client: std.http.Client = .{ .allocator = arena.allocator(), .io = io };
    defer client.deinit();

    var file = try cwd.createFile(io, file_path, .{});
    var wbuf: [4096]u8 = undefined;
    var fw = file.writer(io, &wbuf);
    _ = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &fw.interface,
    });
    try fw.interface.flush();
    file.close(io);
}
