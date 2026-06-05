const std = @import("std");
const str = @import("../string.zig");
const models = @import("../models.zig");
const debug = @import("../debug.zig");
const MapEntry = models.MapEntry;
const YamlNode = models.YamlNode;
const DateTime = models.DateTime;

fn unquote(input: []const u8) []const u8 {
    return if (str.sliceBetween(input, "\"", "\"", 0)) |double_quoted|
        double_quoted.content
    else if (str.sliceBetween(input, "'", "'", 0)) |single_quoted|
        single_quoted.content
    else
        input;
}

fn parseBool(input: []const u8) ?bool {
    if (std.mem.eql(u8, input, "true")) return true;
    if (std.mem.eql(u8, input, "false")) return false;
    return null;
}

fn parseDate(input: []const u8) ?DateTime {
    if (!std.mem.containsAtLeast(u8, input, 2, "-")) return null;
    if (!std.mem.containsAtLeast(u8, input, 1, "T")) return null;
    if (!std.mem.containsAtLeast(u8, input, 2, ":")) return null;

    var date_and_time = std.mem.splitScalar(u8, input, 'T');
    var date = std.mem.splitScalar(u8, date_and_time.first(), '-');
    const year = date.first();
    const month = date.next() orelse "1";
    const day = date.next() orelse "1";

    var time = std.mem.splitScalar(u8, date_and_time.next() orelse "", ':');
    const hour = time.first();
    const minute = time.next() orelse "00";
    const second = std.mem.trimEnd(u8, time.next() orelse "00", "Z");

    return .{
        .year = std.fmt.parseInt(i16, year, 10) catch return null,
        .month = std.fmt.parseInt(u4, month, 10) catch return null,
        .day = std.fmt.parseInt(u5, day, 10) catch return null,
        .hour = std.fmt.parseInt(u5, hour, 10) catch return null,
        .min = std.fmt.parseInt(u6, minute, 10) catch return null,
        .sec = std.fmt.parseInt(u6, second, 10) catch return null,
    };
}

/// Parses an inline YAML map like `{ key: value, ... }` into a slice of
/// MapEntry. Keys and values are trimmed. Values dispatch through
/// parseYamlNode so booleans, dates, and nested collections are detected.
///
/// The explicit `error{OutOfMemory}` breaks an inferred-error-set cycle
/// with parseYamlNode — the two functions are mutually recursive.
fn parseInlineMap(arena: *std.heap.ArenaAllocator, input: []const u8) error{OutOfMemory}!?[]const MapEntry {
    const open_delimiter = "{";
    const close_delimiter = "}";

    if (!std.mem.startsWith(u8, input, open_delimiter)) return null;
    if (!std.mem.endsWith(u8, input, close_delimiter)) return null;

    const allocator = arena.allocator();
    const source = str.sliceBetween(input, open_delimiter, close_delimiter, 0) orelse return null;
    var list: std.ArrayList(MapEntry) = .empty;
    var items = std.mem.splitScalar(u8, source.content, ',');

    while (items.next()) |raw_item| {
        var key_value = std.mem.splitScalar(u8, raw_item, ':');
        const trim_key = std.mem.trim(u8, key_value.first(), " ");
        const trim_value = std.mem.trim(u8, key_value.next() orelse "", " ");

        try list.append(allocator, .{
            .key = trim_key,
            // .value = .{ .string = unquote(trim_value) },
            .value = try parseYamlNode(arena, trim_value),
        });
    }

    return list.items;
}

/// Parses an inline YAML list like `[a, b, c]` into a slice of YamlNode.
/// Each item is trimmed and attempted as parseInlineMap first (for lists
/// of inline maps), falling back to a plain string.
///
/// The explicit `error{OutOfMemory}` is required because parseInlineList
/// is called from parseYamlNode, which participates in the mutual-recursion
/// cycle with parseInlineMap.
fn parseInlineList(arena: *std.heap.ArenaAllocator, input: []const u8) error{OutOfMemory}!?[]const YamlNode {
    const open_delimiter = "[";
    const close_delimiter = "]";

    if (!std.mem.startsWith(u8, input, open_delimiter)) return null;
    if (!std.mem.endsWith(u8, input, close_delimiter)) return null;

    const allocator = arena.allocator();
    const source = str.sliceBetween(input, open_delimiter, close_delimiter, 0) orelse return null;
    var list: std.ArrayList(YamlNode) = .empty;
    var lines = std.mem.splitScalar(u8, source.content, ',');
    while (lines.next()) |raw_line| {
        const trim_line = std.mem.trim(u8, raw_line, " ");
        if (try parseInlineMap(arena, trim_line)) |line_map| {
            try list.append(allocator, .{ .map = line_map });
        } else {
            try list.append(allocator, .{ .string = trim_line });
        }
    }

    return list.items;
}

