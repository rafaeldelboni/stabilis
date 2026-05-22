const std = @import("std");
const Io = std.Io;

pub fn readFile(io: Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited);
}
