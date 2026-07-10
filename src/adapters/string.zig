const std = @import("std");

const models = @import("../models.zig");
const SliceBetween = models.SliceBetween;

/// Finds the first `open`...`close` pair in `source` from `start_index`.
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

/// Lowercases, strips non-ASCII, and slugifies `input` into a URL-safe slug.
pub fn parseSlug(arena: *std.heap.ArenaAllocator, input: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    var iter = (try std.unicode.Utf8View.init(input)).iterator();
    while (iter.nextCodepoint()) |cp| {
        if (escapeNonAsciiChar(cp)) |c| {
            try out.append(allocator, c);
            continue;
        }

        if (cp > std.math.maxInt(u7)) continue;

        const c: u8 = @intCast(cp);
        if (std.ascii.isWhitespace(c)) {
            if (out.items.len > 0 and out.items[out.items.len - 1] != '-')
                try out.append(allocator, '-');
        } else if (std.ascii.isAlphanumeric(c)) {
            try out.append(allocator, std.ascii.toLower(c));
        }
    }
    return out.items;
}

/// Replaces `&`, `<`, `>`, `"` with HTML entities.
pub fn escapeHtml(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (input) |c| {
        switch (c) {
            '&' => try buf.appendSlice(allocator, "&amp;"),
            '<' => try buf.appendSlice(allocator, "&lt;"),
            '>' => try buf.appendSlice(allocator, "&gt;"),
            '"' => try buf.appendSlice(allocator, "&quot;"),
            else => try buf.append(allocator, c),
        }
    }
    return buf.items;
}

/// Escapes `\` and `"` so a value can be safely embedded inside a double-quoted YAML scalar.
pub fn escapeDoubleQuote(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (input) |c| {
        if (c == '"' or c == '\\') try out.append(allocator, '\\');
        try out.append(allocator, c);
    }
    return out.items;
}

/// Prepends `base_path` to root-relative `href="/"` and `src="/"` URLs in rendered HTML.
pub fn prefixRootRelativeUrls(
    arena: *std.heap.ArenaAllocator,
    html: []const u8,
    base_path: []const u8,
) ![]const u8 {
    const allocator = arena.allocator();
    var output: std.ArrayList(u8) = .empty;
    var pos: usize = 0;
    while (pos < html.len) {
        const href_pos = std.mem.indexOfPos(u8, html, pos, "href=\"/");
        const src_pos = std.mem.indexOfPos(u8, html, pos, "src=\"/");
        const next = if (href_pos != null and src_pos != null)
            @min(href_pos.?, src_pos.?)
        else if (href_pos != null) href_pos.? else if (src_pos != null) src_pos.? else break;

        const prefix_len: usize = if (href_pos != null and href_pos.? == next) 6 else 5;
        const slash_pos = next + prefix_len;

        // skip protocol-relative URLs (//cdn.example.com)
        if (slash_pos + 1 < html.len and html[slash_pos + 1] == '/') {
            try output.appendSlice(allocator, html[pos .. slash_pos + 1]);
            pos = slash_pos + 1;
            continue;
        }

        try output.appendSlice(allocator, html[pos .. next + prefix_len]);
        try output.appendSlice(allocator, base_path);
        pos = slash_pos;
    }
    try output.appendSlice(allocator, html[pos..]);
    return output.items;
}

test "parseSlug creates valid slug from chaotic title string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const r1 = "RebuildCast #8 - Ferramentas [Windows, Mac, Linux]";
    try std.testing.expectEqualSlices(u8, "rebuildcast-8-ferramentas-windows-mac-linux", try parseSlug(&arena, r1));

    const r2 = "RebuildCast #15 - .NET para Devs não .NET";
    try std.testing.expectEqualSlices(u8, "rebuildcast-15-net-para-devs-nao-net", try parseSlug(&arena, r2));

    const r3 = "á B {} -a 1!~ã ";
    try std.testing.expectEqualSlices(u8, "a-b-a-1a-", try parseSlug(&arena, r3));
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

test "escapeHtml replaces ampersand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeHtml(arena.allocator(), "foo & bar");
    try std.testing.expectEqualStrings("foo &amp; bar", result);
}

test "escapeHtml replaces angle brackets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeHtml(arena.allocator(), "<div>hello</div>");
    try std.testing.expectEqualStrings("&lt;div&gt;hello&lt;/div&gt;", result);
}