/// Dispatches a single trimmed YAML scalar to the appropriate parser:
/// parseBool → parseDate → parseInlineMap → parseInlineList → unquote.
/// Quotes are stripped only at the string fallback (YAML semantics:
/// quoted values are always strings, regardless of content).
///
/// The explicit `error{OutOfMemory}` breaks an inferred-error-set cycle
/// with parseInlineMap — the two functions are mutually recursive.
fn parseYamlNode(arena: *std.heap.ArenaAllocator, input: []const u8) error{OutOfMemory}!YamlNode {
    const trimmed = std.mem.trim(u8, input, " ");
    if (parseBool(trimmed)) |result| return .{ .boolean = result };
    if (parseDate(trimmed)) |result| return .{ .datetime = result };
    if (try parseInlineMap(arena, trimmed)) |result| return .{ .map = result };
    if (try parseInlineList(arena, trimmed)) |result| return .{ .list = result };
    return .{ .string = unquote(trimmed) };
}

/// Parses a YAML subset into a slice of MapEntry. Handles the constructs
/// needed for site config and frontmatter: flat key-value pairs, inline
/// flow maps (`{ key: val }`), inline flow lists (`[a, b]`), block lists
/// (`key:\n  - item`), and nested block maps (`key:\n  subkey: val`).
/// Nesting is resolved via recursive calls that strip one indentation
/// level per recursion.
///
/// The caller provides an arena for all allocations; all returned slices
/// live in the arena and are freed when the arena is deinitialized.
pub fn parse(arena: *std.heap.ArenaAllocator, source: []const u8) error{OutOfMemory}![]const MapEntry {
    const indentation = "  ";
    const block_list_indicator = "- ";
    const allocator = arena.allocator();
    var map: std.ArrayList(MapEntry) = .empty;

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        const colon_pos = std.mem.indexOfScalar(u8, line, ':') orelse continue;

        const key = line[0..colon_pos];
        const raw_value = std.mem.trim(u8, line[colon_pos + 1 ..], " ");

        if (raw_value.len != 0) {
            try map.append(allocator, .{ .key = key, .value = try parseYamlNode(arena, raw_value) });
        } else {
            var nested_buf: std.ArrayList(u8) = .empty;
            var list: std.ArrayList(YamlNode) = .empty;
            while (lines.peek()) |peeked| {
                const stripped = std.mem.trimEnd(u8, peeked, "\r");
                if (std.mem.cutPrefix(u8, stripped, indentation)) |item| {
                    if (std.mem.cutPrefix(u8, item, block_list_indicator)) |list_item| {
                        try list.append(allocator, try parseYamlNode(arena, list_item));
                        _ = lines.next();
                    } else {
                        if (nested_buf.items.len > 0) try nested_buf.append(allocator, '\n');
                        try nested_buf.appendSlice(allocator, item);
                        _ = lines.next();
                    }
                } else {
                    break;
                }
            }
            if (list.items.len > 0) try map.append(allocator, .{ .key = key, .value = .{ .list = list.items } });
            if (nested_buf.items.len > 0) try map.append(allocator, .{ .key = key, .value = .{ .map = try parse(arena, nested_buf.items) } });
        }
    }
    return map.items;
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

    // std.debug.print("Frontmatter: {s}\n", .{try debug.dumpJson(arena.allocator(), entries)});
    try std.testing.expectEqual(@as(usize, 9), entries.len);

    // title: "Hello World" (quoted string)
    try std.testing.expectEqualStrings("title", entries[0].key);
    try std.testing.expect(entries[0].value == .string);
    try std.testing.expectEqualStrings("Hello World", entries[0].value.string);

    // date: 2026-05-18T10:00:00Z (datetime)
    try std.testing.expectEqualStrings("date", entries[1].key);
    try std.testing.expect(entries[1].value == .datetime);
    try std.testing.expectEqual(@as(i16, 2026), entries[1].value.datetime.year);
    try std.testing.expectEqual(@as(u4, 5), entries[1].value.datetime.month);
    try std.testing.expectEqual(@as(u5, 18), entries[1].value.datetime.day);
    try std.testing.expectEqual(@as(u5, 10), entries[1].value.datetime.hour);
    try std.testing.expectEqual(@as(u6, 0), entries[1].value.datetime.min);
    try std.testing.expectEqual(@as(u6, 0), entries[1].value.datetime.sec);

    // slug: hello-world (unquoted string)
    try std.testing.expectEqualStrings("slug", entries[2].key);
    try std.testing.expectEqualStrings("hello-world", entries[2].value.string);

    // description: A post about Zig and blogging (unquoted multi-word)
    try std.testing.expectEqualStrings("description", entries[3].key);
    try std.testing.expectEqualStrings("A post about Zig and blogging", entries[3].value.string);

    // draft: false (boolean)
    try std.testing.expectEqualStrings("draft", entries[4].key);
    try std.testing.expect(entries[4].value == .boolean);
    try std.testing.expectEqual(false, entries[4].value.boolean);

    // cover: 03.jpg (unquoted string)
    try std.testing.expectEqualStrings("cover", entries[5].key);
    try std.testing.expectEqualStrings("03.jpg", entries[5].value.string);

    // tags: [zig, blogging, ssg] (block list of strings)
    try std.testing.expectEqualStrings("tags", entries[6].key);
    try std.testing.expect(entries[6].value == .list);
    try std.testing.expectEqual(@as(usize, 3), entries[6].value.list.len);
    try std.testing.expectEqualStrings("zig", entries[6].value.list[0].string);
    try std.testing.expectEqualStrings("blogging", entries[6].value.list[1].string);
    try std.testing.expectEqualStrings("ssg", entries[6].value.list[2].string);

    // menus: [main] (inline flow list with one item)
    try std.testing.expectEqualStrings("menus", entries[7].key);
    try std.testing.expect(entries[7].value == .list);
    try std.testing.expectEqual(@as(usize, 2), entries[7].value.list.len);
    try std.testing.expectEqualStrings("main", entries[7].value.list[0].string);
    try std.testing.expectEqualStrings("about", entries[7].value.list[1].string);

    // images: block list of inline flow maps
    try std.testing.expectEqualStrings("images", entries[8].key);
    try std.testing.expect(entries[8].value == .list);
    try std.testing.expectEqual(@as(usize, 3), entries[8].value.list.len);

    // images[0]: { file: 01.jpg, caption: "Arriving at dusk" }
    try std.testing.expect(entries[8].value.list[0] == .map);
    try std.testing.expectEqual(@as(usize, 2), entries[8].value.list[0].map.len);
    try std.testing.expectEqualStrings("file", entries[8].value.list[0].map[0].key);
    try std.testing.expectEqualStrings("01.jpg", entries[8].value.list[0].map[0].value.string);
    try std.testing.expectEqualStrings("caption", entries[8].value.list[0].map[1].key);
    try std.testing.expectEqualStrings("Arriving at dusk", entries[8].value.list[0].map[1].value.string);

    // images[1]: { file: 02.jpg, caption: } (null caption)
    try std.testing.expect(entries[8].value.list[1] == .map);
    try std.testing.expectEqualStrings("file", entries[8].value.list[1].map[0].key);
    try std.testing.expectEqualStrings("02.jpg", entries[8].value.list[1].map[0].value.string);
    try std.testing.expectEqualStrings("caption", entries[8].value.list[1].map[1].key);
    try std.testing.expectEqualStrings("", entries[8].value.list[1].map[1].value.string);

    // images[2]: { file: 03.jpg, caption: The cabin }
    try std.testing.expect(entries[8].value.list[2] == .map);
    try std.testing.expectEqualStrings("file", entries[8].value.list[2].map[0].key);
    try std.testing.expectEqualStrings("03.jpg", entries[8].value.list[2].map[0].value.string);
    try std.testing.expectEqualStrings("caption", entries[8].value.list[2].map[1].key);
    try std.testing.expectEqualStrings("The cabin", entries[8].value.list[2].map[1].value.string);
}

