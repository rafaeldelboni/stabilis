const std = @import("std");
const Io = std.Io;

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
