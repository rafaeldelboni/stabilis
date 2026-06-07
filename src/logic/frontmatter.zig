const std = @import("std");

pub fn startsWithFrontmatter(delimiter: []const u8, source: []const u8) bool {
    if (source.len < delimiter.len) return false;
    return std.mem.startsWith(u8, source, delimiter);
}

test "startsWithFrontmatter detects opening --- delimiter" {
    try std.testing.expectEqual(true, startsWithFrontmatter("---", "---"));
    try std.testing.expectEqual(true, startsWithFrontmatter("---", "---content"));
    try std.testing.expectEqual(true, startsWithFrontmatter("---", "---content---"));
    try std.testing.expectEqual(true, startsWithFrontmatter("---", "---\n"));
    try std.testing.expectEqual(true, startsWithFrontmatter("---", "---\r\n"));
    try std.testing.expectEqual(false, startsWithFrontmatter("---", "content---"));
    try std.testing.expectEqual(false, startsWithFrontmatter("---", ""));
    try std.testing.expectEqual(false, startsWithFrontmatter("---", "--"));
    try std.testing.expectEqual(false, startsWithFrontmatter("---", "  ---"));
    try std.testing.expectEqual(false, startsWithFrontmatter("---", "\t---"));
}
