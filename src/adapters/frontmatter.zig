const std = @import("std");

const logic = @import("../logic/frontmatter.zig");
const models = @import("../models.zig");
const ContentEntry = models.ContentEntry;
const ImageSpec = models.ImageSpec;
const Frontmatter = models.Frontmatter;
const MapEntries = models.MapEntries;
const YamlNode = models.YamlNode;
const str = @import("../string.zig");
const time = @import("../time.zig");
const yaml_lexer = @import("yaml_lexer.zig");

fn asString(arena: *std.heap.ArenaAllocator, value: ?YamlNode) !?[]const u8 {
    if (value) |v| {
        return switch (v) {
            .string => |s| s,
            .boolean => |b| if (b) "true" else "false",
            .datetime => |d| try time.toString(arena, d),
            .null => null,
            else => null,
        };
    } else return null;
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

fn listToImages(arena: *std.heap.ArenaAllocator, list: []const YamlNode) ![]const ImageSpec {
    const allocator = arena.allocator();
    var specs: std.ArrayList(ImageSpec) = .empty;
    for (list) |entry| {
        if (entry == .map) {
            try specs.append(allocator, .{
                .file = (try asString(arena, entry.map.map.get("file"))) orelse "",
                .caption = try asString(arena, entry.map.map.get("caption")),
            });
        }
    }
    return specs.items;
}

fn mapToFrontmatter(arena: *std.heap.ArenaAllocator, entries: MapEntries) !Frontmatter {
    var fm = Frontmatter{};
    fm.author = (try asString(arena, entries.map.get("author"))) orelse fm.author;
    fm.title = (try asString(arena, entries.map.get("title"))) orelse fm.title;
    fm.date = (try asString(arena, entries.map.get("date"))) orelse fm.date;
    fm.slug = (try asString(arena, entries.map.get("slug"))) orelse fm.slug;
    fm.description = (try asString(arena, entries.map.get("description"))) orelse fm.description;
    fm.cover = (try asString(arena, entries.map.get("cover"))) orelse fm.cover;
    if (entries.map.get("draft")) |draft| {
        if (draft == .boolean) fm.draft = draft.boolean;
    }
    if (entries.map.get("tags")) |tags| {
        if (tags == .list) fm.tags = try listToStrings(arena, tags.list);
    }
    if (entries.map.get("menus")) |menus| {
        if (menus == .list) fm.menus = try listToStrings(arena, menus.list);
    }
    if (entries.map.get("images")) |images| {
        if (images == .list) fm.images = try listToImages(arena, images.list);
    }
    return fm;
}

fn appendFmt(list: *std.ArrayList(u8), alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(alloc, fmt, args);
    try list.appendSlice(alloc, s);
}

/// Serializes a `Frontmatter` into a YAML string wrapped in `---` fences.
/// Optional fields are omitted when null/empty; `draft` is emitted only
/// when `true`. All allocations live in the caller's arena.
pub fn frontmatterToYamlString(arena: *std.heap.ArenaAllocator, fm: Frontmatter) ![]const u8 {
    const allocator = arena.allocator();
    var list: std.ArrayList(u8) = .empty;

    try list.appendSlice(allocator, "---\n");

    if (fm.author) |author|
        try appendFmt(&list, allocator, "author: {s}\n", .{author});
    if (fm.title) |title|
        try appendFmt(&list, allocator, "title: {s}\n", .{try str.escapeDoubleQuote(allocator, title)});
    if (fm.date) |date|
        try appendFmt(&list, allocator, "date: {s}\n", .{date});
    if (fm.slug) |slug|
        try appendFmt(&list, allocator, "slug: {s}\n", .{slug});
    if (fm.description) |description|
        try appendFmt(&list, allocator, "description: {s}\n", .{try str.escapeDoubleQuote(allocator, description)});
    if (fm.cover) |cover|
        try appendFmt(&list, allocator, "cover: {s}\n", .{cover});

    if (fm.draft) try appendFmt(&list, allocator, "draft: {}\n", .{fm.draft});

    if (fm.tags.len > 0) {
        const joined = try std.mem.join(allocator, ", ", fm.tags);
        try appendFmt(&list, allocator, "tags: [{s}]\n", .{joined});
    }

    if (fm.menus.len > 0) {
        const joined = try std.mem.join(allocator, ", ", fm.menus);
        try appendFmt(&list, allocator, "menus: [{s}]\n", .{joined});
    }

    if (fm.images.len > 0) {
        try list.appendSlice(allocator, "images:\n");
        for (fm.images) |image| {
            try appendFmt(&list, allocator, "  - {{ file: {s}, caption: \"{s}\" }}\n", .{ image.file, image.caption orelse "" });
        }
    }

    try list.appendSlice(allocator, "---\n");

    return list.items;
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
    if (!logic.startsWithFrontmatter(delimiter, source))
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

test "listToImages: converts YamlNode list to ImageSpec slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var img1: MapEntries = .{};
    try img1.map.put(arena.allocator(), "file", .{ .string = "a.jpg" });
    try img1.map.put(arena.allocator(), "caption", .{ .string = "First" });

    var img2: MapEntries = .{};
    try img2.map.put(arena.allocator(), "file", .{ .string = "b.jpg" });
    try img2.map.put(arena.allocator(), "caption", .{ .string = "Second" });

    const nodes = [_]YamlNode{
        .{ .map = img1 },
        .{ .map = img2 },
    };
    const result = try listToImages(&arena, &nodes);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("a.jpg", result[0].file);
    try std.testing.expectEqualStrings("First", result[0].caption.?);
    try std.testing.expectEqualStrings("b.jpg", result[1].file);
    try std.testing.expectEqualStrings("Second", result[1].caption.?);
}

test "listToImages: missing caption is null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var img: MapEntries = .{};
    try img.map.put(arena.allocator(), "file", .{ .string = "no-caption.jpg" });

    const nodes = [_]YamlNode{.{ .map = img }};
    const result = try listToImages(&arena, &nodes);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("no-caption.jpg", result[0].file);
    try std.testing.expect(result[0].caption == null);
}

