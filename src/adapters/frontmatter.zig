const std = @import("std");
const model = @import("../models.zig");
const str = @import("../string.zig");

fn startsWithFrontmatter(delimiter: []const u8, source: []const u8) bool {
    if (source.len < delimiter.len) return false;
    return std.mem.startsWith(u8, source, delimiter);
}

pub fn split(source: []const u8) model.ContentEntry {
    const delimiter = "---";
    const open_delimiter = delimiter ++ "\n";
    const close_delimiter = "\n" ++ delimiter;
    if (!startsWithFrontmatter(delimiter, source))
        return .{ .frontmatter = "", .source = source };
    if (str.sliceBetween(source, open_delimiter, close_delimiter, 0)) |frontmatter| {
        const body_start = frontmatter.close_index + close_delimiter.len;
        const body = if (body_start < source.len and source[body_start] == '\n')
            source[body_start + 1 ..]
        else
            source[body_start..];
        return .{
            .frontmatter = frontmatter.content,
            .source = body,
        };
    } else return .{ .frontmatter = "", .source = source };
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

test "split frontmatter-shaped content" {
    const source =
        \\---
        \\title: My Post
        \\date: 2026-05-18
        \\tags: [zig, ssg]
        \\---
        \\# Hello
        \\Body text here.
    ;
    const result = split(source);
    try std.testing.expectEqualSlices(u8,
        \\title: My Post
        \\date: 2026-05-18
        \\tags: [zig, ssg]
    , result.frontmatter);
    try std.testing.expectEqualSlices(u8,
        \\# Hello
        \\Body text here.
    , result.source);
}

test "split returns full source as body when no frontmatter" {
    const source = "# Just a page\nNo frontmatter here.";
    const result = split(source);
    try std.testing.expectEqualSlices(u8, "", result.frontmatter);
    try std.testing.expectEqualSlices(u8, source, result.source);
}

test "split returns full source as body when no closing delimiter" {
    const source =
        \\---
        \\title: Orphan
    ;
    const result = split(source);
    try std.testing.expectEqualSlices(u8, "", result.frontmatter);
    try std.testing.expectEqualSlices(u8, source, result.source);
}

test "split handles empty frontmatter" {
    const source =
        \\---
        \\
        \\---
        \\# Hello
    ;
    const result = split(source);
    try std.testing.expectEqualSlices(u8, "", result.frontmatter);
    try std.testing.expectEqualSlices(u8, "# Hello", result.source);
}

test "split handles frontmatter with no body" {
    const source =
        \\---
        \\title: Solo
        \\---
    ;
    const result = split(source);
    try std.testing.expectEqualSlices(u8, "title: Solo", result.frontmatter);
    try std.testing.expectEqualSlices(u8, "", result.source);
}

test "split does not confuse --- in body as frontmatter close" {
    const source =
        \\---
        \\title: Post with HR
        \\---
        \\Some text
        \\---
        \\More text
    ;
    const result = split(source);
    try std.testing.expectEqualSlices(u8, "title: Post with HR", result.frontmatter);
    try std.testing.expectEqualSlices(u8,
        \\Some text
        \\---
        \\More text
    , result.source);
}
