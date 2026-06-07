const std = @import("std");

/// If `value` starts with exactly one indentation level (2 spaces).
/// Returns the `value` with indentation cut or null.
pub fn extractIndentedLine(value: []const u8) ?[]const u8 {
    const indentation = "  ";
    return std.mem.cutPrefix(u8, value, indentation);
}

/// If `value` starts with block list indicator "- ".
/// Returns the `value` with block list indicator cut or null.
pub fn extractBlockListItem(value: []const u8) ?[]const u8 {
    const block_list_indicator = "- ";
    return std.mem.cutPrefix(u8, value, block_list_indicator);
}

test extractIndentedLine {
    // Strips exactly one indentation level.
    try std.testing.expectEqualStrings("hello", extractIndentedLine("  hello").?);
    // Returns null when not indented.
    try std.testing.expect(extractIndentedLine("hello") == null);
    try std.testing.expect(extractIndentedLine("") == null);
    try std.testing.expect(extractIndentedLine(" ") == null);
    // Only strips the first 2 spaces.
    try std.testing.expectEqualStrings("  hello", extractIndentedLine("    hello").?);
    // Empty result when input is exactly the indentation.
    try std.testing.expectEqualStrings("", extractIndentedLine("  ").?);
}

test extractBlockListItem {
    // Strips "- " prefix.
    try std.testing.expectEqualStrings("hello", extractBlockListItem("- hello").?);
    // Returns null when prefix is absent.
    try std.testing.expect(extractBlockListItem("hello") == null);
    try std.testing.expect(extractBlockListItem("") == null);
    try std.testing.expect(extractBlockListItem("-") == null);
    // Empty result when input is exactly "- ".
    try std.testing.expectEqualStrings("", extractBlockListItem("- ").?);
}