test "escapeHtml replaces double quotes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeHtml(arena.allocator(), "say \"hello\"");
    try std.testing.expectEqualStrings("say &quot;hello&quot;", result);
}

test "escapeHtml leaves plain text unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeHtml(arena.allocator(), "just plain text");
    try std.testing.expectEqualStrings("just plain text", result);
}

test "escapeHtml handles empty string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeHtml(arena.allocator(), "");
    try std.testing.expectEqualStrings("", result);
}

test "escapeHtml mixes entities and plain text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeHtml(arena.allocator(), "<p>Tom & Jerry \"cartoon\"</p>");
    try std.testing.expectEqualStrings("&lt;p&gt;Tom &amp; Jerry &quot;cartoon&quot;&lt;/p&gt;", result);
}

test "escapeDoubleQuote leaves plain text unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeDoubleQuote(arena.allocator(), "just plain text");
    try std.testing.expectEqualStrings("just plain text", result);
}

test "escapeDoubleQuote escapes double quotes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeDoubleQuote(arena.allocator(), "say \"hello\" world");
    try std.testing.expectEqualStrings("say \\\"hello\\\" world", result);
}

test "escapeDoubleQuote escapes backslashes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeDoubleQuote(arena.allocator(), "C:\\Users\\foo");
    try std.testing.expectEqualStrings("C:\\\\Users\\\\foo", result);
}

test "escapeDoubleQuote escapes mixed backslashes and quotes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeDoubleQuote(arena.allocator(), "path=\"C:\\dir\\file\"");
    try std.testing.expectEqualStrings("path=\\\"C:\\\\dir\\\\file\\\"", result);
}

test "escapeDoubleQuote handles empty string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeDoubleQuote(arena.allocator(), "");
    try std.testing.expectEqualStrings("", result);
}

test "escapeDoubleQuote leaves other special chars unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try escapeDoubleQuote(arena.allocator(), "a:b#c{d}[e],f@g%h");
    try std.testing.expectEqualStrings("a:b#c{d}[e],f@g%h", result);
}

test "prefixRootRelativeUrls: empty base_path returns html unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const html = "<a href=\"/posts/\">link</a><img src=\"/img.jpg\">";
    const result = try prefixRootRelativeUrls(&arena, html, "");
    try std.testing.expectEqualStrings(html, result);
}

test "prefixRootRelativeUrls: prefixes href and src with base_path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const html = "<a href=\"/posts/\">link</a><img src=\"/img.jpg\">";
    const result = try prefixRootRelativeUrls(&arena, html, "/stabilis");
    try std.testing.expectEqualStrings("<a href=\"/stabilis/posts/\">link</a><img src=\"/stabilis/img.jpg\">", result);
}

test "prefixRootRelativeUrls: skips protocol-relative URLs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const html = "<a href=\"//cdn.example.com/foo\">link</a>";
    const result = try prefixRootRelativeUrls(&arena, html, "/stabilis");
    try std.testing.expectEqualStrings(html, result);
}

test "prefixRootRelativeUrls: skips absolute http(s) URLs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const html = "<a href=\"https://example.com/foo\">link</a>";
    const result = try prefixRootRelativeUrls(&arena, html, "/stabilis");
    try std.testing.expectEqualStrings(html, result);
}

test "prefixRootRelativeUrls: handles multiple href and src in any order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const html = "<img src=\"/a.jpg\"><a href=\"/b\">b</a><img src=\"/c.jpg\">";
    const result = try prefixRootRelativeUrls(&arena, html, "/stabilis");
    try std.testing.expectEqualStrings("<img src=\"/stabilis/a.jpg\"><a href=\"/stabilis/b\">b</a><img src=\"/stabilis/c.jpg\">", result);
}

test "prefixRootRelativeUrls: leaves relative URLs (no leading slash) unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const html = "<a href=\"posts/hello\">link</a>";
    const result = try prefixRootRelativeUrls(&arena, html, "/stabilis");
    try std.testing.expectEqualStrings(html, result);
}

test "prefixRootRelativeUrls: no href or src returns html unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const html = "<p>just text</p>";
    const result = try prefixRootRelativeUrls(&arena, html, "/stabilis");
    try std.testing.expectEqualStrings(html, result);
}
