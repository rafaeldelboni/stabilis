const std = @import("std");

const options: std.json.Stringify.Options = .{
    .whitespace = .indent_2,
    .emit_null_optional_fields = false,
};

pub fn dumpJson(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, value, options);
}

pub fn printJson(value: anytype) void {
    std.debug.print("{f}\n", .{std.json.fmt(value, options)});
}
