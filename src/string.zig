const std = @import("std");

pub fn sliceBetween(source: []const u8, open: []const u8, close: []const u8, start_index: usize) ?struct {
    content: []const u8,
    open_index: usize,
    close_index: usize,
} {
    const open_index = std.mem.findPos(u8, source, start_index, open) orelse return null;
    const content_start_index = open_index + open.len;
    const close_index = std.mem.findPos(u8, source, content_start_index, close) orelse return null;
    return .{
        .content = source[content_start_index..close_index],
        .open_index = open_index,
        .close_index = close_index,
    };
}

test "sliceBetween returns content between delimiters" {
    const r1 = sliceBetween("---hello---", "---", "---", 0).?;
    try std.testing.expectEqualSlices(u8, "hello", r1.content);
    try std.testing.expectEqual(@as(usize, 0), r1.open_index);
    try std.testing.expectEqual(@as(usize, 8), r1.close_index);

    const r2 = sliceBetween("{{hello}}", "{{", "}}", 0).?;
    try std.testing.expectEqualSlices(u8, "hello", r2.content);
    try std.testing.expectEqual(@as(usize, 0), r2.open_index);
    try std.testing.expectEqual(@as(usize, 7), r2.close_index);

    const r3 = sliceBetween("<< mid >>", "<<", ">>", 0).?;
    try std.testing.expectEqualSlices(u8, " mid ", r3.content);
    try std.testing.expectEqual(@as(usize, 0), r3.open_index);
    try std.testing.expectEqual(@as(usize, 7), r3.close_index);

    const r4 = sliceBetween("----", "--", "--", 0).?;
    try std.testing.expectEqualSlices(u8, "", r4.content);
    try std.testing.expectEqual(@as(usize, 0), r4.open_index);
    try std.testing.expectEqual(@as(usize, 2), r4.close_index);

    const r5 = sliceBetween("---\ntitle: Hello\n---\nbody", "---\n", "\n---", 0).?;
    try std.testing.expectEqualSlices(u8, "title: Hello", r5.content);
    try std.testing.expectEqual(@as(usize, 0), r5.open_index);
    try std.testing.expectEqual(@as(usize, 16), r5.close_index);
}

test "sliceBetween returns null when delimiters not found" {
    try std.testing.expect(sliceBetween("no delimiters here", "---", "---", 0) == null);
    try std.testing.expect(sliceBetween("---no close", "---", "---", 0) == null);
    try std.testing.expect(sliceBetween("no open---", "---", "---", 0) == null);
    try std.testing.expect(sliceBetween("", "---", "---", 0) == null);
    try std.testing.expect(sliceBetween("---", "---", "---", 0) == null);
    try std.testing.expectEqualSlices(u8, "", sliceBetween("----", "--", "--", 0).?.content);
    try std.testing.expect(sliceBetween("]][", "[", "]", 0) == null);
    try std.testing.expectEqualSlices(u8, "", sliceBetween("##", "#", "#", 0).?.content);
}

test "sliceBetween returns content between first open and first close after it" {
    try std.testing.expectEqualSlices(u8, "a", sliceBetween("---a---b---", "---", "---", 0).?.content);
    try std.testing.expectEqualSlices(u8, "x", sliceBetween("---x---y---", "---", "---", 0).?.content);
}

test "sliceBetween with delimiters at string boundaries" {
    try std.testing.expectEqualSlices(u8, "content", sliceBetween("[content]", "[", "]", 0).?.content);
    try std.testing.expectEqualSlices(u8, "mid", sliceBetween("pre[mid]post", "[", "]", 0).?.content);
}

test "sliceBetween with empty content between delimiters" {
    try std.testing.expectEqualSlices(u8, "", sliceBetween("<>", "<", ">", 0).?.content);
    try std.testing.expectEqualSlices(u8, "", sliceBetween("[][]", "[", "]", 0).?.content);
}

test "sliceBetween with close-like text inside content" {
    try std.testing.expectEqualSlices(u8, "a--b", sliceBetween("---a--b---", "---", "---", 0).?.content);
    try std.testing.expectEqualSlices(u8, "a}b", sliceBetween("{{a}b}}", "{{", "}}", 0).?.content);
}

test "sliceBetween with single-byte delimiters" {
    try std.testing.expectEqualSlices(u8, "x", sliceBetween("axb", "a", "b", 0).?.content);
    try std.testing.expectEqualSlices(u8, "", sliceBetween("ab", "a", "b", 0).?.content);
}

test "sliceBetween with unicode content between delimiters" {
    try std.testing.expectEqualSlices(u8, "café", sliceBetween("[café]", "[", "]", 0).?.content);
    try std.testing.expectEqualSlices(u8, "日本語", sliceBetween("<<日本語>>", "<<", ">>", 0).?.content);
    try std.testing.expectEqualSlices(u8, "émoji 🎉", sliceBetween("---émoji 🎉---", "---", "---", 0).?.content);
}