test "parse nested block map" {
    const source =
        \\menu:
        \\  main:
        \\    - { name: Home, url: / }
        \\    - { name: Posts, url: /posts/ }
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const entries = try parse(&arena, source);

    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqualStrings("menu", entries[0].key);
    try std.testing.expect(entries[0].value == .map);

    const menu_map = entries[0].value.map;
    try std.testing.expectEqual(@as(usize, 1), menu_map.len);
    try std.testing.expectEqualStrings("main", menu_map[0].key);
    try std.testing.expect(menu_map[0].value == .list);

    const main_list = menu_map[0].value.list;
    try std.testing.expectEqual(@as(usize, 2), main_list.len);

    try std.testing.expect(main_list[0] == .map);
    try std.testing.expectEqualStrings("Home", main_list[0].map[0].value.string);
    try std.testing.expectEqualStrings("/", main_list[0].map[1].value.string);

    try std.testing.expect(main_list[1] == .map);
    try std.testing.expectEqualStrings("Posts", main_list[1].map[0].value.string);
    try std.testing.expectEqualStrings("/posts/", main_list[1].map[1].value.string);
}

test "parseYamlNode: plain string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "hello");
    try std.testing.expect(result == .string);
    try std.testing.expectEqualStrings("hello", result.string);
}

test "parseYamlNode: double-quoted string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "\"Hello World\"");
    try std.testing.expect(result == .string);
    try std.testing.expectEqualStrings("Hello World", result.string);
}

