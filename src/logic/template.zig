const std = @import("std");

const config = @import("config.zig");
const models = @import("../models.zig");
const Context = models.Context;
const PageKind = models.PageKind;
const SliceBetween = models.SliceBetween;

pub const SortDirection = enum { asc, desc };

pub const SectionModifiers = struct {
    sort_key: ?[]const u8 = null,
    sort_direction: SortDirection = .asc,
    top: ?usize = null,
};

const Tag = struct {
    kind: Kind,
    name: []const u8,
    close_pos: usize,
    modifiers: SectionModifiers = .{},

    const Kind = enum { raw, section_open, section_close, partial, variable };
};

/// Parses a `{{ }}` mustache-style tag into a structured Tag.
///
/// Tag kinds are determined by the leading character inside `{{ }}`:
///   - `{expr}` / `{{{ expr }}}` -> .raw
///   - `#name` -> .section_open
///   - `/name` -> .section_close
///   - `>name` -> .partial
///   - `name` (no prefix) -> .variable
///
/// Section open tags support optional modifiers after the name:
///   `{{# posts sort=date desc top=10 }}`
///   - `sort=<key> [asc|desc]` — sort items by context key (string compare)
///   - `top=<n>` — limit to first n items (applied after sort)
pub fn parseTag(result: SliceBetween) Tag {
    const tag_content = std.mem.trim(u8, result.content, " \n\t\r");
    const close_pos = result.close_index + 2;

    if (std.mem.cutPrefix(u8, tag_content, "{")) |expr| {
        const name = std.mem.trim(u8, std.mem.trimEnd(u8, expr, "}"), " ");
        return Tag{ .kind = .raw, .name = name, .close_pos = close_pos + 1 };
    } else if (std.mem.cutPrefix(u8, tag_content, "#")) |rest| {
        const name = parseSectionName(rest);
        const mods = parseSectionModifiers(rest[name.len..]);
        return Tag{ .kind = .section_open, .name = name, .close_pos = close_pos, .modifiers = mods };
    } else if (std.mem.cutPrefix(u8, tag_content, "/")) |name_raw| {
        const name = std.mem.trim(u8, name_raw, " ");
        return Tag{ .kind = .section_close, .name = name, .close_pos = close_pos };
    } else if (std.mem.cutPrefix(u8, tag_content, ">")) |name_raw| {
        const name = std.mem.trim(u8, name_raw, " ");
        return Tag{ .kind = .partial, .name = name, .close_pos = close_pos };
    } else {
        const name = std.mem.trim(u8, tag_content, " ");
        return Tag{ .kind = .variable, .name = name, .close_pos = close_pos };
    }
}

fn parseSectionName(rest: []const u8) []const u8 {
    const trimmed = std.mem.trimStart(u8, rest, " \n\t\r");
    var i: usize = 0;
    while (i < trimmed.len and !std.ascii.isWhitespace(trimmed[i])) i += 1;
    return trimmed[0..i];
}

fn parseSectionModifiers(rest: []const u8) SectionModifiers {
    var mods = SectionModifiers{};
    var it = std.mem.tokenizeScalar(u8, std.mem.trim(u8, rest, " \n\t\r"), ' ');
    while (it.next()) |token| {
        if (std.mem.cutPrefix(u8, token, "sort=")) |val| {
            mods.sort_key = val;
        } else if (std.mem.eql(u8, token, "asc")) {
            mods.sort_direction = .asc;
        } else if (std.mem.eql(u8, token, "desc")) {
            mods.sort_direction = .desc;
        } else if (std.mem.cutPrefix(u8, token, "top=")) |val| {
            mods.top = std.fmt.parseInt(usize, val, 10) catch null;
        }
    }
    return mods;
}

/// Sorts `list` in-place by the string value at `key`, in the given direction.
/// Items missing the key sink to the end regardless of direction.
pub fn sortContextList(
    list: []Context,
    key: []const u8,
    direction: SortDirection,
) void {
    const Ctx = struct { key: []const u8, direction: SortDirection };
    std.mem.sort(Context, list, Ctx{ .key = key, .direction = direction }, struct {
        fn lt(ctx: Ctx, a: Context, b: Context) bool {
            const va = a.map.get(ctx.key) orelse return false;
            const vb = b.map.get(ctx.key) orelse return true;
            const order = std.mem.order(u8, va.string, vb.string);
            return switch (ctx.direction) {
                .asc => order == .lt,
                .desc => order == .gt,
            };
        }
    }.lt);
}

