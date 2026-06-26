const std = @import("std");

const modelsCli = @import("../models/cli.zig");
const Cli = modelsCli.Cli;
const Diagnostics = modelsCli.Diagnostics;
const Command = modelsCli.Command;
const Flag = modelsCli.Flag;

/// Maps a field type to its CLI value kind for help output.
const FlagType = enum {
    boolean,
    number,
    list_of_strings,
    string,
};

/// The parse result: shared args plus an optional command result.
fn Output(comptime cli: Cli) type {
    if (cli.commands) |cmds| {
        return struct {
            flags: cli.flags.Result,
            commands: ?cmds.Result,
        };
    } else {
        return struct {
            flags: cli.flags.Result,
            commands: ?bool = null,
        };
    }
}

fn diagError(arg: []const u8, name: []const u8, diag: *Diagnostics, err: anyerror) anyerror {
    diag.arg = arg;
    diag.name = name;
    return err;
}

/// Infers the `FlagType` from a struct field's type at comptime.
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

const Match = enum { matched, not_matched };

fn applyFlag(
    arena: *std.heap.ArenaAllocator,
    arg: []const u8,
    comptime T: type,
    comptime flags: []const Flag,
    target: *T,
    args: []const []const u8,
    i: *usize,
    diag: *Diagnostics,
) !Match {
    inline for (flags) |flag| {
        if (std.mem.eql(u8, arg, flag.long) or std.mem.eql(u8, arg, flag.short)) {
            const FieldT = @FieldType(T, flag.field);
            if (@typeInfo(FieldT) == .bool) {
                @field(target.*, flag.field) = true;
                return .matched;
            }
            if (i.* + 1 >= args.len) return diagError(arg, flag.field, diag, error.MissingValue);
            const raw = args[i.* + 1];
            if (raw.len > 1 and raw[0] == '-' and !std.mem.eql(u8, raw, "--"))
                return diagError(arg, flag.field, diag, error.MissingValue);
            i.* += 1;
            @field(target.*, flag.field) = try parseFields(arena, T, flag, @field(target.*, flag.field), raw);
            return .matched;
        } else if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            const head = arg[0..eq];
            if (std.mem.eql(u8, head, flag.long) or std.mem.eql(u8, head, flag.short)) {
                const raw = arg[eq + 1 ..];
                @field(target.*, flag.field) = try parseFields(arena, T, flag, @field(target.*, flag.field), raw);
                return .matched;
            }
        }
    }
    return .not_matched;
}

fn parseArgs(
    arena: *std.heap.ArenaAllocator,
    comptime cli: Cli,
    comptime cmd_name: []const u8,
    comptime cmd_flags: []const Flag,
    comptime positionals: []const []const u8,
    out: *Output(cli),
    args: []const []const u8,
    diag: *Diagnostics,
) !void {
    const C = @FieldType(cli.commands.?.Result, cmd_name);
    var i: usize = 0;
    var pos_idx: usize = 0;
    next_arg: while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (try applyFlag(arena, arg, C, cmd_flags, &@field(out.commands.?, cmd_name), args, &i, diag) == .matched) continue :next_arg;
        if (try applyFlag(arena, arg, cli.flags.Result, cli.flags.items, &out.flags, args, &i, diag) == .matched) continue :next_arg;

        if (arg.len > 0 and arg[0] == '-') return diagError(arg, cmd_name, diag, error.UnknownFlag);

        inline for (positionals, 0..) |pos, j| {
            if (j == pos_idx) {
                @field(@field(out.commands.?, cmd_name), pos) = arg;
                pos_idx += 1;
                continue :next_arg;
            }
        }

        return diagError(arg, cmd_name, diag, error.TooManyPositionals);
    }

    inline for (cli.flags.items) |flag| {
        if (flag.terminal) {
            if (@typeInfo(@FieldType(cli.flags.Result, flag.field)) == .bool and @field(out.flags, flag.field)) return;
        }
    }

    inline for (positionals, 0..) |pos, j| {
        if (j >= pos_idx) {
            const FieldT = @FieldType(C, pos);
            if (@typeInfo(FieldT) != .optional) return diagError(pos, cmd_name, diag, error.MissingPositional);
        }
    }
}

fn assertAligned(comptime T: type, comptime cmds: []const Command) void {
    inline for (cmds) |cmd| {
        switch (cmd.body) {
            .command => _ = @field(T, cmd.name),
            .sub_commands => |subs| {
                const Sub = @FieldType(T, cmd.name);
                inline for (subs) |sub| _ = @field(Sub, sub.name);
            },
        }
    }
}

