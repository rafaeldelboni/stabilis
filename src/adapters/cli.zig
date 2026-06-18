const std = @import("std");

const debug = @import("../debug.zig");
const models = @import("../models.zig");
const Command = models.Command;
const ServeArgs = models.ServeArgs;
const BuildArgs = models.BuildArgs;
const NewPostArgs = models.NewPostArgs;
const NewPageArgs = models.NewPageArgs;

const FlagMatch = union(enum) {
    none,
    attached: []const u8,
    separate,
};

fn isFlag(tok: []const u8, long: []const u8, short: []const u8) bool {
    return std.mem.eql(u8, tok, long) or std.mem.eql(u8, tok, short);
}

fn matchFlag(tok: []const u8, long: []const u8, short: []const u8) FlagMatch {
    if (isFlag(tok, long, short)) return .separate;

    if (std.mem.indexOfScalar(u8, tok, '=')) |eq| {
        const head = tok[0..eq];
        if (std.mem.eql(u8, head, long) or std.mem.eql(u8, head, short))
            return .{ .attached = tok[eq + 1 ..] };
    }

    return .none;
}

fn nextValue(args: []const []const u8, i: usize) error{MissingValue}![]const u8 {
    if (i + 1 >= args.len) return error.MissingValue;

    const next = args[i + 1];
    if (next.len > 1 and next[0] == '-' and !std.mem.eql(u8, next, "--"))
        return error.MissingValue;

    return next;
}

fn parseNumber(s: []const u8) error{InvalidValue}!u16 {
    return std.fmt.parseInt(u16, s, 10) catch error.InvalidValue;
}

fn appendSplit(arena: *std.heap.ArenaAllocator, list: *std.ArrayList([]const u8), value: []const u8) !void {
    const allocator = arena.allocator();
    var parts = std.mem.splitScalar(u8, value, ',');
    while (parts.next()) |raw| {
        const item = std.mem.trim(u8, raw, " ");
        if (item.len > 0) try list.append(allocator, item);
    }
}

fn parseBuildArgs(args: []const []const u8) !BuildArgs {
    var result: BuildArgs = .{};
    var i: usize = 0;
    debug.printJson(args);
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        switch (matchFlag(arg, "--dest", "-d")) {
            .none => {},
            .attached => |v| {
                result.destination = v;
                continue;
            },
            .separate => {
                result.destination = try nextValue(args, i);
                i += 1;
                continue;
            },
        }
        std.debug.print("after dest {s}\n", .{arg});

        if (isFlag(arg, "--drafts", "-D")) {
            result.build_drafts = true;
            continue;
        }

        if (isFlag(arg, "--minify", "-m")) {
            result.minify = true;
            continue;
        }

        if (isFlag(arg, "--clean-dest-dir", "-c")) {
            result.clean_destination_dir = true;
            continue;
        }

        if (isFlag(arg, "--help", "-h")) {
            result.help = true;
            continue;
        }

        if (arg.len > 0 and arg[0] != '-' and !std.mem.eql(u8, arg, "--")) {
            result.source = arg;
            continue;
        }

        return error.UnknownFlag;
    }
    return result;
}

fn parseServeArgs(args: []const []const u8) !ServeArgs {
    var result: ServeArgs = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        switch (matchFlag(arg, "--port", "-p")) {
            .none => {},
            .attached => |v| {
                result.port = try parseNumber(v);
                continue;
            },
            .separate => {
                result.port = try parseNumber(try nextValue(args, i));
                i += 1;
                continue;
            },
        }

        switch (matchFlag(arg, "--bind", "-b")) {
            .none => {},
            .attached => |v| {
                result.bind = v;
                continue;
            },
            .separate => {
                result.bind = try nextValue(args, i);
                i += 1;
                continue;
            },
        }

        if (isFlag(arg, "--open", "-o")) {
            result.open = true;
            continue;
        }

        if (isFlag(arg, "--drafts", "-D")) {
            result.build_drafts = true;
            continue;
        }

        if (isFlag(arg, "--help", "-h")) {
            result.help = true;
            continue;
        }

        return error.UnknownFlag;
    }
    return result;
}

