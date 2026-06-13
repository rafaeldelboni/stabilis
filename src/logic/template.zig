const std = @import("std");

const models = @import("../models.zig");
const PageKind = models.PageKind;
const SliceBetween = models.SliceBetween;

const Tag = struct {
    kind: Kind,
    name: []const u8,
    close_pos: usize,

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
pub fn parseTag(result: SliceBetween) Tag {
    const tag_content = std.mem.trim(u8, result.content, " \n\t\r");
    const close_pos = result.close_index + 2;

    if (std.mem.cutPrefix(u8, tag_content, "{")) |expr| {
        const name = std.mem.trim(u8, std.mem.trimEnd(u8, expr, "}"), " ");
        return Tag{ .kind = .raw, .name = name, .close_pos = close_pos + 1 };
    } else if (std.mem.cutPrefix(u8, tag_content, "#")) |name_raw| {
        const name = std.mem.trim(u8, name_raw, " ");
        return Tag{ .kind = .section_open, .name = name, .close_pos = close_pos };
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

/// Given `kind` return the template name string
pub fn templateFor(kind: PageKind) []const u8 {
    return switch (kind) {
        .home => "home.html",
        .post => "post.html",
        .page => "page.html",
        .post_list => "posts-list.html",
    };
}

test "templateFor: home" {
    try std.testing.expectEqualStrings("home.html", templateFor(.home));
}

test "templateFor: post" {
    try std.testing.expectEqualStrings("post.html", templateFor(.post));
}

test "templateFor: page" {
    try std.testing.expectEqualStrings("page.html", templateFor(.page));
}

test "templateFor: post_list" {
    try std.testing.expectEqualStrings("posts-list.html", templateFor(.post_list));
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
