const std = @import("std");

const models = @import("../models.zig");
const CommandResult = models.CommandResult;
const modelsCli = @import("../models/cli.zig");
const NamedCommand = modelsCli.NamedCommand;
const CommandSpec = modelsCli.CommandSpec;
const Flag = modelsCli.Flag;

pub const FlagType = enum {
    boolean,
    number,
    list_of_strings,
    string,
};

pub fn parseFieldTypes(comptime T: type) FlagType {
    return switch (@typeInfo(T)) {
        .bool => .boolean,
        .int => .number,
        .optional => |info| parseFieldTypes(info.child),
        .pointer => |info| if (info.size == .slice and @typeInfo(info.child) == .pointer)
            .list_of_strings
        else
            .string,
        else => .string,
    };
}

fn splitIntoSlice(
    arena: *std.heap.ArenaAllocator,
    comptime T: type,
    buffer: []const T,
    delimiter: T,
) ![]const []const T {
    const allocator = arena.allocator();
    var list: std.ArrayList([]const T) = .empty;
    var it = std.mem.splitScalar(T, buffer, delimiter);
    while (it.next()) |chunk| {
        const item = std.mem.trim(T, chunk, " ");
        if (item.len > 0) try list.append(allocator, item);
    }
    return try list.toOwnedSlice(allocator);
}

fn concatSlices(
    arena: *std.heap.ArenaAllocator,
    comptime T: type,
    a: []const T,
    b: []const T,
) ![]const T {
    if (a.len == 0) return b;
    if (b.len == 0) return a;
    const out = try arena.allocator().alloc(T, a.len + b.len);
    @memcpy(out[0..a.len], a);
    @memcpy(out[a.len..], b);
    return out;
}

fn handleStringList(
    arena: *std.heap.ArenaAllocator,
    buffer: []const u8,
    current: []const []const u8,
) ![]const []const u8 {
    const nxt = try splitIntoSlice(arena, u8, buffer, ',');
    return try concatSlices(arena, []const u8, current, nxt);
}

fn parseFields(
    arena: *std.heap.ArenaAllocator,
    comptime T: type,
    comptime flag: Flag,
    current: @FieldType(T, flag.field),
    value: []const u8,
) !@FieldType(T, flag.field) {
    const FieldT = @FieldType(T, flag.field);
    const flag_type = comptime parseFieldTypes(FieldT);
    return switch (flag_type) {
        .boolean => std.mem.eql(u8, value, "true"),
        .number => std.fmt.parseInt(
            if (@typeInfo(FieldT) == .optional) @typeInfo(FieldT).optional.child else FieldT,
            value,
            10,
        ) catch error.InvalidValue,
        .list_of_strings => try handleStringList(arena, value, current),
        else => value,
    };
}

/// Matches a `.tag_only` command by name, plus its `--`/`-` aliases.
/// `tag` is comptime so aliases fold at compile time.
pub fn matchTagAlias(name: []const u8, comptime tag: []const u8) bool {
    return std.mem.eql(u8, name, tag) or
        std.mem.eql(u8, name, "--" ++ tag) or
        std.mem.eql(u8, name, "-" ++ tag[0..1]);
}

fn commandParse(
    arena: *std.heap.ArenaAllocator,
    comptime spec: CommandSpec,
    args: []const []const u8,
) !spec.Result {
    var result: spec.Result = .{};
    var i: usize = 0;
    var pos_idx: usize = 0;
    next_arg: while (i < args.len) : (i += 1) {
        const arg = args[i];
        inline for (spec.flags) |flag| {
            if (std.mem.eql(u8, arg, flag.long) or std.mem.eql(u8, arg, flag.short)) {
                const FieldT = @FieldType(spec.Result, flag.field);
                if (@typeInfo(FieldT) == .bool) {
                    @field(result, flag.field) = true;
                    continue :next_arg;
                }
                if (i + 1 >= args.len) return error.MissingValue;

                const raw = args[i + 1];
                if (raw.len > 1 and raw[0] == '-' and !std.mem.eql(u8, raw, "--"))
                    return error.MissingValue;

                i += 1;
                @field(result, flag.field) = try parseFields(arena, spec.Result, flag, @field(result, flag.field), raw);

                continue :next_arg;
            } else if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
                const head = arg[0..eq];
                if (std.mem.eql(u8, head, flag.long) or std.mem.eql(u8, head, flag.short)) {
                    const raw = arg[eq + 1 ..];
                    @field(result, flag.field) = try parseFields(arena, spec.Result, flag, @field(result, flag.field), raw);
                    continue :next_arg;
                }
            }
        }

        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;

        inline for (spec.positionals, 0..) |pos, j| {
            if (j == pos_idx) {
                @field(result, pos) = arg;
                pos_idx += 1;
                continue :next_arg;
            }
        }

        return error.TooManyPositionals;
    }

    inline for (spec.positionals, 0..) |pos, j| {
        if (j >= pos_idx) {
            const FieldT = @FieldType(spec.Result, pos);
            if (@typeInfo(FieldT) != .optional) return error.MissingPositional;
        }
    }
    return result;
}