fn parseSharedOnly(
    arena: *std.heap.ArenaAllocator,
    comptime cli: Cli,
    out: *Output(cli),
    args: []const []const u8,
    diag_name: []const u8,
    diag: *Diagnostics,
) !bool {
    if (args.len == 0 or args[0].len == 0 or args[0][0] != '-') return false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (try applyFlag(arena, args[i], cli.flags.Result, cli.flags.items, &out.flags, args, &i, diag) == .matched) continue;
        return diagError(args[i], diag_name, diag, error.UnknownFlag);
    }
    return true;
}

fn parseImpl(
    arena: *std.heap.ArenaAllocator,
    args: []const []const u8,
    comptime cli: Cli,
    diag: *Diagnostics,
    comptime maybe_cmd: ?Command,
) !Output(cli) {
    var out: Output(cli) = .{ .flags = cli.flags.Result{}, .commands = null };

    if (maybe_cmd == null) {
        if (args.len == 0) return diagError("", "", diag, error.NoCommand);
        const arg = args[0];

        if (cli.commands) |cli_cmd| {
            inline for (cli_cmd.items) |cmd| {
                if (std.mem.eql(u8, arg, cmd.name))
                    return parseImpl(arena, args[1..], cli, diag, cmd);
            }
        }

        if (try parseSharedOnly(arena, cli, &out, args, "", diag)) return out;

        return diagError(arg, "", diag, error.UnknownCommand);
    }

    const cmd = maybe_cmd.?;
    switch (cmd.body) {
        .command => |spec| {
            if (cli.commands) |cmds| {
                out.commands = @unionInit(cmds.Result, cmd.name, spec.Result{});
            }
            try parseArgs(arena, cli, cmd.name, spec.flags, spec.positionals, &out, args, diag);
        },
        .sub_commands => |sub_cmds| {
            if (cli.commands == null) return;
            const Sub = @FieldType(cli.commands.?.Result, cmd.name);

            if (args.len == 0) return diagError("", cmd.name, diag, error.NoSubCommand);
            const sub_arg = args[0];

            if (try parseSharedOnly(arena, cli, &out, args, cmd.name, diag)) return out;

            inline for (sub_cmds) |sub_cmd| {
                if (std.mem.eql(u8, sub_arg, sub_cmd.name)) {
                    const sub_cli = Cli{ .flags = .{ .Result = cli.flags.Result, .items = cli.flags.items }, .commands = .{ .Result = Sub, .items = sub_cmds } };
                    const sub_out = try parseImpl(arena, args[1..], sub_cli, diag, sub_cmd);
                    out.flags = sub_out.flags;
                    if (sub_out.commands) |sub| out.commands = @unionInit(cli.commands.?.Result, cmd.name, sub);
                    return out;
                }
            }
            return diagError(sub_arg, cmd.name, diag, error.UnknownSubCommand);
        },
    }
    return out;
}

/// Parses `args` against the CLI definition, returning global args and
/// the dispatched command result if one was matched.
pub fn parse(
    arena: *std.heap.ArenaAllocator,
    args: []const []const u8,
    comptime cli: Cli,
    diag: *Diagnostics,
) !Output(cli) {
    if (cli.commands) |cmds|
        comptime assertAligned(cmds.Result, cmds.items);
    if (args.len <= 1) return error.NoCommand;
    return parseImpl(arena, args[1..], cli, diag, null);
}

const test_models = @import("../models.zig");

