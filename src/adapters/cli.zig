const std = @import("std");

const modelsCli = @import("../models/cli.zig");
const logic = @import("../logic/cli.zig");
const Cli = modelsCli.Cli;
const Diagnostics = modelsCli.Diagnostics;
const Command = modelsCli.Command;
const Flag = modelsCli.Flag;
const FlagType = logic.FlagType;

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
    const flag_type = comptime logic.parseFieldTypes(FieldT);
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
        if (logic.nameMatches(arg, flag)) {
            const FieldT = @FieldType(T, flag.field);
            if (@typeInfo(FieldT) == .bool) {
                @field(target.*, flag.field) = true;
                return .matched;
            }
            if (i.* + 1 >= args.len) return diagError(arg, flag.field, diag, error.MissingValue);
            const raw = args[i.* + 1];
            if (logic.looksLikeFlag(raw))
                return diagError(arg, flag.field, diag, error.MissingValue);
            i.* += 1;
            @field(target.*, flag.field) = try parseFields(arena, T, flag, @field(target.*, flag.field), raw);
            return .matched;
        } else if (logic.splitFlagAssignment(arg)) |assign| {
            if (logic.nameMatches(assign.head, flag)) {
                @field(target.*, flag.field) = try parseFields(arena, T, flag, @field(target.*, flag.field), assign.value);
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

        if (logic.startsLikeFlag(arg)) return diagError(arg, cmd_name, diag, error.UnknownFlag);

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
    if (args.len == 0 or !logic.startsLikeFlag(args[0])) return false;
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

const t_top_flags = struct {
    version: bool = false,
    help: bool = false,
    name: []const u8 = "",
};
const t_top_items = [_]modelsCli.Flag{
    .{ .long = "--help", .short = "-h", .field = "help", .terminal = true, .help = "" },
    .{ .long = "--version", .short = "-v", .field = "version", .terminal = true, .help = "" },
    .{ .long = "--name", .short = "-n", .field = "name", .help = "" },
};

const t_leaf_result = struct {
    bool_flag: bool = false,
    str_flag: []const u8 = "",
    num_flag: ?u16 = null,
    list_flag: []const []const u8 = &.{},
};
const t_leaf_items = [_]modelsCli.Flag{
    .{ .long = "--bool", .short = "-b", .field = "bool_flag", .help = "" },
    .{ .long = "--str", .short = "-s", .field = "str_flag", .help = "" },
    .{ .long = "--num", .short = "-N", .field = "num_flag", .help = "" },
    .{ .long = "--list", .short = "-l", .field = "list_flag", .help = "" },
};
const t_sub_result = struct {
    title: []const u8 = "",
};
const t_sub_items = [_]modelsCli.Flag{};
fn t_leaf_cli() modelsCli.Cli {
    return .{
        .flags = .{ .Result = t_top_flags, .items = &t_top_items },
        .commands = .{
            .Result = union(enum) { leaf: t_leaf_result },
            .items = &.{.{
                .name = "leaf",
                .help = "",
                .body = .{ .command = .{
                    .Result = t_leaf_result,
                    .flags = &t_leaf_items,
                    .positionals = &.{},
                } },
            }},
        },
    };
}
fn t_group_cli() modelsCli.Cli {
    return .{
        .flags = .{ .Result = t_top_flags, .items = &t_top_items },
        .commands = .{
            .Result = union(enum) { grp: union(enum) { sub: t_sub_result } },
            .items = &.{.{
                .name = "grp",
                .help = "",
                .body = .{ .sub_commands = &.{.{
                    .name = "sub",
                    .help = "",
                    .body = .{ .command = .{
                        .Result = t_sub_result,
                        .flags = &t_sub_items,
                        .positionals = &.{"title"},
                    } },
                }} },
            }},
        },
    };
}

test "parse returns NoCommand when args <= 1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    try std.testing.expectError(error.NoCommand, parse(&arena, &.{"app"}, cli, &diag));
}

test "parse shared-only flags short/long/=/bool/terminal and UnknownFlag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "app", "--help" }, cli, &diag)).flags.help);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "app", "-h" }, cli, &diag)).flags.help);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "app", "--version" }, cli, &diag)).flags.version);
    try std.testing.expectEqualStrings("z", (try parse(&arena, &.{ "app", "--name", "z" }, cli, &diag)).flags.name);
    try std.testing.expectEqualStrings("y", (try parse(&arena, &.{ "app", "-n", "y" }, cli, &diag)).flags.name);
    try std.testing.expectEqualStrings("x", (try parse(&arena, &.{ "app", "--name=x" }, cli, &diag)).flags.name);
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "app", "--bogus" }, cli, &diag));
}

test "parse returns UnknownCommand for unknown top-level" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    try std.testing.expectError(error.UnknownCommand, parse(&arena, &.{ "app", "bogus" }, cli, &diag));
    try std.testing.expectEqual("bogus", diag.arg);
}

test "parse returns NoSubCommand when group gets no sub" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_group_cli();
    try std.testing.expectError(error.NoSubCommand, parse(&arena, &.{ "app", "grp" }, cli, &diag));
    try std.testing.expectEqual("grp", diag.name);
}

test "parse returns UnknownSubCommand for unknown sub" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_group_cli();
    try std.testing.expectError(error.UnknownSubCommand, parse(&arena, &.{ "app", "grp", "bogus" }, cli, &diag));
}

