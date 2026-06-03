const std = @import("std");

/// Serializes any value to an indented JSON string. Caller owns the returned
/// slice and must free it with the same allocator.
///
/// Usage:
///   const json = try dumpJson(allocator, value);
///   defer allocator.free(json);
///   std.debug.print("{s}\n", .{json});
pub fn dumpJson(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var write_stream: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try write_stream.write(value);

    return out.toOwnedSlice();
}
