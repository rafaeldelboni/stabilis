const std = @import("std");

fn isMap(comptime T: type) bool {
    const Ty = if (@typeInfo(T) == .optional) @typeInfo(T).optional.child else T;
    if (@typeInfo(Ty) != .@"struct") return false;
    inline for (@typeInfo(Ty).@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, "metadata")) return true;
        if (std.mem.eql(u8, f.name, "index_header")) return true;
        if (std.mem.eql(u8, f.name, "unmanaged") and isMap(f.type)) return true;
    }
    return false;
}

fn writeValue(j: *std.json.Stringify, value: anytype) !void {
    if (comptime isMap(@TypeOf(value))) {
        try j.beginObject();
        var it = value.iterator();
        while (it.next()) |e| {
            try j.objectField(e.key_ptr.*);
            try writeValue(j, e.value_ptr.*);
        }
        try j.endObject();
        return;
    }
    if (comptime @typeInfo(@TypeOf(value)) != .@"struct") return j.write(value);

    try j.beginObject();
    inline for (@typeInfo(@TypeOf(value)).@"struct".fields) |f| {
        if (f.type != void) {
            const v = @field(value, f.name);
            const opt = @typeInfo(f.type) == .optional;
            if (!opt or v != null) {
                try j.objectField(f.name);
                try writeValue(j, if (opt) v.? else v);
            }
        }
    }
    try j.endObject();
}

pub fn dumpJson(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var j: std.json.Stringify = .{ .writer = &out.writer, .options = .{ .whitespace = .indent_2 } };
    try writeValue(&j, value);
    return out.toOwnedSlice();
}

pub fn printJson(arena: *std.heap.ArenaAllocator, value: anytype) !void {
    const allocator = arena.allocator();
    const json = try dumpJson(allocator, value);
    std.debug.print("{s}\n", .{json});
}
