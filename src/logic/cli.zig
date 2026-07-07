const std = @import("std");

const modelsCli = @import("../models/cli.zig");
const Flag = modelsCli.Flag;

/// Maps a field type to its CLI value kind for help output.
pub const FlagType = enum {
    boolean,
    number,
    list_of_strings,
    string,
};

/// Infers the `FlagType` from a struct field's type at comptime.
pub fn parseFieldTypes(comptime T: type) FlagType {
    return switch (@typeInfo(T)) {
        .bool => .boolean,
        .int => .number,
        .optional => |info| parseFieldTypes(info.child),
        .pointer => |info| if (info.size == .slice and @typeInfo(info.child) == .pointer)
            .list_of_strings
        else
            .string,
        else => .string,
    };
}

/// True when `name` equals the flag's long or short form.
pub fn nameMatches(name: []const u8, flag: Flag) bool {
    return std.mem.eql(u8, name, flag.long) or std.mem.eql(u8, name, flag.short);
}

/// True when `token` looks like a flag (starts with `-`, not `--`).
pub fn looksLikeFlag(token: []const u8) bool {
    return token.len > 1 and token[0] == '-' and !std.mem.eql(u8, token, "--");
}

/// True when `token` begins with a dash, i.e. could be a flag token.
pub fn startsLikeFlag(token: []const u8) bool {
    return token.len > 0 and token[0] == '-';
}

/// Splits a `--flag=value` token into `(flag, value)`, or null when there is
/// no `=` separator.
pub fn splitFlagAssignment(arg: []const u8) ?struct { head: []const u8, value: []const u8 } {
    const eq = std.mem.findScalar(u8, arg, '=') orelse return null;
    return .{ .head = arg[0..eq], .value = arg[eq + 1 ..] };
}

const testing = std.testing;

test "parseFieldTypes infers bool, int, string, list_of_strings, optional" {
    try testing.expectEqual(.boolean, parseFieldTypes(bool));
    try testing.expectEqual(.number, parseFieldTypes(u16));
    try testing.expectEqual(.number, parseFieldTypes(i32));
    try testing.expectEqual(.string, parseFieldTypes([]const u8));
    try testing.expectEqual(.list_of_strings, parseFieldTypes([]const []const u8));
    try testing.expectEqual(.number, parseFieldTypes(?u16));
    try testing.expectEqual(.string, parseFieldTypes(?[]const u8));
}

test "nameMatches matches long or short, rejects other" {
    const flag = Flag{ .long = "--name", .short = "-n", .field = "name", .help = "" };
    try testing.expect(nameMatches("--name", flag));
    try testing.expect(nameMatches("-n", flag));
    try testing.expect(!nameMatches("--other", flag));
    try testing.expect(!nameMatches("", flag));
}

test "looksLikeFlag true for short and long flags, false for -- and value" {
    try testing.expect(looksLikeFlag("-n"));
    try testing.expect(looksLikeFlag("--name"));
    try testing.expect(!looksLikeFlag("--"));
    try testing.expect(!looksLikeFlag("value"));
    try testing.expect(!looksLikeFlag(""));
    try testing.expect(!looksLikeFlag("-"));
}

test "startsLikeFlag true for any leading dash, false otherwise" {
    try testing.expect(startsLikeFlag("-"));
    try testing.expect(startsLikeFlag("-n"));
    try testing.expect(startsLikeFlag("--name"));
    try testing.expect(startsLikeFlag("--"));
    try testing.expect(!startsLikeFlag("value"));
    try testing.expect(!startsLikeFlag(""));
}

test "splitFlagAssignment splits on =, returns null when absent" {
    const split = splitFlagAssignment("--name=value").?;
    try testing.expectEqualStrings("--name", split.head);
    try testing.expectEqualStrings("value", split.value);
    try testing.expect(splitFlagAssignment("--name") == null);
    try testing.expect(splitFlagAssignment("") == null);
    const empty_val = splitFlagAssignment("--name=").?;
    try testing.expectEqualStrings("--name", empty_val.head);
    try testing.expectEqualStrings("", empty_val.value);
}
