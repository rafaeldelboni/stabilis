const std = @import("std");

const models = @import("../models.zig");
const ContentEntry = models.ContentEntry;
const Frontmatter = models.Frontmatter;
const MapEntry = models.MapEntry;
const YamlNode = models.YamlNode;
const str = @import("../string.zig");
const yaml_lexer = @import("yaml_lexer.zig");

fn startsWithFrontmatter(delimiter: []const u8, source: []const u8) bool {
    if (source.len < delimiter.len) return false;
    return std.mem.startsWith(u8, source, delimiter);
}

fn asString(arena: *std.heap.ArenaAllocator, value: YamlNode) !?[]const u8 {
    return switch (value) {
        .string => |s| s,
        .boolean => |b| if (b) "true" else "false",
        .datetime => |d| blk: {
            const buf = try arena.allocator().alloc(u8, 20);
            break :blk try std.fmt.bufPrint(buf, "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
                d.year, d.month, d.day, d.hour, d.min, d.sec,
            });
        },
        .null => null,
        else => null,
    };
}


fn listToStrings(arena: *std.heap.ArenaAllocator, list: []const YamlNode) ![]const []const u8 {
    const allocator = arena.allocator();
    var strings: std.ArrayList([]const u8) = .empty;
    for (list) |entry| {
        if (try asString(arena, entry)) |s| {
            try strings.append(allocator, s);
        }
    }
    return strings.items;
}

fn mapToFrontmatter(arena: *std.heap.ArenaAllocator, entries: []const MapEntry) !Frontmatter {
    var fm = Frontmatter{};
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.key, "author")) fm.author = (try asString(arena, entry.value)) orelse fm.author;
        if (std.mem.eql(u8, entry.key, "title")) fm.title = (try asString(arena, entry.value)) orelse fm.title;
        if (std.mem.eql(u8, entry.key, "date")) fm.date = (try asString(arena, entry.value)) orelse fm.date;
        if (std.mem.eql(u8, entry.key, "slug")) fm.slug = (try asString(arena, entry.value)) orelse fm.slug;
        if (std.mem.eql(u8, entry.key, "description")) fm.description = (try asString(arena, entry.value)) orelse fm.description;
        if (std.mem.eql(u8, entry.key, "cover")) fm.cover = (try asString(arena, entry.value)) orelse fm.cover;
        if (std.mem.eql(u8, entry.key, "draft")) {
            if (entry.value == .boolean) fm.draft = entry.value.boolean;
        }
        if (std.mem.eql(u8, entry.key, "tags")) {
            if (entry.value == .list) fm.tags = try listToStrings(arena, entry.value.list);
        }
        if (std.mem.eql(u8, entry.key, "menus")) {
            if (entry.value == .list) fm.menus = try listToStrings(arena, entry.value.list);
        }
    }
    return fm;
}

/// Parses a markdown source into a ContentEntry by splitting the YAML
/// frontmatter block (delimited by `---`) from the markdown body and
/// converting the frontmatter into a typed Frontmatter struct via
/// yaml_lexer.parse and mapToFrontmatter.
///
/// Returns a ContentEntry with an empty Frontmatter when no valid
/// frontmatter block is found. All allocations live in the caller's arena.
pub fn parse(arena: *std.heap.ArenaAllocator, source: []const u8) !ContentEntry {
    const delimiter = "---";
    const open_delimiter = delimiter ++ "\n";
    const close_delimiter = "\n" ++ delimiter;
    if (!startsWithFrontmatter(delimiter, source))
        return .{ .frontmatter = .{}, .source = source };
    if (str.sliceBetween(source, open_delimiter, close_delimiter, 0)) |frontmatter| {
        const body_start = frontmatter.close_index + close_delimiter.len;
        const body = if (body_start < source.len and source[body_start] == '\n')
            source[body_start + 1 ..]
        else
            source[body_start..];
        const frontmatter_map = try yaml_lexer.parse(arena, frontmatter.content);
        return .{
            .frontmatter = try mapToFrontmatter(arena, frontmatter_map),
            .source = body,
        };
    } else return .{ .frontmatter = .{}, .source = source };
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

test "parse frontmatter-shaped content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source =
        \\---
        \\title: My Post
        \\date: 2026-05-18
        \\draft: false
        \\tags: [zig, ssg]
        \\---
        \\# Hello
        \\Body text here.
    ;
    const result = try parse(&arena, source);
    try std.testing.expectEqualStrings("My Post", result.frontmatter.title.?);
    try std.testing.expectEqualStrings("2026-05-18", result.frontmatter.date.?);
    try std.testing.expectEqual(false, result.frontmatter.draft);
    try std.testing.expectEqual(@as(usize, 2), result.frontmatter.tags.len);
    try std.testing.expectEqualStrings("zig", result.frontmatter.tags[0]);
    try std.testing.expectEqualStrings("ssg", result.frontmatter.tags[1]);
    try std.testing.expectEqualSlices(u8,
        \\# Hello
        \\Body text here.
    , result.source);
}