/// Returns the first `n` elements of `list`, or the whole list if shorter.
pub fn topN(list: []const Context, n: usize) []const Context {
    return list[0..@min(n, list.len)];
}

/// Given `kind` return the template name string
pub fn templateFor(kind: PageKind) []const u8 {
    return config.templateNameFor(kind);
}

test "templateFor: each kind maps to its template filename" {
    try std.testing.expectEqualStrings("home.html", templateFor(.home));
    try std.testing.expectEqualStrings("post.html", templateFor(.post));
    try std.testing.expectEqualStrings("page.html", templateFor(.page));
    try std.testing.expectEqualStrings("post-list.html", templateFor(.post_list));
}

test "parseTag: variable" {
    const tag = parseTag(.{ .content = " name ", .open_index = 0, .close_index = 9 });
    try std.testing.expectEqual(Tag.Kind.variable, tag.kind);
    try std.testing.expectEqualSlices(u8, "name", tag.name);
    try std.testing.expectEqual(@as(usize, 11), tag.close_pos);
}

test "parseTag: raw" {
    const tag = parseTag(.{ .content = " {html} ", .open_index = 0, .close_index = 11 });
    try std.testing.expectEqual(Tag.Kind.raw, tag.kind);
    try std.testing.expectEqualSlices(u8, "html", tag.name);
    try std.testing.expectEqual(@as(usize, 14), tag.close_pos);
}

test "parseTag: section_open" {
    const tag = parseTag(.{ .content = " #posts ", .open_index = 0, .close_index = 10 });
    try std.testing.expectEqual(Tag.Kind.section_open, tag.kind);
    try std.testing.expectEqualSlices(u8, "posts", tag.name);
    try std.testing.expectEqual(@as(usize, 12), tag.close_pos);
}

test "parseTag: section_close" {
    const tag = parseTag(.{ .content = " /posts ", .open_index = 0, .close_index = 10 });
    try std.testing.expectEqual(Tag.Kind.section_close, tag.kind);
    try std.testing.expectEqualSlices(u8, "posts", tag.name);
    try std.testing.expectEqual(@as(usize, 12), tag.close_pos);
}

test "parseTag: partial" {
    const tag = parseTag(.{ .content = " >header ", .open_index = 0, .close_index = 11 });
    try std.testing.expectEqual(Tag.Kind.partial, tag.kind);
    try std.testing.expectEqualSlices(u8, "header", tag.name);
    try std.testing.expectEqual(@as(usize, 13), tag.close_pos);
}

test "parseTag: variable with empty name" {
    const tag = parseTag(.{ .content = "  ", .open_index = 0, .close_index = 4 });
    try std.testing.expectEqual(Tag.Kind.variable, tag.kind);
    try std.testing.expectEqualSlices(u8, "", tag.name);
}

test "parseTag: raw with extra braces" {
    const tag = parseTag(.{ .content = " { foo } ", .open_index = 0, .close_index = 11 });
    try std.testing.expectEqual(Tag.Kind.raw, tag.kind);
    try std.testing.expectEqualSlices(u8, "foo", tag.name);
}

test "parseTag: section_open with sort desc" {
    const tag = parseTag(.{ .content = " #posts sort=date desc ", .open_index = 0, .close_index = 24 });
    try std.testing.expectEqual(Tag.Kind.section_open, tag.kind);
    try std.testing.expectEqualSlices(u8, "posts", tag.name);
    try std.testing.expectEqualSlices(u8, "date", tag.modifiers.sort_key.?);
    try std.testing.expectEqual(SortDirection.desc, tag.modifiers.sort_direction);
}

test "parseTag: section_open with sort asc and top" {
    const tag = parseTag(.{ .content = " #posts sort=title asc top=5 ", .open_index = 0, .close_index = 30 });
    try std.testing.expectEqual(Tag.Kind.section_open, tag.kind);
    try std.testing.expectEqualSlices(u8, "posts", tag.name);
    try std.testing.expectEqualSlices(u8, "title", tag.modifiers.sort_key.?);
    try std.testing.expectEqual(SortDirection.asc, tag.modifiers.sort_direction);
    try std.testing.expectEqual(@as(usize, 5), tag.modifiers.top.?);
}