test "parseYamlNode: single-quoted string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "'Hello World'");
    try std.testing.expect(result == .string);
    try std.testing.expectEqualStrings("Hello World", result.string);
}

test "parseYamlNode: trims whitespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "  hello  ");
    try std.testing.expect(result == .string);
    try std.testing.expectEqualStrings("hello", result.string);
}

test "parseYamlNode: boolean true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "true");
    try std.testing.expect(result == .boolean);
    try std.testing.expectEqual(true, result.boolean);
}

test "parseYamlNode: boolean false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "false");
    try std.testing.expect(result == .boolean);
    try std.testing.expectEqual(false, result.boolean);
}

test "parseYamlNode: quoted true stays string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "\"true\"");
    try std.testing.expect(result == .string);
    try std.testing.expectEqualStrings("true", result.string);
}

test "parseYamlNode: datetime from unquoted value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "2026-05-18T10:00:00Z");
    try std.testing.expect(result == .datetime);
    try std.testing.expectEqual(@as(i16, 2026), result.datetime.year);
    try std.testing.expectEqual(@as(u4, 5), result.datetime.month);
    try std.testing.expectEqual(@as(u5, 18), result.datetime.day);
}

test "parseYamlNode: quoted datetime becomes string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "\"2026-05-18T10:00:00Z\"");
    try std.testing.expect(result == .string);
    try std.testing.expectEqualStrings("2026-05-18T10:00:00Z", result.string);
}

test "parseYamlNode: inline list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "[a, b, c]");
    try std.testing.expect(result == .list);
    try std.testing.expectEqual(@as(usize, 3), result.list.len);
    try std.testing.expectEqualStrings("a", result.list[0].string);
    try std.testing.expectEqualStrings("b", result.list[1].string);
    try std.testing.expectEqualStrings("c", result.list[2].string);
}

test "parseYamlNode: inline map" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "{ file: 01.jpg, caption: hello }");
    try std.testing.expect(result == .map);
    try std.testing.expectEqual(@as(usize, 2), result.map.len);
}

test "parseYamlNode: quoted inline list stays string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseYamlNode(&arena, "\"[a, b]\"");
    try std.testing.expect(result == .string);
    try std.testing.expectEqualStrings("[a, b]", result.string);
}

test "parseBool: true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = try allocator.dupe(u8, "true");
    const result = parseBool(input);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(true, result.?);
}

test "parseBool: false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = try allocator.dupe(u8, "false");
    const result = parseBool(input);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(false, result.?);
}