test "parse returns empty frontmatter when no frontmatter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "# Just a page\nNo frontmatter here.";
    const result = try parse(&arena, source);
    try std.testing.expect(result.frontmatter.title == null);
    try std.testing.expectEqualSlices(u8, source, result.source);
}

test "parse returns empty frontmatter when no closing delimiter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source =
        \\---
        \\title: Orphan
    ;
    const result = try parse(&arena, source);
    try std.testing.expect(result.frontmatter.title == null);
    try std.testing.expectEqualSlices(u8, source, result.source);
}

test "parse handles empty frontmatter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source =
        \\---
        \\
        \\---
        \\# Hello
    ;
    const result = try parse(&arena, source);
    try std.testing.expectEqualSlices(u8, "# Hello", result.source);
}

test "parse handles frontmatter with no body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source =
        \\---
        \\title: Solo
        \\---
    ;
    const result = try parse(&arena, source);
    try std.testing.expectEqualStrings("Solo", result.frontmatter.title.?);
    try std.testing.expectEqualSlices(u8, "", result.source);
}

test "parse does not confuse --- in body as frontmatter close" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source =
        \\---
        \\title: Post with HR
        \\---
        \\Some text
        \\---
        \\More text
    ;
    const result = try parse(&arena, source);
    try std.testing.expectEqualStrings("Post with HR", result.frontmatter.title.?);
    try std.testing.expectEqualSlices(u8,
        \\Some text
        \\---
        \\More text
    , result.source);
}

test "listToStrings: converts YamlNode list to string slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const nodes = [_]YamlNode{
        .{ .string = "zig" },
        .{ .string = "blogging" },
        .{ .string = "ssg" },
    };
    const result = try listToStrings(&arena, &nodes);
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("zig", result[0]);
    try std.testing.expectEqualStrings("blogging", result[1]);
    try std.testing.expectEqualStrings("ssg", result[2]);
}

test "listToStrings: empty list returns empty slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try listToStrings(&arena, &.{});
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "mapToFrontmatter: maps known keys to Frontmatter fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const entries = [_]MapEntry{
        .{ .key = "title", .value = .{ .string = "Hello" } },
        .{ .key = "draft", .value = .{ .boolean = true } },
        .{ .key = "tags", .value = .{ .list = &.{
            .{ .string = "zig" },
            .{ .string = "ssg" },
        } } },
    };
    const fm = try mapToFrontmatter(&arena, &entries);
    try std.testing.expectEqualStrings("Hello", fm.title.?);
    try std.testing.expectEqual(true, fm.draft);
    try std.testing.expectEqual(@as(usize, 2), fm.tags.len);
    try std.testing.expectEqualStrings("zig", fm.tags[0]);
    try std.testing.expectEqualStrings("ssg", fm.tags[1]);
}

test "mapToFrontmatter: unknown keys are ignored" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const entries = [_]MapEntry{
        .{ .key = "custom_field", .value = .{ .string = "ignored" } },
        .{ .key = "title", .value = .{ .string = "Only This" } },
    };
    const fm = try mapToFrontmatter(&arena, &entries);
    try std.testing.expectEqualStrings("Only This", fm.title.?);
    try std.testing.expect(fm.date == null);
    try std.testing.expectEqual(false, fm.draft);
}

test "mapToFrontmatter: empty entries returns default Frontmatter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fm = try mapToFrontmatter(&arena, &.{});
    try std.testing.expect(fm.title == null);
    try std.testing.expectEqual(false, fm.draft);
    try std.testing.expectEqual(@as(usize, 0), fm.tags.len);
}

test "asString: string passes through" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try asString(&arena, .{ .string = "hello" });
    try std.testing.expectEqualStrings("hello", result.?);
}

test "asString: boolean true becomes string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectEqualStrings("true", (try asString(&arena, .{ .boolean = true })).?);
}

test "asString: boolean false becomes string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectEqualStrings("false", (try asString(&arena, .{ .boolean = false })).?);
}

test "asString: datetime formatted to RFC3339" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try asString(&arena, .{ .datetime = .{
        .year = 2026,
        .month = 5,
        .day = 18,
        .hour = 10,
        .min = 0,
        .sec = 0,
    } });
    try std.testing.expectEqualStrings("2026-05-18T10:00:00Z", result.?);
}

test "asString: null returns null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expect((try asString(&arena, .null)) == null);
}

test "asString: list and map return null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expect((try asString(&arena, .{ .list = &.{} })) == null);
    try std.testing.expect((try asString(&arena, .{ .map = &.{} })) == null);
}
