const std = @import("std");
const Io = std.Io;

pub fn writeFile(io: Io, data: []const u8, path: []const u8) !void {
    return std.Io.Dir.writeFile(std.Io.Dir.cwd(), io, .{
        .sub_path = path,
        .data = data,
    });
}