fn assertAligned(comptime T: type, comptime cmds: []const NamedCommand) void {
    inline for (cmds) |cmd| {
        switch (cmd.spec) {
            .tag_only => _ = @field(T, cmd.name),
            .command => _ = @field(T, cmd.name),
            .sub_commands => |subs| {
                const Sub = @FieldType(T, cmd.name); // ← discovered, not passed
                inline for (subs) |sub| _ = @field(Sub, sub.name);
            },
        }
    }
}

pub fn parseImpl(
    comptime T: type,
    arena: *std.heap.ArenaAllocator,
    comptime cmds: []const NamedCommand,
    args: []const []const u8,
    comptime maybe_cmd: ?NamedCommand,
) !T {
    if (maybe_cmd == null) {
        if (args.len == 0) return error.NoCommand;
        const name = args[0];
        inline for (cmds) |cmd| {
            const matched = switch (cmd.spec) {
                .tag_only => matchTagAlias(name, cmd.name),
                else => std.mem.eql(u8, name, cmd.name),
            };
            if (matched) return parseImpl(T, arena, cmds, args[1..], cmd);
        }
        return error.UnknownCommand;
    }
    const cmd = maybe_cmd.?;
    return switch (cmd.spec) {
        .tag_only => return @field(T, cmd.name),
        .command => |spec| @unionInit(T, cmd.name, try commandParse(arena, spec, args)),
        .sub_commands => |sub_cmds| {
            const Sub = @FieldType(T, cmd.name);
            if (args.len == 0) return error.NoSubCommand;
            const sub_name = args[0];
            inline for (sub_cmds) |sub_cmd| {
                if (std.mem.eql(u8, sub_name, sub_cmd.name)) {
                    // recurse on the SUB type, then wrap one level
                    const sub = try parseImpl(Sub, arena, sub_cmds, args[1..], sub_cmd);
                    return @unionInit(T, cmd.name, sub);
                }
            }
            return error.UnknownSubCommand;
        },
    };
}

pub fn parse(
    comptime T: type,
    arena: *std.heap.ArenaAllocator,
    args: []const []const u8,
    comptime commands: []const NamedCommand,
) !T {
    comptime assertAligned(T, commands);
    if (args.len <= 1) return error.NoCommand;
    return parseImpl(T, arena, commands, args[1..], null);
}

test "parse dispatches top-level commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const commands = &models.stabilis_commands;

    try std.testing.expectError(error.NoCommand, parse(CommandResult, &arena, &.{"stabilis"}, commands));
    try std.testing.expectEqual(CommandResult.help, try parse(CommandResult, &arena, &.{ "stabilis", "help" }, commands));
    try std.testing.expectEqual(CommandResult.help, try parse(CommandResult, &arena, &.{ "stabilis", "--help" }, commands));
    try std.testing.expectEqual(CommandResult.help, try parse(CommandResult, &arena, &.{ "stabilis", "-h" }, commands));
    try std.testing.expectEqual(CommandResult.version, try parse(CommandResult, &arena, &.{ "stabilis", "version" }, commands));
    try std.testing.expectEqual(CommandResult.version, try parse(CommandResult, &arena, &.{ "stabilis", "--version" }, commands));
    try std.testing.expectEqual(CommandResult.version, try parse(CommandResult, &arena, &.{ "stabilis", "-v" }, commands));
    try std.testing.expectError(error.UnknownCommand, parse(CommandResult, &arena, &.{ "stabilis", "delbongo" }, commands));

    try std.testing.expectError(error.NoSubCommand, parse(CommandResult, &arena, &.{ "stabilis", "new" }, commands));
    try std.testing.expectError(error.UnknownSubCommand, parse(CommandResult, &arena, &.{ "stabilis", "new", "unknown" }, commands));
}

