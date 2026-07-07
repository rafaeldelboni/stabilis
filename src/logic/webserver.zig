const std = @import("std");

/// Strips the query string and fragment from a URL, returning only the path portion.
pub fn stripUrlQueryAndFragment(url: []const u8) []const u8 {
    const qt = std.mem.findScalar(u8, url, '?') orelse url.len;
    const hs = std.mem.findScalar(u8, url, '#') orelse url.len;
    return url[0..@min(qt, hs)];
}

test "stripUrlQueryAndFragment strips query and fragment" {
    try std.testing.expectEqualStrings("/path", stripUrlQueryAndFragment("/path?query=1#frag"));
    try std.testing.expectEqualStrings("/path", stripUrlQueryAndFragment("/path#frag"));
    try std.testing.expectEqualStrings("/path", stripUrlQueryAndFragment("/path?query=1"));
    try std.testing.expectEqualStrings("/path", stripUrlQueryAndFragment("/path"));
}