test "parse dispatches top-level without commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};

    const FlagsReturn = struct {
        version: bool = false,
        help: bool = false,
        banana: []const u8 = "",
    };

    const cli = modelsCli.Cli{
        .flags = .{
            .Result = FlagsReturn,
            .items = &.{
                .{ .long = "--help", .short = "-h", .field = "help", .terminal = true, .help = "Show help" },
                .{ .long = "--version", .short = "-v", .field = "version", .terminal = true, .help = "Print version" },
                .{ .long = "--banana", .short = "-b", .field = "banana", .terminal = true, .help = "Print version" },
            },
        },
    };

    try std.testing.expectError(error.NoCommand, parse(&arena, &.{"stabilis"}, cli, &diag));
    try std.testing.expectEqual("", diag.arg);
    try std.testing.expectEqual("", diag.name);

    const help_long = try parse(&arena, &.{ "stabilis", "--help" }, cli, &diag);
    try std.testing.expectEqual(true, help_long.flags.help);

    const help_short = try parse(&arena, &.{ "stabilis", "-h" }, cli, &diag);
    try std.testing.expectEqual(true, help_short.flags.help);

    const ver_long = try parse(&arena, &.{ "stabilis", "--version" }, cli, &diag);
    try std.testing.expectEqual(true, ver_long.flags.version);

    const ver_short = try parse(&arena, &.{ "stabilis", "-v" }, cli, &diag);
    try std.testing.expectEqual(true, ver_short.flags.version);

    const banana_long = try parse(&arena, &.{ "stabilis", "--banana", "happy" }, cli, &diag);
    try std.testing.expectEqual("happy", banana_long.flags.banana);

    const banana_short = try parse(&arena, &.{ "stabilis", "-b", "sad" }, cli, &diag);
    try std.testing.expectEqual("sad", banana_short.flags.banana);

    try std.testing.expectError(error.UnknownCommand, parse(&arena, &.{ "stabilis", "delbongo" }, cli, &diag));
    try std.testing.expectEqual("delbongo", diag.arg);
    try std.testing.expectEqual("", diag.name);

    try std.testing.expectError(error.UnknownCommand, parse(&arena, &.{ "stabilis", "new" }, cli, &diag));
    try std.testing.expectEqual("new", diag.arg);
    try std.testing.expectEqual("", diag.name);

    try std.testing.expectError(error.UnknownCommand, parse(&arena, &.{ "stabilis", "new", "unknown" }, cli, &diag));
    try std.testing.expectEqual("new", diag.arg);
    try std.testing.expectEqual("", diag.name);
}

test "parse dispatches top-level commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const cli = test_models.stabilis_cli;

    try std.testing.expectError(error.NoCommand, parse(&arena, &.{"stabilis"}, cli, &diag));
    try std.testing.expectEqual("", diag.arg);
    try std.testing.expectEqual("", diag.name);

    const help_long = try parse(&arena, &.{ "stabilis", "--help" }, cli, &diag);
    try std.testing.expectEqual(true, help_long.flags.help);
    try std.testing.expectEqual(@as(?test_models.CommandsResult, null), help_long.commands);

    const help_short = try parse(&arena, &.{ "stabilis", "-h" }, cli, &diag);
    try std.testing.expectEqual(true, help_short.flags.help);

    const ver_long = try parse(&arena, &.{ "stabilis", "--version" }, cli, &diag);
    try std.testing.expectEqual(true, ver_long.flags.version);

    const ver_short = try parse(&arena, &.{ "stabilis", "-v" }, cli, &diag);
    try std.testing.expectEqual(true, ver_short.flags.version);

    try std.testing.expectError(error.UnknownCommand, parse(&arena, &.{ "stabilis", "delbongo" }, cli, &diag));
    try std.testing.expectEqual("delbongo", diag.arg);
    try std.testing.expectEqual("", diag.name);

    try std.testing.expectError(error.NoSubCommand, parse(&arena, &.{ "stabilis", "new" }, cli, &diag));
    try std.testing.expectEqual("", diag.arg);
    try std.testing.expectEqual("new", diag.name);

    try std.testing.expectError(error.UnknownSubCommand, parse(&arena, &.{ "stabilis", "new", "unknown" }, cli, &diag));
}

test "parse 'build' parses short, long, and combined flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const cli = test_models.stabilis_cli;

    const defaults = try parse(&arena, &.{ "stabilis", "build" }, cli, &diag);
    try std.testing.expect(defaults.commands.? == .build);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.commands.?.build.source);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.commands.?.build.destination);
    try std.testing.expectEqual(false, defaults.commands.?.build.build_drafts);
    try std.testing.expectEqual(false, defaults.commands.?.build.minify);
    try std.testing.expectEqual(false, defaults.commands.?.build.clear_dir);

    const pos = try parse(&arena, &.{ "stabilis", "build", "mycontent" }, cli, &diag);
    try std.testing.expectEqualStrings("mycontent", pos.commands.?.build.source.?);

    const d = try parse(&arena, &.{ "stabilis", "build", "-d", "out" }, cli, &diag);
    try std.testing.expectEqualStrings("out", d.commands.?.build.destination.?);

    const dest = try parse(&arena, &.{ "stabilis", "build", "--dest", "out" }, cli, &diag);
    try std.testing.expectEqualStrings("out", dest.commands.?.build.destination.?);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "-b" }, cli, &diag)).commands.?.build.build_drafts);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--build-drafts" }, cli, &diag)).commands.?.build.build_drafts);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--minify" }, cli, &diag)).commands.?.build.minify);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--clear-dir" }, cli, &diag)).commands.?.build.clear_dir);

    const build_help = try parse(&arena, &.{ "stabilis", "build", "--help" }, cli, &diag);
    try std.testing.expectEqual(true, build_help.flags.help);
    const build_h = try parse(&arena, &.{ "stabilis", "build", "-h" }, cli, &diag);
    try std.testing.expectEqual(true, build_h.flags.help);

    const combined = try parse(&arena, &.{ "stabilis", "build", "content", "-d", "public", "-b", "--minify" }, cli, &diag);
    try std.testing.expectEqualStrings("content", combined.commands.?.build.source.?);
    try std.testing.expectEqualStrings("public", combined.commands.?.build.destination.?);
    try std.testing.expectEqual(true, combined.commands.?.build.build_drafts);
    try std.testing.expectEqual(true, combined.commands.?.build.minify);
}

