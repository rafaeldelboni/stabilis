const std = @import("std");
const Io = std.Io;

pub fn readFile(io: Io, arena: *std.heap.ArenaAllocator, path: []const u8) ![]u8 {
    const allocator = arena.allocator();
    return try std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited);
}
