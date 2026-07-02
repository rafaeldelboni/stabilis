const std = @import("std");

const models = @import("../models.zig");
const DateTime = models.DateTime;

/// Formats a `DateTime` as an ISO 8601 string (`YYYY-MM-DDThh:mm:ssZ`).
pub fn toIsoString(arena: *std.heap.ArenaAllocator, d: DateTime) ![]const u8 {
    return try std.fmt.allocPrint(
        arena.allocator(),
        "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ d.year, d.month, d.day, d.hour, d.min, d.sec },
    );
}

const month_names = [_][]const u8{
    "January", "February", "March",     "April",   "May",      "June",
    "July",    "August",  "September", "October", "November", "December",
};

/// Formats a `DateTime` for human display (`July 2, 2026 · 14:30`).
pub fn toHumanString(arena: *std.heap.ArenaAllocator, d: DateTime) ![]const u8 {
    return try std.fmt.allocPrint(
        arena.allocator(),
        "{s} {d}, {d} · {d:0>2}:{d:0>2}",
        .{ month_names[d.month - 1], d.day, d.year, d.hour, d.min },
    );
}

test "toIsoString: datetime formatted to RFC3339" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try toIsoString(&arena, .{
        .year = 2026,
        .month = 5,
        .day = 18,
        .hour = 10,
        .min = 0,
        .sec = 0,
    });
    try std.testing.expectEqualStrings("2026-05-18T10:00:00Z", result);
}

test "toHumanString: datetime formatted for display" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try toHumanString(&arena, .{
        .year = 2026,
        .month = 7,
        .day = 2,
        .hour = 14,
        .min = 30,
        .sec = 0,
    });
    try std.testing.expectEqualStrings("July 2, 2026 · 14:30", result);
}
