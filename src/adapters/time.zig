const std = @import("std");

const models = @import("../models.zig");
const DateTime = models.DateTime;

/// Formats a `DateTime` as an RFC3339 string (`YYYY-MM-DDThh:mm:ssZ`).
pub fn toString(arena: *std.heap.ArenaAllocator, d: DateTime) ![]const u8 {
    return try std.fmt.allocPrint(
        arena.allocator(),
        "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ d.year, d.month, d.day, d.hour, d.min, d.sec },
    );
}

test "toString: datetime formatted to RFC3339" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try toString(&arena, .{
        .year = 2026,
        .month = 5,
        .day = 18,
        .hour = 10,
        .min = 0,
        .sec = 0,
    });
    try std.testing.expectEqualStrings("2026-05-18T10:00:00Z", result);
}