fn parseNewPostArgs(arena: *std.heap.ArenaAllocator, args: []const []const u8) !NewPostArgs {
    var result: NewPostArgs = .{ .title = "" };
    var tags: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        switch (matchFlag(arg, "--desc", "-d")) {
            .none => {},
            .attached => |v| {
                result.description = v;
                continue;
            },
            .separate => {
                result.description = try nextValue(args, i);
                i += 1;
                continue;
            },
        }

        switch (matchFlag(arg, "--tags", "-t")) {
            .none => {},
            .attached => |v| {
                try appendSplit(arena, &tags, v);
                continue;
            },
            .separate => {
                try appendSplit(arena, &tags, try nextValue(args, i));
                i += 1;
                continue;
            },
        }

        if (isFlag(arg, "--draft", "-D")) {
            result.draft = true;
            continue;
        }

        if (isFlag(arg, "--help", "-h")) {
            result.help = true;
            continue;
        }

        if (arg.len > 0 and arg[0] != '-' and !std.mem.eql(u8, arg, "--")) {
            result.title = arg;
            continue;
        }

        return error.UnknownFlag;
    }
    if (result.title.len == 0) return error.MissingTitle;
    result.tags = tags.items;
    return result;
}

fn parseNewPageArgs(arena: *std.heap.ArenaAllocator, args: []const []const u8) !NewPageArgs {
    var result: NewPageArgs = .{ .title = "" };
    var menus: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        switch (matchFlag(arg, "--slug", "-s")) {
            .none => {},
            .attached => |v| {
                result.slug = v;
                continue;
            },
            .separate => {
                result.slug = try nextValue(args, i);
                i += 1;
                continue;
            },
        }

        switch (matchFlag(arg, "--menus", "-m")) {
            .none => {},
            .attached => |v| {
                try appendSplit(arena, &menus, v);
                continue;
            },
            .separate => {
                try appendSplit(arena, &menus, try nextValue(args, i));
                i += 1;
                continue;
            },
        }

        if (isFlag(arg, "--draft", "-D")) {
            result.draft = true;
            continue;
        }

        if (isFlag(arg, "--help", "-h")) {
            result.help = true;
            continue;
        }

        if (arg.len > 0 and arg[0] != '-' and !std.mem.eql(u8, arg, "--")) {
            result.title = arg;
            continue;
        }

        return error.UnknownFlag;
    }
    if (result.title.len == 0) return error.MissingTitle;
    result.menus = menus.items;
    return result;
}

/// Parses raw CLI args (argv) into a typed Command by dispatching on the
/// first positional (`build`, `serve`, `new`, `help`, `version`) and parsing
/// the remaining tokens with the command-specific parser.
///
/// `args[0]` is the program name and is ignored. Returns `.help` when no
/// command is given. List allocations (e.g. post tags, page menus) live in
/// the caller's arena.
pub fn parse(arena: *std.heap.ArenaAllocator, args: []const []const u8) !Command {
    if (args.len <= 1) return .help;
    const command_arg = args[1];
    if (std.mem.eql(u8, command_arg, "help") or
        std.mem.eql(u8, command_arg, "--help") or
        std.mem.eql(u8, command_arg, "-h")) return .help;
    if (std.mem.eql(u8, command_arg, "version") or
        std.mem.eql(u8, command_arg, "--version") or
        std.mem.eql(u8, command_arg, "-v")) return .version;
    if (std.mem.eql(u8, command_arg, "serve"))
        return .{ .serve = try parseServeArgs(args[2..]) };
    if (std.mem.eql(u8, command_arg, "build"))
        return .{ .build = try parseBuildArgs(args[2..]) };
    if (std.mem.eql(u8, command_arg, "new")) {
        if (args.len < 3) return .{ .new = .help };
        const sub = args[2];
        if (std.mem.eql(u8, sub, "post"))
            return .{ .new = .{ .post = try parseNewPostArgs(arena, args[3..]) } };
        if (std.mem.eql(u8, sub, "page"))
            return .{ .new = .{ .page = try parseNewPageArgs(arena, args[3..]) } };
        return .{ .new = .help };
    }
    return error.UnknownCommand;
}

