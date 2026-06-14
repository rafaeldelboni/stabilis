const std = @import("std");

const models = @import("models.zig");
const SliceBetween = models.SliceBetween;

pub fn sliceBetween(
    source: []const u8,
    open: []const u8,
    close: []const u8,
    start_index: usize,
) ?SliceBetween {
    const open_index = std.mem.findPos(u8, source, start_index, open) orelse return null;
    const content_start_index = open_index + open.len;
    const close_index = std.mem.findPos(u8, source, content_start_index, close) orelse return null;
    return .{
        .content = source[content_start_index..close_index],
        .open_index = open_index,
        .close_index = close_index,
    };
}

fn escapeNonAsciiChar(input: u21) ?u8 {
    return switch (input) {
        'ą', 'à', 'á', 'ä', 'â', 'ã', 'å', 'æ', 'ă' => 'a',
        'ć', 'č', 'ĉ' => 'c',
        'ę', 'è', 'é', 'ë', 'ê' => 'e',
        'ĝ' => 'g',
        'ĥ' => 'h',
        'ì', 'í', 'ï', 'î' => 'i',
        'ĵ' => 'j',
        'ł', 'ľ' => 'l',
        'ń', 'ň', 'ñ' => 'n',
        'ò', 'ó', 'ö', 'ő', 'ô', 'õ', 'ð', 'ø' => 'o',
        'ś', 'ș', 'š', 'ŝ' => 's',
        'ť', 'ț' => 't',
        'ŭ', 'ù', 'ú', 'ü', 'ű', 'û' => 'u',
        'ÿ', 'ý' => 'y',
        'ç' => 'c',
        'ż', 'ź', 'ž' => 'z',
        else => null,
    };
}

pub fn parseSlug(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const lower = try allocator.dupe(u8, input);
    _ = std.ascii.lowerString(lower, lower);

    var out: std.ArrayList(u8) = .empty;
    var iter = (try std.unicode.Utf8View.init(lower)).iterator();
    while (iter.nextCodepoint()) |cp| {
        if (escapeNonAsciiChar(cp)) |c| {
            try out.append(allocator, c);
            continue;
        }

        if (cp > std.math.maxInt(u7)) continue;

        if (std.ascii.isWhitespace(@intCast(cp))) {
            if (out.items.len > 0 and out.items[out.items.len - 1] != '-')
                try out.append(allocator, '-');
        } else if (std.ascii.isAlphanumeric(@intCast(cp))) {
            try out.append(allocator, @intCast(cp));
        }
    }
    return out.items;
}

test "parseSlug creates valid slug from chaotic title string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const r1 = "RebuildCast #8 - Ferramentas [Windows, Mac, Linux]";
    try std.testing.expectEqualSlices(u8, "rebuildcast-8-ferramentas-windows-mac-linux", try parseSlug(arena.allocator(), r1));

    const r2 = "RebuildCast #15 - .NET para Devs não .NET";
    try std.testing.expectEqualSlices(u8, "rebuildcast-15-net-para-devs-nao-net", try parseSlug(arena.allocator(), r2));

    const r3 = "á B {} -a 1!~ã ";
    try std.testing.expectEqualSlices(u8, "a-b-a-1a-", try parseSlug(arena.allocator(), r3));
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