test "listToImages: empty list returns empty slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try listToImages(&arena, &.{});
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "listToImages: skips non-map entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var img: MapEntries = .{};
    try img.map.put(arena.allocator(), "file", .{ .string = "valid.jpg" });

    const nodes = [_]YamlNode{
        .{ .string = "not-a-map" },
        .{ .map = img },
        .{ .string = "also-not-a-map" },
    };
    const result = try listToImages(&arena, &nodes);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("valid.jpg", result[0].file);
}

test "mapToFrontmatter: maps known keys to Frontmatter fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var img1: MapEntries = .{};
    try img1.map.put(arena.allocator(), "file", .{ .string = "a.jpg" });
    try img1.map.put(arena.allocator(), "caption", .{ .string = "First" });

    var img2: MapEntries = .{};
    try img2.map.put(arena.allocator(), "file", .{ .string = "b.jpg" });

    var entries: MapEntries = .{};
    try entries.map.put(arena.allocator(), "title", .{ .string = "Hello" });
    try entries.map.put(arena.allocator(), "draft", .{ .boolean = true });
    try entries.map.put(arena.allocator(), "tags", .{ .list = &.{
        .{ .string = "zig" },
        .{ .string = "ssg" },
    } });
    try entries.map.put(arena.allocator(), "images", .{ .list = &.{
        .{ .map = img1 },
        .{ .map = img2 },
    } });

    const fm = try mapToFrontmatter(&arena, entries);
    try std.testing.expectEqualStrings("Hello", fm.title.?);
    try std.testing.expectEqual(true, fm.draft);
    try std.testing.expectEqual(@as(usize, 2), fm.tags.len);
    try std.testing.expectEqualStrings("zig", fm.tags[0]);
    try std.testing.expectEqualStrings("ssg", fm.tags[1]);
    try std.testing.expectEqual(@as(usize, 2), fm.images.len);
    try std.testing.expectEqualStrings("a.jpg", fm.images[0].file);
    try std.testing.expectEqualStrings("First", fm.images[0].caption.?);
    try std.testing.expectEqualStrings("b.jpg", fm.images[1].file);
    try std.testing.expect(fm.images[1].caption == null);
}