test "parse 'build' parses short, long, and combined flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const commands = &models.stabilis_commands;

    const defaults = try parse(CommandResult, &arena, &.{ "stabilis", "build" }, commands);
    try std.testing.expect(defaults == .build);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.build.source);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.build.destination);
    try std.testing.expectEqual(false, defaults.build.build_drafts);
    try std.testing.expectEqual(false, defaults.build.minify);
    try std.testing.expectEqual(false, defaults.build.clear_dir);
    try std.testing.expectEqual(false, defaults.build.help);

    const pos = try parse(CommandResult, &arena, &.{ "stabilis", "build", "mycontent" }, commands);
    try std.testing.expectEqualStrings("mycontent", pos.build.source.?);

    const d = try parse(CommandResult, &arena, &.{ "stabilis", "build", "-d", "out" }, commands);
    try std.testing.expectEqualStrings("out", d.build.destination.?);

    const dest = try parse(CommandResult, &arena, &.{ "stabilis", "build", "--dest", "out" }, commands);
    try std.testing.expectEqualStrings("out", dest.build.destination.?);

    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "build", "-b" }, commands)).build.build_drafts);
    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "build", "--build-drafts" }, commands)).build.build_drafts);
    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "build", "--minify" }, commands)).build.minify);
    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "build", "--clear-dir" }, commands)).build.clear_dir);
    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "build", "--help" }, commands)).build.help);

    const combined = try parse(CommandResult, &arena, &.{ "stabilis", "build", "content", "-d", "public", "-b", "--minify" }, commands);
    try std.testing.expectEqualStrings("content", combined.build.source.?);
    try std.testing.expectEqualStrings("public", combined.build.destination.?);
    try std.testing.expectEqual(true, combined.build.build_drafts);
    try std.testing.expectEqual(true, combined.build.minify);
}

test "parse 'build' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const commands = &models.stabilis_commands;

    try std.testing.expectError(error.UnknownFlag, parse(CommandResult, &arena, &.{ "stabilis", "build", "--bogus" }, commands));
    try std.testing.expectError(error.MissingValue, parse(CommandResult, &arena, &.{ "stabilis", "build", "-d" }, commands));
}

test "parse 'new post' parses short, long, and list flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const commands = &models.stabilis_commands;

    const defaults = try parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello World" }, commands);
    try std.testing.expect(defaults == .new);
    try std.testing.expect(defaults.new == .post);
    try std.testing.expectEqualStrings("Hello World", defaults.new.post.title);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.new.post.description);
    try std.testing.expectEqual(@as(usize, 0), defaults.new.post.tags.len);
    try std.testing.expectEqual(false, defaults.new.post.draft);
    try std.testing.expectEqual(false, defaults.new.post.help);

    const d = try parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "-d", "A description" }, commands);
    try std.testing.expectEqualStrings("A description", d.new.post.description.?);

    const desc = try parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "--desc", "A description" }, commands);
    try std.testing.expectEqualStrings("A description", desc.new.post.description.?);

    const single = try parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig" }, commands);
    try std.testing.expectEqual(@as(usize, 1), single.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", single.new.post.tags[0]);

    const comma = try parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig,clojure" }, commands);
    try std.testing.expectEqual(@as(usize, 2), comma.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", comma.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", comma.new.post.tags[1]);

    const repeated = try parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig", "-t", "clojure" }, commands);
    try std.testing.expectEqual(@as(usize, 2), repeated.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", repeated.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", repeated.new.post.tags[1]);

    const long_tags = try parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "--tags", "zig,clojure" }, commands);
    try std.testing.expectEqual(@as(usize, 2), long_tags.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", long_tags.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", long_tags.new.post.tags[1]);

    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "--draft" }, commands)).new.post.draft);
    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "--help" }, commands)).new.post.help);

    const all = try parse(CommandResult, &arena, &.{
        "stabilis", "new",  "post", "Hello World",
        "-d",       "desc", "-t",   "a,b",
        "--draft",
    }, commands);
    try std.testing.expectEqualStrings("Hello World", all.new.post.title);
    try std.testing.expectEqualStrings("desc", all.new.post.description.?);
    try std.testing.expectEqual(@as(usize, 2), all.new.post.tags.len);
    try std.testing.expectEqual(true, all.new.post.draft);
}

test "parse 'new post' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const commands = &models.stabilis_commands;

    try std.testing.expectError(error.MissingPositional, parse(CommandResult, &arena, &.{ "stabilis", "new", "post" }, commands));
    try std.testing.expectError(error.MissingValue, parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "-t" }, commands));
    try std.testing.expectError(error.UnknownFlag, parse(CommandResult, &arena, &.{ "stabilis", "new", "post", "Hello", "--bogus" }, commands));
}

