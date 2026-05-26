const std = @import("std");

pub const YamlNode = union(enum) {
    string: []const u8,
    boolean: bool,
    list: []const YamlNode,
    map: []const MapEntry,
    null,
};

pub const MapEntry = struct {
    key: []const u8,
    value: YamlNode,
};

// TODO
pub fn parse(arena: *std.heap.ArenaAllocator, source: []const u8) ![]const MapEntry {
    const allocator = arena.allocator();
    var list: std.ArrayList(MapEntry) = .empty;

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        const colon_pos = std.mem.indexOfScalar(u8, line, ':') orelse continue;

        const key = line[0..colon_pos];
        const raw_value = std.mem.trimEnd(u8, line[colon_pos + 1 ..], " ");

        if (raw_value.len != 0) {
            try list.append(allocator, .{ .key = key, .value = .{ .string = raw_value } });
        } else {
            while (lines.peek()) |peeked| {
                const stripped = std.mem.trimEnd(u8, peeked, "\r");
                if (std.mem.cutPrefix(u8, stripped, "  - ")) |item| {
                    _ = item;
                    _ = lines.next();
                } else {
                    break;
                }
            }
            try list.append(allocator, .{ .key = key, .value = .{ .string = "Hello World" } });
        }
    }
    // try list.append(allocator, .{ .key = "title", .value = .{ .string = "Hello World" } });
    // try list.append(allocator, .{ .key = "draft", .value = .{ .boolean = false } });
    return list.items;
}

test "parse yaml subset content" {
    const source =
        \\title: "Hello World"
        \\date: 2026-05-18T10:00:00Z
        \\slug: hello-world
        \\description: A post about Zig and blogging
        \\draft: false
        \\cover: 03.jpg
        \\tags:
        \\  - zig
        \\  - blogging
        \\  - ssg
        \\menus: [main, about]
        \\images:
        \\  - { file: 01.jpg, caption: "Arriving at dusk" }
        \\  - { file: 02.jpg, caption: }
        \\  - { file: 03.jpg, caption: The cabin }
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const entries = try parse(&arena, source);

    // TODO
    try std.testing.expectEqual(@as(usize, 9), entries.len);

    // title: "Hello World" (quoted string)
    try std.testing.expectEqualStrings("title", entries[0].key);
    // try std.testing.expect(entries[0].value == .string);
    // try std.testing.expectEqualStrings("Hello World", entries[0].value.string);

    // date: 2026-05-18T10:00:00Z (unquoted string)
    try std.testing.expectEqualStrings("date", entries[1].key);
    // try std.testing.expect(entries[1].value == .string);
    // try std.testing.expectEqualStrings("2026-05-18T10:00:00Z", entries[1].value.string);

    // slug: hello-world (unquoted string)
    try std.testing.expectEqualStrings("slug", entries[2].key);
    // try std.testing.expectEqualStrings("hello-world", entries[2].value.string);

    // description: A post about Zig and blogging (unquoted multi-word)
    try std.testing.expectEqualStrings("description", entries[3].key);
    // try std.testing.expectEqualStrings("A post about Zig and blogging", entries[3].value.string);

    // draft: false (boolean)
    try std.testing.expectEqualStrings("draft", entries[4].key);
    // try std.testing.expect(entries[4].value == .boolean);
    // try std.testing.expectEqual(false, entries[4].value.boolean);

    // cover: 03.jpg (unquoted string)
    try std.testing.expectEqualStrings("cover", entries[5].key);
    // try std.testing.expectEqualStrings("03.jpg", entries[5].value.string);

    // tags: [zig, blogging, ssg] (inline flow list)
    try std.testing.expectEqualStrings("tags", entries[6].key);
    // try std.testing.expect(entries[6].value == .list);
    // try std.testing.expectEqual(@as(usize, 3), entries[6].value.list.len);
    // try std.testing.expectEqualStrings("zig", entries[6].value.list[0].string);
    // try std.testing.expectEqualStrings("blogging", entries[6].value.list[1].string);
    // try std.testing.expectEqualStrings("ssg", entries[6].value.list[2].string);

    // menus: [main] (inline flow list with one item)
    try std.testing.expectEqualStrings("menus", entries[7].key);
    // try std.testing.expect(entries[7].value == .list);
    // try std.testing.expectEqual(@as(usize, 1), entries[7].value.list.len);
    // try std.testing.expectEqualStrings("main", entries[7].value.list[0].string);
    // try std.testing.expectEqualStrings("about", entries[7].value.list[1].string);

    // images: block list of inline flow maps
    try std.testing.expectEqualStrings("images", entries[8].key);
    // try std.testing.expect(entries[8].value == .list);
    // try std.testing.expectEqual(@as(usize, 3), entries[8].value.list.len);

    // // images[0]: { file: 01.jpg, caption: "Arriving at dusk" }
    // try std.testing.expect(entries[8].value.list[0] == .map);
    // try std.testing.expectEqual(@as(usize, 2), entries[8].value.list[0].map.len);
    // try std.testing.expectEqualStrings("file", entries[8].value.list[0].map[0].key);
    // try std.testing.expectEqualStrings("01.jpg", entries[8].value.list[0].map[0].value.string);
    // try std.testing.expectEqualStrings("caption", entries[8].value.list[0].map[1].key);
    // try std.testing.expectEqualStrings("Arriving at dusk", entries[8].value.list[0].map[1].value.string);
    //
    // // images[1]: { file: 02.jpg, caption: } (null caption)
    // try std.testing.expect(entries[8].value.list[1] == .map);
    // try std.testing.expectEqualStrings("file", entries[8].value.list[1].map[0].key);
    // try std.testing.expectEqualStrings("02.jpg", entries[8].value.list[1].map[0].value.string);
    // try std.testing.expectEqualStrings("caption", entries[8].value.list[1].map[1].key);
    // try std.testing.expect(entries[8].value.list[1].map[1].value == .null);
    //
    // // images[2]: { file: 03.jpg, caption: The cabin }
    // try std.testing.expect(entries[8].value.list[2] == .map);
    // try std.testing.expectEqualStrings("file", entries[8].value.list[2].map[0].key);
    // try std.testing.expectEqualStrings("03.jpg", entries[8].value.list[2].map[0].value.string);
    // try std.testing.expectEqualStrings("caption", entries[8].value.list[2].map[1].key);
    // try std.testing.expectEqualStrings("The cabin", entries[8].value.list[2].map[1].value.string);
}
