const std = @import("std");

/// Prints a formatted message to stdout.
pub fn print(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    try stdout.interface.print(fmt, args);
    try stdout.flush();
}

/// Prints a formatted message to stderr.
pub fn errPrint(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buf);
    try stderr.interface.print(fmt, args);
    try stderr.flush();
}

/// Prints the version string to stdout.
pub fn printVersion(io: std.Io, name: []const u8, version: []const u8) !void {
    var buf: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    try stdout.interface.print("{s} {s}\n", .{ name, version });
    try stdout.flush();
}