test "parse 'new page' parses short, long, and list flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const commands = &models.stabilis_commands;

    const defaults = try parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About Me" }, commands);
    try std.testing.expect(defaults == .new);
    try std.testing.expect(defaults.new == .page);
    try std.testing.expectEqualStrings("About Me", defaults.new.page.title);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.new.page.slug);
    try std.testing.expectEqual(false, defaults.new.page.draft);
    try std.testing.expectEqual(@as(usize, 0), defaults.new.page.menus.len);
    try std.testing.expectEqual(false, defaults.new.page.help);

    const s = try parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About", "-s", "about" }, commands);
    try std.testing.expectEqualStrings("about", s.new.page.slug.?);

    const slug = try parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About", "--slug", "about" }, commands);
    try std.testing.expectEqualStrings("about", slug.new.page.slug.?);

    const single = try parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About", "--menus", "main" }, commands);
    try std.testing.expectEqual(@as(usize, 1), single.new.page.menus.len);
    try std.testing.expectEqualStrings("main", single.new.page.menus[0]);

    const comma = try parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About", "--menus", "main,footer" }, commands);
    try std.testing.expectEqual(@as(usize, 2), comma.new.page.menus.len);
    try std.testing.expectEqualStrings("main", comma.new.page.menus[0]);
    try std.testing.expectEqualStrings("footer", comma.new.page.menus[1]);

    const repeated = try parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About", "-m", "main", "-m", "footer" }, commands);
    try std.testing.expectEqual(@as(usize, 2), repeated.new.page.menus.len);
    try std.testing.expectEqualStrings("main", repeated.new.page.menus[0]);
    try std.testing.expectEqualStrings("footer", repeated.new.page.menus[1]);

    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About", "--draft" }, commands)).new.page.draft);
    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About", "--help" }, commands)).new.page.help);

    const all = try parse(CommandResult, &arena, &.{
        "stabilis", "new",   "page",    "About",
        "-s",       "about", "--draft", "--menus",
        "main",
    }, commands);
    try std.testing.expectEqualStrings("About", all.new.page.title);
    try std.testing.expectEqualStrings("about", all.new.page.slug.?);
    try std.testing.expectEqual(true, all.new.page.draft);
    try std.testing.expectEqual(@as(usize, 1), all.new.page.menus.len);
    try std.testing.expectEqualStrings("main", all.new.page.menus[0]);
}

test "parse 'new page' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const commands = &models.stabilis_commands;

    try std.testing.expectError(error.MissingPositional, parse(CommandResult, &arena, &.{ "stabilis", "new", "page" }, commands));
    try std.testing.expectError(error.MissingValue, parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About", "-s" }, commands));
    try std.testing.expectError(error.UnknownFlag, parse(CommandResult, &arena, &.{ "stabilis", "new", "page", "About", "--bogus" }, commands));
}

test "parse 'serve' parses short, long, and combined flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const commands = &models.stabilis_commands;

    const defaults = try parse(CommandResult, &arena, &.{ "stabilis", "serve" }, commands);
    try std.testing.expect(defaults == .serve);
    try std.testing.expectEqual(@as(?u16, null), defaults.serve.port);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.serve.bind);
    try std.testing.expectEqual(false, defaults.serve.open);
    try std.testing.expectEqual(false, defaults.serve.no_drafts);
    try std.testing.expectEqual(false, defaults.serve.help);

    const p = try parse(CommandResult, &arena, &.{ "stabilis", "serve", "-p", "8080" }, commands);
    try std.testing.expectEqual(@as(u16, 8080), p.serve.port.?);

    const port = try parse(CommandResult, &arena, &.{ "stabilis", "serve", "--port", "1313" }, commands);
    try std.testing.expectEqual(@as(u16, 1313), port.serve.port.?);

    const bind = try parse(CommandResult, &arena, &.{ "stabilis", "serve", "--bind", "0.0.0.0" }, commands);
    try std.testing.expectEqualStrings("0.0.0.0", bind.serve.bind.?);

    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "serve", "--open" }, commands)).serve.open);
    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "serve", "-n" }, commands)).serve.no_drafts);
    try std.testing.expectEqual(true, (try parse(CommandResult, &arena, &.{ "stabilis", "serve", "--help" }, commands)).serve.help);

    const combined = try parse(CommandResult, &arena, &.{ "stabilis", "serve", "-p", "8080", "--bind", "0.0.0.0", "--open", "-n" }, commands);
    try std.testing.expectEqual(@as(u16, 8080), combined.serve.port.?);
    try std.testing.expectEqualStrings("0.0.0.0", combined.serve.bind.?);
    try std.testing.expectEqual(true, combined.serve.open);
    try std.testing.expectEqual(true, combined.serve.no_drafts);
}

test "parse 'serve' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const commands = &models.stabilis_commands;

    try std.testing.expectError(error.MissingValue, parse(CommandResult, &arena, &.{ "stabilis", "serve", "-p" }, commands));
    try std.testing.expectError(error.InvalidValue, parse(CommandResult, &arena, &.{ "stabilis", "serve", "-p", "abc" }, commands));
    try std.testing.expectError(error.UnknownFlag, parse(CommandResult, &arena, &.{ "stabilis", "serve", "--bogus" }, commands));
}
