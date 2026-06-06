const std = @import("std");

const str = @import("../string.zig");
const models = @import("../models.zig");

const CtxValue = models.CtxValue;

const RenderError = error{
    UnclosedSection,
    UnknownPartial,
    OutOfMemory,
    NoSpaceLeft,
};

const Tag = struct {
    kind: Kind,
    name: []const u8,
    close_pos: usize,

    const Kind = enum { raw, section_open, section_close, partial, variable };
};

/// Replaces `&`, `<`, `>`, `"` with HTML entities.
fn escapeHtml(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
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

/// Classifies a `{{ }}` tag into its kind (raw, section, partial, variable) and extracts the key name.
fn parseTag(result: str.SliceResult) Tag {
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

/// Finds the matching `{{/ name }}` closing tag, handling nested same-name sections via depth counting.
fn findSectionEnd(template: []const u8, name: []const u8, start: usize) !struct { inner: []const u8, end: usize } {
    var depth: usize = 1;
    var search_pos = start;
    var section_end = start;
    while (depth > 0) {
        const result = str.sliceBetween(template, "{{", "}}", search_pos) orelse {
            return error.UnclosedSection;
        };
        const tag = parseTag(result);
        if (std.mem.eql(u8, tag.name, name)) {
            switch (tag.kind) {
                .section_open => depth += 1,
                .section_close => {
                    depth -= 1;
                    section_end = result.open_index;
                },
                else => {},
            }
        }
        search_pos = tag.close_pos;
    }
    return .{ .inner = template[start..section_end], .end = search_pos };
}

/// Iterates over a list value, merging parent scope into each item, and renders the section body for each.
fn renderSection(
    arena: *std.heap.ArenaAllocator,
    inner: []const u8,
    templates: std.StringHashMap([]const u8),
    context: std.StringHashMap(CtxValue),
    value: CtxValue,
    output: *std.ArrayList(u8),
) !void {
    const allocator = arena.allocator();
    switch (value) {
        .list => |items| {
            for (items) |item| {
                var child_ctx = std.StringHashMap(CtxValue).init(allocator);
                var parent_it = context.iterator();
                while (parent_it.next()) |entry| {
                    try child_ctx.put(entry.key_ptr.*, entry.value_ptr.*);
                }
                var item_it = item.iterator();
                while (item_it.next()) |entry| {
                    try child_ctx.put(entry.key_ptr.*, entry.value_ptr.*);
                }
                const html = try render(arena, inner, templates, child_ctx);
                try output.appendSlice(allocator, html);
            }
        },
        else => {},
    }
}

/// Looks up a key in context and appends its HTML-escaped string value to output.
fn renderVariable(
    allocator: std.mem.Allocator,
    context: std.StringHashMap(CtxValue),
    name: []const u8,
    output: *std.ArrayList(u8),
) !void {
    if (context.get(name)) |value| {
        switch (value) {
            .string => |s| try output.appendSlice(allocator, try escapeHtml(allocator, s)),
            else => {},
        }
    }
}

/// Looks up a key in context and appends its raw string value to output (no escaping).
fn renderRaw(
    allocator: std.mem.Allocator,
    context: std.StringHashMap(CtxValue),
    name: []const u8,
    output: *std.ArrayList(u8),
) !void {
    if (context.get(name)) |value| {
        switch (value) {
            .string => |s| try output.appendSlice(allocator, s),
            else => {},
        }
    }
}

/// Renders a Mustache-like template with sections, partials, and variable interpolation.
/// `{{ key }}` — escaped output, `{{{ key }}}` — raw output, `{{# key }}...{{/ key }}` — section,
/// `{{> partial }}` — partial include. Sections inherit parent scope.
pub fn render(
    arena: *std.heap.ArenaAllocator,
    template: []const u8,
    templates: std.StringHashMap([]const u8),
    context: std.StringHashMap(CtxValue),
) RenderError![]const u8 {
    const allocator = arena.allocator();
    var output: std.ArrayList(u8) = .empty;

    var pos: usize = 0;
    while (pos < template.len) {
        const result = str.sliceBetween(template, "{{", "}}", pos) orelse {
            try output.appendSlice(allocator, template[pos..]);
            break;
        };
        try output.appendSlice(allocator, template[pos..result.open_index]);
        const tag = parseTag(result);
        pos = tag.close_pos;
        switch (tag.kind) {
            .raw => try renderRaw(allocator, context, tag.name, &output),
            .section_open => {
                const session = try findSectionEnd(template, tag.name, tag.close_pos);
                if (context.get(tag.name)) |value| {
                    try renderSection(arena, session.inner, templates, context, value, &output);
                }
                pos = session.end;
            },
            .partial => {
                const partial_tmpl = templates.get(tag.name) orelse return error.UnknownPartial;
                const html = try render(arena, partial_tmpl, templates, context);
                try output.appendSlice(allocator, html);
            },
            .variable => try renderVariable(allocator, context, tag.name, &output),
            else => {},
        }
    }
    return output.items;
}

test "render home example" {
    const header_template =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="utf-8">
        \\  <title>{{ title }}</title>
        \\</head>
        \\<body>
        \\  <nav>
        \\    {{# menu_main }}
        \\    <a href="{{ url }}">{{ name }}</a>
        \\    {{/ menu_main }}
        \\  </nav>
    ;
    const home_template =
        \\{{> partials/header.html }}
        \\
        \\  <h1>{{ title }}</h1>
        \\  {{{ body }}}
        \\
        \\  <h2>Recent posts</h2>
        \\  <ul>
        \\    {{# posts }}
        \\    <li><a href="{{ url }}">{{ name }}</a> — {{ date }}</li>
        \\    {{/ posts }}
        \\  </ul>
        \\
        \\</body>
        \\</html>
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    var context = std.StringHashMap(CtxValue).init(allocator);

    try context.put("title", .{ .string = "<Home Page>" });
    try context.put("body", .{ .string = "<h1>Hello</h1>" });

    var posts_list = std.ArrayList(std.StringHashMap(CtxValue)).initCapacity(allocator, 2) catch unreachable;
    {
        var ctx = std.StringHashMap(CtxValue).init(allocator);
        try ctx.put("name", .{ .string = "Bananas" });
        try ctx.put("url", .{ .string = "/posts/bananas" });
        try ctx.put("date", .{ .string = "1977-01-01" });
        try posts_list.append(allocator, ctx);
    }
    {
        var ctx = std.StringHashMap(CtxValue).init(allocator);
        try ctx.put("name", .{ .string = "Apples" });
        try ctx.put("url", .{ .string = "/posts/apples" });
        try ctx.put("date", .{ .string = "1977-01-02" });
        try posts_list.append(allocator, ctx);
    }
    try context.put("posts", .{ .list = posts_list.items });

    var menu_list = std.ArrayList(std.StringHashMap(CtxValue)).initCapacity(allocator, 2) catch unreachable;
    {
        var ctx = std.StringHashMap(CtxValue).init(allocator);
        try ctx.put("name", .{ .string = "Home" });
        try ctx.put("url", .{ .string = "/site/home" });
        try menu_list.append(allocator, ctx);
    }
    {
        var ctx = std.StringHashMap(CtxValue).init(allocator);
        try ctx.put("name", .{ .string = "About" });
        try ctx.put("url", .{ .string = "/site/about" });
        try menu_list.append(allocator, ctx);
    }
    try context.put("menu_main", .{ .list = menu_list.items });

    var templates = std.StringHashMap([]const u8).init(arena.allocator());
    defer templates.deinit();

    try templates.put("partials/header.html", header_template);
    try templates.put("home.html", home_template);

    const entries = try render(&arena, home_template, templates, context);

    const expected =
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="utf-8">
        \\  <title>&lt;Home Page&gt;</title>
        \\</head>
        \\<body>
        \\  <nav>
        \\    
        \\    <a href="/site/home">Home</a>
        \\    
        \\    <a href="/site/about">About</a>
        \\    
        \\  </nav>
        \\
        \\  <h1>&lt;Home Page&gt;</h1>
        \\  <h1>Hello</h1>
        \\
        \\  <h2>Recent posts</h2>
        \\  <ul>
        \\    
        \\    <li><a href="/posts/bananas">Bananas</a> — 1977-01-01</li>
        \\    
        \\    <li><a href="/posts/apples">Apples</a> — 1977-01-02</li>
        \\    
        \\  </ul>
        \\
        \\</body>
        \\</html>
    ;
    try std.testing.expectEqualStrings(expected, entries);
}

test "non-string value in {{ }} tag does not crash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var context = std.StringHashMap(CtxValue).init(allocator);
    defer context.deinit();
    try context.put("items", .{ .list = &.{
        blk: {
            var ctx = std.StringHashMap(CtxValue).init(allocator);
            try ctx.put("name", .{ .string = "foo" });
            try ctx.put("url", .{ .string = "/bar" });
            break :blk ctx;
        },
    } });

    var templates = std.StringHashMap([]const u8).init(allocator);
    defer templates.deinit();

    const result = try render(&arena, "{{ items }}", templates, context);
    try std.testing.expectEqualStrings("", result);
}

test "child section inherits parent scope" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var context = std.StringHashMap(CtxValue).init(allocator);
    defer context.deinit();
    try context.put("site_name", .{ .string = "MySite" });
    try context.put("items", .{ .list = &.{
        blk: {
            var ctx = std.StringHashMap(CtxValue).init(allocator);
            try ctx.put("name", .{ .string = "Home" });
            try ctx.put("url", .{ .string = "/" });
            break :blk ctx;
        },
    } });

    var templates = std.StringHashMap([]const u8).init(allocator);
    defer templates.deinit();

    const result = try render(&arena, "{{# items }}{{ site_name }}:{{ name }}{{/ items }}", templates, context);
    try std.testing.expectEqualStrings("MySite:Home", result);
}

test "nested same-name sections resolve correctly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var context = std.StringHashMap(CtxValue).init(allocator);
    defer context.deinit();
    try context.put("x", .{ .list = &.{
        blk: {
            var ctx = std.StringHashMap(CtxValue).init(allocator);
            try ctx.put("name", .{ .string = "outer" });
            try ctx.put("url", .{ .string = "/o" });
            break :blk ctx;
        },
    } });

    var templates = std.StringHashMap([]const u8).init(allocator);
    defer templates.deinit();

    const tmpl = "{{# x }}{{ name }}-{{# x }}{{ name }}{{/ x }}{{/ x }}";
    const result = try render(&arena, tmpl, templates, context);
    try std.testing.expectEqualStrings("outer-outer", result);
}

test "triple brace {{{ }}} renders raw html without stray characters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var context = std.StringHashMap(CtxValue).init(allocator);
    defer context.deinit();
    try context.put("body", .{ .string = "<h1>Hello</h1>" });

    var templates = std.StringHashMap([]const u8).init(allocator);
    defer templates.deinit();

    const result = try render(&arena, "start{{{ body }}}end", templates, context);
    try std.testing.expectEqualStrings("start<h1>Hello</h1>end", result);
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

test "findSectionEnd simple section" {
    const template = "{{# items }}content{{/ items }}";
    const result = try findSectionEnd(template, "items", 12);
    try std.testing.expectEqualStrings("content", result.inner);
    try std.testing.expectEqual(@as(usize, template.len), result.end);
}

test "findSectionEnd unclosed section returns error" {
    const template = "{{# items }}no closing tag";
    try std.testing.expectError(error.UnclosedSection, findSectionEnd(template, "items", 12));
}

test "findSectionEnd handles nested same-name sections" {
    const template = "a{{# x }}outer{{# x }}inner{{/ x }}{{/ x }}b";
    const result = try findSectionEnd(template, "x", 9);
    try std.testing.expectEqualStrings("outer{{# x }}inner{{/ x }}", result.inner);
    try std.testing.expectEqual(@as(usize, 43), result.end);
}

test "findSectionEnd different named sections do not nest" {
    const template = "{{# a }}content{{/ a }}";
    const result = try findSectionEnd(template, "a", 8);
    try std.testing.expectEqualStrings("content", result.inner);
    try std.testing.expectEqual(@as(usize, template.len), result.end);
}

test "findSectionEnd empty section body" {
    const template = "{{# x }}{{/ x }}";
    const result = try findSectionEnd(template, "x", 8);
    try std.testing.expectEqualStrings("", result.inner);
    try std.testing.expectEqual(@as(usize, template.len), result.end);
}

test "findSectionEnd mismatched close tag does not close" {
    const template = "{{# a }}{{# b }}{{/ b }}{{/ a }}";
    const result = try findSectionEnd(template, "a", 8);
    try std.testing.expectEqualStrings("{{# b }}{{/ b }}", result.inner);
    try std.testing.expectEqual(@as(usize, template.len), result.end);
}

test "findSectionEnd section with surrounding text" {
    const template = "before{{# x }}mid{{/ x }}after";
    const result = try findSectionEnd(template, "x", 14);
    try std.testing.expectEqualStrings("mid", result.inner);
    try std.testing.expectEqual(@as(usize, 25), result.end);
}