test "parse 'build' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const cli = test_models.stabilis_cli;

    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "build", "--bogus" }, cli, &diag));
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "build", "-d" }, cli, &diag));
}

test "parse 'new post' parses short, long, and list flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const cli = test_models.stabilis_cli;

    const defaults = try parse(&arena, &.{ "stabilis", "new", "post", "Hello World" }, cli, &diag);
    try std.testing.expect(defaults.commands.? == .new);
    try std.testing.expect(defaults.commands.?.new == .post);
    try std.testing.expectEqualStrings("Hello World", defaults.commands.?.new.post.title);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.commands.?.new.post.description);
    try std.testing.expectEqual(@as(usize, 0), defaults.commands.?.new.post.tags.len);
    try std.testing.expectEqual(false, defaults.commands.?.new.post.draft);

    const d = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-d", "A description" }, cli, &diag);
    try std.testing.expectEqualStrings("A description", d.commands.?.new.post.description.?);

    const desc = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--desc", "A description" }, cli, &diag);
    try std.testing.expectEqualStrings("A description", desc.commands.?.new.post.description.?);

    const single = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 1), single.commands.?.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", single.commands.?.new.post.tags[0]);

    const comma = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig,clojure" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 2), comma.commands.?.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", comma.commands.?.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", comma.commands.?.new.post.tags[1]);

    const repeated = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig", "-t", "clojure" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 2), repeated.commands.?.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", repeated.commands.?.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", repeated.commands.?.new.post.tags[1]);

    const long_tags = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--tags", "zig,clojure" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 2), long_tags.commands.?.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", long_tags.commands.?.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", long_tags.commands.?.new.post.tags[1]);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--draft" }, cli, &diag)).commands.?.new.post.draft);

    const post_help = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--help" }, cli, &diag);
    try std.testing.expectEqual(true, post_help.flags.help);
    const post_h = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-h" }, cli, &diag);
    try std.testing.expectEqual(true, post_h.flags.help);

    const all = try parse(&arena, &.{
        "stabilis", "new",  "post", "Hello World",
        "-d",       "desc", "-t",   "a,b",
        "--draft",
    }, cli, &diag);
    try std.testing.expectEqualStrings("Hello World", all.commands.?.new.post.title);
    try std.testing.expectEqualStrings("desc", all.commands.?.new.post.description.?);
    try std.testing.expectEqual(@as(usize, 2), all.commands.?.new.post.tags.len);
    try std.testing.expectEqual(true, all.commands.?.new.post.draft);
}

test "parse 'new post' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const cli = test_models.stabilis_cli;

    try std.testing.expectError(error.MissingPositional, parse(&arena, &.{ "stabilis", "new", "post" }, cli, &diag));
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t" }, cli, &diag));
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--bogus" }, cli, &diag));
}

