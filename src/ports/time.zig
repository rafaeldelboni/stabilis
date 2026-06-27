const std = @import("std");

const models = @import("../models.zig");
const DateTime = models.DateTime;
const time_logic = @import("../adapters/time.zig");

/// Returns the current wall-clock time via the `Io` instance.
pub fn now(io: std.Io) DateTime {
    const secs: u64 = @intCast(std.Io.Clock.now(.real, io).toSeconds());

    const day = std.time.epoch.EpochDay{ .day = @intCast(@divFloor(secs, std.time.epoch.secs_per_day)) };
    const yd = day.calculateYearDay();
    const md = yd.calculateMonthDay();

    const time_of_day = std.time.epoch.DaySeconds{ .secs = @intCast(@mod(secs, std.time.epoch.secs_per_day)) };
    const h = time_of_day.getHoursIntoDay();
    const m = time_of_day.getMinutesIntoHour();
    const s = time_of_day.getSecondsIntoMinute();

    return DateTime{
        .sec = s,
        .min = m,
        .hour = h,
        .day = md.day_index + 1,
        .month = md.month.numeric(),
        .year = @intCast(yd.year),
    };
}

/// Returns the current wall-clock time formatted as an RFC3339 string.
pub fn nowString(arena: *std.heap.ArenaAllocator, io: std.Io) ![]const u8 {
    return try time_logic.toString(arena, now(io));
}

test "now: returns sane date values" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    const dt = now(io);

    try std.testing.expect(dt.year >= 2026);
    try std.testing.expect(dt.month >= 1 and dt.month <= 12);
    try std.testing.expect(dt.day >= 1 and dt.day <= 31);
    try std.testing.expect(dt.hour <= 23);
    try std.testing.expect(dt.min <= 59);
    try std.testing.expect(dt.sec <= 59);
}

test "nowString: returns RFC3339 formatted current time" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try nowString(&arena, io);
    try std.testing.expect(result.len > 0);
}