test "parse dispatches top-level commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectEqual(Command.help, try parse(&arena, &.{"stabilis"}));
    try std.testing.expectEqual(Command.help, try parse(&arena, &.{ "stabilis", "help" }));
    try std.testing.expectEqual(Command.help, try parse(&arena, &.{ "stabilis", "--help" }));
    try std.testing.expectEqual(Command.help, try parse(&arena, &.{ "stabilis", "-h" }));
    try std.testing.expectEqual(Command.version, try parse(&arena, &.{ "stabilis", "version" }));
    try std.testing.expectEqual(Command.version, try parse(&arena, &.{ "stabilis", "--version" }));
    try std.testing.expectEqual(Command.version, try parse(&arena, &.{ "stabilis", "-v" }));
    try std.testing.expectError(error.UnknownCommand, parse(&arena, &.{ "stabilis", "delbongo" }));

    const new_none = try parse(&arena, &.{ "stabilis", "new" });
    try std.testing.expect(new_none == .new);
    try std.testing.expect(new_none.new == .help);

    const new_unknown = try parse(&arena, &.{ "stabilis", "new", "unknown" });
    try std.testing.expect(new_unknown == .new);
    try std.testing.expect(new_unknown.new == .help);
}

test "parse 'build' parses short, long, and combined flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const defaults = try parse(&arena, &.{ "stabilis", "build" });
    try std.testing.expect(defaults == .build);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.build.source);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.build.destination);
    try std.testing.expectEqual(false, defaults.build.build_drafts);
    try std.testing.expectEqual(false, defaults.build.minify);
    try std.testing.expectEqual(false, defaults.build.clean_destination_dir);
    try std.testing.expectEqual(false, defaults.build.help);

    const pos = try parse(&arena, &.{ "stabilis", "build", "mycontent" });
    try std.testing.expectEqualStrings("mycontent", pos.build.source.?);

    const d = try parse(&arena, &.{ "stabilis", "build", "-d", "out" });
    try std.testing.expectEqualStrings("out", d.build.destination.?);

    const dest = try parse(&arena, &.{ "stabilis", "build", "--dest", "out" });
    try std.testing.expectEqualStrings("out", dest.build.destination.?);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "-D" })).build.build_drafts);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--drafts" })).build.build_drafts);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--minify" })).build.minify);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--clean-dest-dir" })).build.clean_destination_dir);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--help" })).build.help);

    const combined = try parse(&arena, &.{ "stabilis", "build", "content", "-d", "public", "-D", "--minify" });
    try std.testing.expectEqualStrings("content", combined.build.source.?);
    try std.testing.expectEqualStrings("public", combined.build.destination.?);
    try std.testing.expectEqual(true, combined.build.build_drafts);
    try std.testing.expectEqual(true, combined.build.minify);
}

test "parse 'build' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "build", "--bogus" }));
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "build", "-d" }));
}

test "parse 'new post' parses short, long, and list flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const defaults = try parse(&arena, &.{ "stabilis", "new", "post", "Hello World" });
    try std.testing.expect(defaults == .new);
    try std.testing.expect(defaults.new == .post);
    try std.testing.expectEqualStrings("Hello World", defaults.new.post.title);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.new.post.description);
    try std.testing.expectEqual(@as(usize, 0), defaults.new.post.tags.len);
    try std.testing.expectEqual(false, defaults.new.post.draft);
    try std.testing.expectEqual(false, defaults.new.post.help);

    const d = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-d", "A description" });
    try std.testing.expectEqualStrings("A description", d.new.post.description.?);

    const desc = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--desc", "A description" });
    try std.testing.expectEqualStrings("A description", desc.new.post.description.?);

    const single = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig" });
    try std.testing.expectEqual(@as(usize, 1), single.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", single.new.post.tags[0]);

    const comma = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig,clojure" });
    try std.testing.expectEqual(@as(usize, 2), comma.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", comma.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", comma.new.post.tags[1]);

    const repeated = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig", "-t", "clojure" });
    try std.testing.expectEqual(@as(usize, 2), repeated.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", repeated.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", repeated.new.post.tags[1]);

    const long_tags = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--tags", "zig,clojure" });
    try std.testing.expectEqual(@as(usize, 2), long_tags.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", long_tags.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", long_tags.new.post.tags[1]);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--draft" })).new.post.draft);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--help" })).new.post.help);

    const all = try parse(&arena, &.{
        "stabilis", "new",  "post", "Hello World",
        "-d",       "desc", "-t",   "a,b",
        "--draft",
    });
    try std.testing.expectEqualStrings("Hello World", all.new.post.title);
    try std.testing.expectEqualStrings("desc", all.new.post.description.?);
    try std.testing.expectEqual(@as(usize, 2), all.new.post.tags.len);
    try std.testing.expectEqual(true, all.new.post.draft);
}

test "parse 'new post' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.MissingTitle, parse(&arena, &.{ "stabilis", "new", "post" }));
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t" }));
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--bogus" }));
}