test "parse 'new page' parses short, long, and list flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const cli = test_models.stabilis_cli;

    const defaults = try parse(&arena, &.{ "stabilis", "new", "page", "About Me" }, cli, &diag);
    try std.testing.expect(defaults.commands.? == .new);
    try std.testing.expect(defaults.commands.?.new == .page);
    try std.testing.expectEqualStrings("About Me", defaults.commands.?.new.page.title);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.commands.?.new.page.slug);
    try std.testing.expectEqual(false, defaults.commands.?.new.page.draft);
    try std.testing.expectEqual(@as(usize, 0), defaults.commands.?.new.page.menus.len);

    const s = try parse(&arena, &.{ "stabilis", "new", "page", "About", "-s", "about" }, cli, &diag);
    try std.testing.expectEqualStrings("about", s.commands.?.new.page.slug.?);

    const slug = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--slug", "about" }, cli, &diag);
    try std.testing.expectEqualStrings("about", slug.commands.?.new.page.slug.?);

    const single = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--menus", "main" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 1), single.commands.?.new.page.menus.len);
    try std.testing.expectEqualStrings("main", single.commands.?.new.page.menus[0]);

    const comma = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--menus", "main,footer" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 2), comma.commands.?.new.page.menus.len);
    try std.testing.expectEqualStrings("main", comma.commands.?.new.page.menus[0]);
    try std.testing.expectEqualStrings("footer", comma.commands.?.new.page.menus[1]);

    const repeated = try parse(&arena, &.{ "stabilis", "new", "page", "About", "-m", "main", "-m", "footer" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 2), repeated.commands.?.new.page.menus.len);
    try std.testing.expectEqualStrings("main", repeated.commands.?.new.page.menus[0]);
    try std.testing.expectEqualStrings("footer", repeated.commands.?.new.page.menus[1]);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "page", "About", "--draft" }, cli, &diag)).commands.?.new.page.draft);

    const page_help = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--help" }, cli, &diag);
    try std.testing.expectEqual(true, page_help.flags.help);
    const page_h = try parse(&arena, &.{ "stabilis", "new", "page", "About", "-h" }, cli, &diag);
    try std.testing.expectEqual(true, page_h.flags.help);

    const all = try parse(&arena, &.{
        "stabilis", "new",   "page",    "About",
        "-s",       "about", "--draft", "--menus",
        "main",
    }, cli, &diag);
    try std.testing.expectEqualStrings("About", all.commands.?.new.page.title);
    try std.testing.expectEqualStrings("about", all.commands.?.new.page.slug.?);
    try std.testing.expectEqual(true, all.commands.?.new.page.draft);
    try std.testing.expectEqual(@as(usize, 1), all.commands.?.new.page.menus.len);
    try std.testing.expectEqualStrings("main", all.commands.?.new.page.menus[0]);
}

test "parse 'new page' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const cli = test_models.stabilis_cli;

    try std.testing.expectError(error.MissingPositional, parse(&arena, &.{ "stabilis", "new", "page" }, cli, &diag));
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "new", "page", "About", "-s" }, cli, &diag));
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "new", "page", "About", "--bogus" }, cli, &diag));
}

test "parse 'serve' parses short, long, and combined flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const cli = test_models.stabilis_cli;

    const defaults = try parse(&arena, &.{ "stabilis", "serve" }, cli, &diag);
    try std.testing.expect(defaults.commands.? == .serve);
    try std.testing.expectEqual(@as(?u16, null), defaults.commands.?.serve.port);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.commands.?.serve.bind);
    try std.testing.expectEqual(false, defaults.commands.?.serve.open);
    try std.testing.expectEqual(false, defaults.commands.?.serve.no_drafts);

    const p = try parse(&arena, &.{ "stabilis", "serve", "-p", "8080" }, cli, &diag);
    try std.testing.expectEqual(@as(u16, 8080), p.commands.?.serve.port.?);

    const port = try parse(&arena, &.{ "stabilis", "serve", "--port", "1313" }, cli, &diag);
    try std.testing.expectEqual(@as(u16, 1313), port.commands.?.serve.port.?);

    const bind = try parse(&arena, &.{ "stabilis", "serve", "--bind", "0.0.0.0" }, cli, &diag);
    try std.testing.expectEqualStrings("0.0.0.0", bind.commands.?.serve.bind.?);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "serve", "--open" }, cli, &diag)).commands.?.serve.open);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "serve", "-n" }, cli, &diag)).commands.?.serve.no_drafts);

    const serve_help = try parse(&arena, &.{ "stabilis", "serve", "--help" }, cli, &diag);
    try std.testing.expectEqual(true, serve_help.flags.help);
    const serve_h = try parse(&arena, &.{ "stabilis", "serve", "-h" }, cli, &diag);
    try std.testing.expectEqual(true, serve_h.flags.help);

    const combined = try parse(&arena, &.{ "stabilis", "serve", "-p", "8080", "--bind", "0.0.0.0", "--open", "-n" }, cli, &diag);
    try std.testing.expectEqual(@as(u16, 8080), combined.commands.?.serve.port.?);
    try std.testing.expectEqualStrings("0.0.0.0", combined.commands.?.serve.bind.?);
    try std.testing.expectEqual(true, combined.commands.?.serve.open);
    try std.testing.expectEqual(true, combined.commands.?.serve.no_drafts);
}

test "parse 'serve' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const cli = test_models.stabilis_cli;

    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "serve", "-p" }, cli, &diag));
    try std.testing.expectError(error.InvalidValue, parse(&arena, &.{ "stabilis", "serve", "-p", "abc" }, cli, &diag));
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "serve", "--bogus" }, cli, &diag));
}