test "parseBool: non-boolean returns null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expect(parseBool(try allocator.dupe(u8, "yes")) == null);
    try std.testing.expect(parseBool(try allocator.dupe(u8, "no")) == null);
    try std.testing.expect(parseBool(try allocator.dupe(u8, "")) == null);
    try std.testing.expect(parseBool(try allocator.dupe(u8, "TRUE")) == null);
    try std.testing.expect(parseBool(try allocator.dupe(u8, " true")) == null);
}

test "parseDate: valid RFC3339 datetime" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = try allocator.dupe(u8, "2026-05-18T10:00:00Z");
    const result = parseDate(input);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i16, 2026), result.?.year);
    try std.testing.expectEqual(@as(u4, 5), result.?.month);
    try std.testing.expectEqual(@as(u5, 18), result.?.day);
    try std.testing.expectEqual(@as(u5, 10), result.?.hour);
    try std.testing.expectEqual(@as(u6, 0), result.?.min);
    try std.testing.expectEqual(@as(u6, 0), result.?.sec);
}

test "parseDate: returns null for non-datetime input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expect(parseDate(try allocator.dupe(u8, "hello")) == null);
    try std.testing.expect(parseDate(try allocator.dupe(u8, "")) == null);
    try std.testing.expect(parseDate(try allocator.dupe(u8, "2026-05-18")) == null);
    try std.testing.expect(parseDate(try allocator.dupe(u8, "10:00:00")) == null);
    try std.testing.expect(parseDate(try allocator.dupe(u8, "2026/05/18T10:00:00Z")) == null);
}

test "parseInlineMap: simple inline map" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = try allocator.dupe(u8, "{ file: 01.jpg, caption: hello }");
    const result = try parseInlineMap(&arena, input);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 2), result.?.len);
    try std.testing.expectEqualStrings("file", result.?[0].key);
    try std.testing.expectEqualStrings("01.jpg", result.?[0].value.string);
    try std.testing.expectEqualStrings("caption", result.?[1].key);
    try std.testing.expectEqualStrings("hello", result.?[1].value.string);
}

test "parseInlineMap: returns null for non-map input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expect((try parseInlineMap(&arena, try allocator.dupe(u8, "not a map"))) == null);
    try std.testing.expect((try parseInlineMap(&arena, try allocator.dupe(u8, ""))) == null);
    try std.testing.expect((try parseInlineMap(&arena, try allocator.dupe(u8, "[list, not, map]"))) == null);
}

test "parseInlineList: simple string list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = try allocator.dupe(u8, "[zig, blogging, ssg]");
    const result = try parseInlineList(&arena, input);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 3), result.?.len);
    try std.testing.expectEqualStrings("zig", result.?[0].string);
    try std.testing.expectEqualStrings("blogging", result.?[1].string);
    try std.testing.expectEqualStrings("ssg", result.?[2].string);
}

test "parseInlineList: list with inline maps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = try allocator.dupe(u8, "[{ file: 01.jpg }, { file: 02.jpg }]");
    const result = try parseInlineList(&arena, input);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 2), result.?.len);
    try std.testing.expect(result.?[0] == .map);
    try std.testing.expect(result.?[1] == .map);
}

test "parseInlineList: returns null for non-list input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expect((try parseInlineList(&arena, try allocator.dupe(u8, "not a list"))) == null);
    try std.testing.expect((try parseInlineList(&arena, try allocator.dupe(u8, ""))) == null);
    try std.testing.expect((try parseInlineList(&arena, try allocator.dupe(u8, "{ key: value }"))) == null);
}

test "unquote: double-quoted string unquotes" {
    try std.testing.expectEqualStrings("hello", unquote("\"hello\""));
}

test "unquote: single-quoted string unquotes" {
    try std.testing.expectEqualStrings("hello", unquote("'hello'"));
}

test "unquote: unquoted string passes through" {
    try std.testing.expectEqualStrings("hello", unquote("hello"));
}

test "unquote: empty quotes returns empty" {
    try std.testing.expectEqualStrings("", unquote("\"\""));
    try std.testing.expectEqualStrings("", unquote("''"));
}

test "unquote: empty unquoted returns empty" {
    try std.testing.expectEqualStrings("", unquote(""));
}

test "unquote: only opening quote passes through" {
    try std.testing.expectEqualStrings("\"only-open", unquote("\"only-open"));
}

test "unquote: only closing quote passes through" {
    try std.testing.expectEqualStrings("only-close\"", unquote("only-close\""));
}