test "parse 'new page' parses short, long, and list flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const defaults = try parse(&arena, &.{ "stabilis", "new", "page", "About Me" });
    try std.testing.expect(defaults == .new);
    try std.testing.expect(defaults.new == .page);
    try std.testing.expectEqualStrings("About Me", defaults.new.page.title);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.new.page.slug);
    try std.testing.expectEqual(false, defaults.new.page.draft);
    try std.testing.expectEqual(@as(usize, 0), defaults.new.page.menus.len);
    try std.testing.expectEqual(false, defaults.new.page.help);

    const s = try parse(&arena, &.{ "stabilis", "new", "page", "About", "-s", "about" });
    try std.testing.expectEqualStrings("about", s.new.page.slug.?);

    const slug = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--slug", "about" });
    try std.testing.expectEqualStrings("about", slug.new.page.slug.?);

    const single = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--menus", "main" });
    try std.testing.expectEqual(@as(usize, 1), single.new.page.menus.len);
    try std.testing.expectEqualStrings("main", single.new.page.menus[0]);

    const comma = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--menus", "main,footer" });
    try std.testing.expectEqual(@as(usize, 2), comma.new.page.menus.len);
    try std.testing.expectEqualStrings("main", comma.new.page.menus[0]);
    try std.testing.expectEqualStrings("footer", comma.new.page.menus[1]);

    const repeated = try parse(&arena, &.{ "stabilis", "new", "page", "About", "-m", "main", "-m", "footer" });
    try std.testing.expectEqual(@as(usize, 2), repeated.new.page.menus.len);
    try std.testing.expectEqualStrings("main", repeated.new.page.menus[0]);
    try std.testing.expectEqualStrings("footer", repeated.new.page.menus[1]);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "page", "About", "--draft" })).new.page.draft);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "page", "About", "--help" })).new.page.help);

    const all = try parse(&arena, &.{
        "stabilis", "new",   "page",    "About",
        "-s",       "about", "--draft", "--menus",
        "main",
    });
    try std.testing.expectEqualStrings("About", all.new.page.title);
    try std.testing.expectEqualStrings("about", all.new.page.slug.?);
    try std.testing.expectEqual(true, all.new.page.draft);
    try std.testing.expectEqual(@as(usize, 1), all.new.page.menus.len);
    try std.testing.expectEqualStrings("main", all.new.page.menus[0]);
}

test "parse 'new page' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.MissingTitle, parse(&arena, &.{ "stabilis", "new", "page" }));
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "new", "page", "About", "-s" }));
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "new", "page", "About", "--bogus" }));
}

test "parse 'serve' parses short, long, and combined flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const defaults = try parse(&arena, &.{ "stabilis", "serve" });
    try std.testing.expect(defaults == .serve);
    try std.testing.expectEqual(@as(?u16, null), defaults.serve.port);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.serve.bind);
    try std.testing.expectEqual(false, defaults.serve.open);
    try std.testing.expectEqual(true, defaults.serve.build_drafts);
    try std.testing.expectEqual(false, defaults.serve.help);

    const p = try parse(&arena, &.{ "stabilis", "serve", "-p", "8080" });
    try std.testing.expectEqual(@as(u16, 8080), p.serve.port.?);

    const port = try parse(&arena, &.{ "stabilis", "serve", "--port", "1313" });
    try std.testing.expectEqual(@as(u16, 1313), port.serve.port.?);

    const bind = try parse(&arena, &.{ "stabilis", "serve", "--bind", "0.0.0.0" });
    try std.testing.expectEqualStrings("0.0.0.0", bind.serve.bind.?);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "serve", "--open" })).serve.open);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "serve", "-D" })).serve.build_drafts);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "serve", "--help" })).serve.help);

    const combined = try parse(&arena, &.{ "stabilis", "serve", "-p", "8080", "--bind", "0.0.0.0", "--open", "-D" });
    try std.testing.expectEqual(@as(u16, 8080), combined.serve.port.?);
    try std.testing.expectEqualStrings("0.0.0.0", combined.serve.bind.?);
    try std.testing.expectEqual(true, combined.serve.open);
    try std.testing.expectEqual(true, combined.serve.build_drafts);
}

test "parse 'serve' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "serve", "-p" }));
    try std.testing.expectError(error.InvalidValue, parse(&arena, &.{ "stabilis", "serve", "-p", "abc" }));
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "serve", "--bogus" }));
}