test "parse leaf command yields default-valued result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    const out = try parse(&arena, &.{ "app", "leaf" }, cli, &diag);
    try std.testing.expect(out.commands.? == .leaf);
    try std.testing.expectEqual(false, out.commands.?.leaf.bool_flag);
    try std.testing.expectEqual("", out.commands.?.leaf.str_flag);
    try std.testing.expectEqual(@as(?u16, null), out.commands.?.leaf.num_flag);
    try std.testing.expectEqual(@as(usize, 0), out.commands.?.leaf.list_flag.len);
}

test "parse leaf flags short/long/=/bool/string/number valid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "app", "leaf", "-b" }, cli, &diag)).commands.?.leaf.bool_flag);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "app", "leaf", "--bool" }, cli, &diag)).commands.?.leaf.bool_flag);
    try std.testing.expectEqualStrings("v", (try parse(&arena, &.{ "app", "leaf", "-s", "v" }, cli, &diag)).commands.?.leaf.str_flag);
    try std.testing.expectEqualStrings("w", (try parse(&arena, &.{ "app", "leaf", "--str", "w" }, cli, &diag)).commands.?.leaf.str_flag);
    try std.testing.expectEqualStrings("eq", (try parse(&arena, &.{ "app", "leaf", "--str=eq" }, cli, &diag)).commands.?.leaf.str_flag);
    try std.testing.expectEqual(@as(u16, 9), (try parse(&arena, &.{ "app", "leaf", "-N", "9" }, cli, &diag)).commands.?.leaf.num_flag.?);
    try std.testing.expectEqual(@as(u16, 10), (try parse(&arena, &.{ "app", "leaf", "--num", "10" }, cli, &diag)).commands.?.leaf.num_flag.?);
}

test "parse number flag returns InvalidValue on non-numeric" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    try std.testing.expectError(error.InvalidValue, parse(&arena, &.{ "app", "leaf", "-N", "abc" }, cli, &diag));
}

test "parse list flag single/comma/repeated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    const one = try parse(&arena, &.{ "app", "leaf", "-l", "a" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 1), one.commands.?.leaf.list_flag.len);
    try std.testing.expectEqualStrings("a", one.commands.?.leaf.list_flag[0]);
    const comma = try parse(&arena, &.{ "app", "leaf", "-l", "a,b" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 2), comma.commands.?.leaf.list_flag.len);
    try std.testing.expectEqualStrings("a", comma.commands.?.leaf.list_flag[0]);
    try std.testing.expectEqualStrings("b", comma.commands.?.leaf.list_flag[1]);
    const rep = try parse(&arena, &.{ "app", "leaf", "-l", "a", "-l", "b" }, cli, &diag);
    try std.testing.expectEqual(@as(usize, 2), rep.commands.?.leaf.list_flag.len);
    try std.testing.expectEqualStrings("a", rep.commands.?.leaf.list_flag[0]);
    try std.testing.expectEqualStrings("b", rep.commands.?.leaf.list_flag[1]);
}

test "parse positional + MissingPositional + TooManyPositionals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_group_cli();
    const ok = try parse(&arena, &.{ "app", "grp", "sub", "hello" }, cli, &diag);
    try std.testing.expectEqualStrings("hello", ok.commands.?.grp.sub.title);
    try std.testing.expectError(error.MissingPositional, parse(&arena, &.{ "app", "grp", "sub" }, cli, &diag));
    try std.testing.expectError(error.TooManyPositionals, parse(&arena, &.{ "app", "grp", "sub", "a", "b" }, cli, &diag));
}

test "parse returns MissingValue when value flag lacks value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "app", "leaf", "-s" }, cli, &diag));
}

test "parse returns UnknownFlag inside leaf command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "app", "leaf", "--bogus" }, cli, &diag));
}

test "parse terminal global --help passes through inside command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};
    const cli = t_leaf_cli();
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "app", "leaf", "--help" }, cli, &diag)).flags.help);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "app", "leaf", "-h" }, cli, &diag)).flags.help);
}

test "parse nested subcommands two levels deep" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag = Diagnostics{};

    const inner_result = struct {
        name: []const u8 = "",
    };
    const inner_items = [_]modelsCli.Flag{};
    const cli = modelsCli.Cli{
        .flags = .{ .Result = t_top_flags, .items = &t_top_items },
        .commands = .{
            .Result = union(enum) { outer: union(enum) { middle: union(enum) { inner: inner_result } } },
            .items = &.{.{
                .name = "outer",
                .help = "",
                .body = .{ .sub_commands = &.{.{
                    .name = "middle",
                    .help = "",
                    .body = .{ .sub_commands = &.{.{
                        .name = "inner",
                        .help = "",
                        .body = .{ .command = .{
                            .Result = inner_result,
                            .flags = &inner_items,
                            .positionals = &.{"name"},
                        } },
                    }} },
                }} },
            }},
        },
    };

    const out = try parse(&arena, &.{ "app", "outer", "middle", "inner", "deep" }, cli, &diag);
    try std.testing.expect(out.commands.? == .outer);
    try std.testing.expect(out.commands.?.outer == .middle);
    try std.testing.expect(out.commands.?.outer.middle == .inner);
    try std.testing.expectEqualStrings("deep", out.commands.?.outer.middle.inner.name);

    try std.testing.expectError(error.NoSubCommand, parse(&arena, &.{ "app", "outer", "middle" }, cli, &diag));
    try std.testing.expectError(error.UnknownSubCommand, parse(&arena, &.{ "app", "outer", "middle", "bogus" }, cli, &diag));
}