test "mapToFrontmatter: unknown keys are ignored" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var entries: MapEntries = .{};
    try entries.map.put(arena.allocator(), "custom_field", .{ .string = "ignored" });
    try entries.map.put(arena.allocator(), "title", .{ .string = "Only This" });

    const fm = try mapToFrontmatter(&arena, entries);
    try std.testing.expectEqualStrings("Only This", fm.title.?);
    try std.testing.expect(fm.date == null);
    try std.testing.expectEqual(false, fm.draft);
}

test "mapToFrontmatter: empty entries returns default Frontmatter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const entries: MapEntries = .{};
    const fm = try mapToFrontmatter(&arena, entries);
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
    try std.testing.expect((try asString(&arena, .{ .map = .{} })) == null);
}

test "frontmatterToYamlString should parse frontmatter into yaml string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fm = models.Frontmatter{
        .title = "Hello World",
        .date = "2026-05-18T10:00:00Z",
        .slug = "hello-world",
        .description = "A post about Zig and blogging",
        .draft = true,
        .cover = "03.jpg",
        .tags = &.{ "zig", "blogging", "ssg" },
        .menus = &.{ "main", "about" },
        .images = &.{
            .{ .file = "01.jpg", .caption = "Arriving at dusk" },
            .{ .file = "02.jpg", .caption = null },
            .{ .file = "03.jpg", .caption = "The cabin" },
        },
    };

    const expected =
        \\---
        \\title: Hello World
        \\date: 2026-05-18T10:00:00Z
        \\slug: hello-world
        \\description: A post about Zig and blogging
        \\cover: 03.jpg
        \\draft: true
        \\tags: [zig, blogging, ssg]
        \\menus: [main, about]
        \\images:
        \\  - { file: 01.jpg, caption: "Arriving at dusk" }
        \\  - { file: 02.jpg, caption: "" }
        \\  - { file: 03.jpg, caption: "The cabin" }
        \\---
        \\
    ;
    try std.testing.expectEqualStrings(expected, try frontmatterToYamlString(&arena, fm));
}

test "frontmatterToYamlString omits null/empty fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fm = models.Frontmatter{
        .title = "Only Title",
        .draft = false,
    };

    const expected =
        \\---
        \\title: Only Title
        \\---
        \\
    ;
    try std.testing.expectEqualStrings(expected, try frontmatterToYamlString(&arena, fm));
}

test "frontmatterToYamlString escapes quotes in title and description" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fm = models.Frontmatter{
        .title = "Say \"hello\"",
        .description = "a \"quote\" and a backslash \\",
        .draft = true,
    };

    const expected =
        \\---
        \\title: Say \"hello\"
        \\description: a \"quote\" and a backslash \\
        \\draft: true
        \\---
        \\
    ;
    try std.testing.expectEqualStrings(expected, try frontmatterToYamlString(&arena, fm));
}

test "frontmatterToYamlString emits tags and menus as flow sequences" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fm = models.Frontmatter{
        .draft = false,
        .tags = &.{ "one", "two" },
        .menus = &.{ "nav", "footer" },
    };

    const expected =
        \\---
        \\tags: [one, two]
        \\menus: [nav, footer]
        \\---
        \\
    ;
    try std.testing.expectEqualStrings(expected, try frontmatterToYamlString(&arena, fm));
}

test "frontmatterToYamlString emits images with null caption as empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fm = models.Frontmatter{
        .draft = false,
        .images = &.{
            .{ .file = "pic.jpg", .caption = null },
        },
    };

    const expected =
        \\---
        \\images:
        \\  - { file: pic.jpg, caption: "" }
        \\---
        \\
    ;
    try std.testing.expectEqualStrings(expected, try frontmatterToYamlString(&arena, fm));
}

test "frontmatterToYamlString emits only fences for empty frontmatter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fm = models.Frontmatter{};

    const expected =
        \\---
        \\---
        \\
    ;
    try std.testing.expectEqualStrings(expected, try frontmatterToYamlString(&arena, fm));
}