test "parseTag: section_open with top only" {
    const tag = parseTag(.{ .content = " #posts top=3 ", .open_index = 0, .close_index = 14 });
    try std.testing.expectEqual(Tag.Kind.section_open, tag.kind);
    try std.testing.expectEqualSlices(u8, "posts", tag.name);
    try std.testing.expect(tag.modifiers.sort_key == null);
    try std.testing.expectEqual(@as(usize, 3), tag.modifiers.top.?);
}

test "parseTag: section_open without modifiers has empty modifiers" {
    const tag = parseTag(.{ .content = " #posts ", .open_index = 0, .close_index = 10 });
    try std.testing.expectEqual(Tag.Kind.section_open, tag.kind);
    try std.testing.expect(tag.modifiers.sort_key == null);
    try std.testing.expect(tag.modifiers.top == null);
}

test "sortContextList: sorts asc by string key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var list = [_]Context{
        blk: {
            var ctx: Context = .{};
            ctx.map.put(a, "name", .{ .string = "charlie" }) catch unreachable;
            break :blk ctx;
        },
        blk: {
            var ctx: Context = .{};
            ctx.map.put(a, "name", .{ .string = "alice" }) catch unreachable;
            break :blk ctx;
        },
        blk: {
            var ctx: Context = .{};
            ctx.map.put(a, "name", .{ .string = "bob" }) catch unreachable;
            break :blk ctx;
        },
    };
    sortContextList(&list, "name", .asc);
    try std.testing.expectEqualSlices(u8, "alice", list[0].map.get("name").?.string);
    try std.testing.expectEqualSlices(u8, "bob", list[1].map.get("name").?.string);
    try std.testing.expectEqualSlices(u8, "charlie", list[2].map.get("name").?.string);
}

test "sortContextList: sorts desc by string key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var list = [_]Context{
        blk: {
            var ctx: Context = .{};
            ctx.map.put(a, "date", .{ .string = "2026-01-01" }) catch unreachable;
            break :blk ctx;
        },
        blk: {
            var ctx: Context = .{};
            ctx.map.put(a, "date", .{ .string = "2026-06-01" }) catch unreachable;
            break :blk ctx;
        },
        blk: {
            var ctx: Context = .{};
            ctx.map.put(a, "date", .{ .string = "2026-03-01" }) catch unreachable;
            break :blk ctx;
        },
    };
    sortContextList(&list, "date", .desc);
    try std.testing.expectEqualSlices(u8, "2026-06-01", list[0].map.get("date").?.string);
    try std.testing.expectEqualSlices(u8, "2026-03-01", list[1].map.get("date").?.string);
    try std.testing.expectEqualSlices(u8, "2026-01-01", list[2].map.get("date").?.string);
}

test "sortContextList: missing key sinks to end" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var list = [_]Context{
        blk: {
            var ctx: Context = .{};
            ctx.map.put(a, "date", .{ .string = "2026-03-01" }) catch unreachable;
            break :blk ctx;
        },
        blk: {
            const ctx: Context = .{};
            break :blk ctx;
        },
        blk: {
            var ctx: Context = .{};
            ctx.map.put(a, "date", .{ .string = "2026-01-01" }) catch unreachable;
            break :blk ctx;
        },
    };
    sortContextList(&list, "date", .asc);
    try std.testing.expectEqualSlices(u8, "2026-01-01", list[0].map.get("date").?.string);
    try std.testing.expectEqualSlices(u8, "2026-03-01", list[1].map.get("date").?.string);
    try std.testing.expect(list[2].map.get("date") == null);
}

test "topN: returns first n elements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var arr: [5]Context = undefined;
    for (&arr, 0..) |*ctx, i| {
        ctx.* = .{};
        _ = i;
        ctx.map.put(a, "name", .{ .string = "x" }) catch unreachable;
    }
    const slice = topN(&arr, 3);
    try std.testing.expectEqual(@as(usize, 3), slice.len);
}

test "topN: returns whole list when n exceeds length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var arr: [2]Context = undefined;
    for (&arr) |*ctx| {
        ctx.* = .{};
        ctx.map.put(a, "name", .{ .string = "x" }) catch unreachable;
    }
    const slice = topN(&arr, 10);
    try std.testing.expectEqual(@as(usize, 2), slice.len);
}
