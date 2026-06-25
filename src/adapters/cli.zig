const std = @import("std");

const models = @import("../models.zig");
const CommandResult = models.CommandResult;
const modelsCli = @import("../models/cli.zig");
const Command = modelsCli.Command;
const Diagnostics = modelsCli.Diagnostics;
const NamedCommand = modelsCli.NamedCommand;
const CommandSpec = modelsCli.CommandSpec;
const Flag = modelsCli.Flag;

pub const FlagType = enum {
    boolean,
    number,
    list_of_strings,
    string,
};

fn diagError(arg: []const u8, name: []const u8, diag: *Diagnostics, err: anyerror) anyerror {
    diag.arg = arg;
    diag.name = name;
    return err;
}

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
    cmd_name: []const u8,
    comptime spec: CommandSpec,
    args: []const []const u8,
    diag: *Diagnostics,
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
                if (i + 1 >= args.len) return diagError(arg, flag.field, diag, error.MissingValue);

                const raw = args[i + 1];
                if (raw.len > 1 and raw[0] == '-' and !std.mem.eql(u8, raw, "--"))
                    return diagError(arg, flag.field, diag, error.MissingValue);

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

        if (arg.len > 0 and arg[0] == '-') return diagError(arg, cmd_name, diag, error.UnknownFlag);

        inline for (spec.positionals, 0..) |pos, j| {
            if (j == pos_idx) {
                @field(result, pos) = arg;
                pos_idx += 1;
                continue :next_arg;
            }
        }

        return diagError(arg, cmd_name, diag, error.TooManyPositionals);
    }

    inline for (spec.positionals, 0..) |pos, j| {
        if (j >= pos_idx) {
            const FieldT = @FieldType(spec.Result, pos);
            if (@typeInfo(FieldT) != .optional) return diagError(pos, cmd_name, diag, error.MissingPositional);
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

fn parseImpl(
    arena: *std.heap.ArenaAllocator,
    args: []const []const u8,
    comptime command: Command,
    diag: *Diagnostics,
    comptime maybe_cmd: ?NamedCommand,
) !command.ReturnT {
    if (maybe_cmd == null) {
        if (args.len == 0) return diagError("", "", diag, error.NoCommand);
        const arg = args[0];
        inline for (command.commands) |cmd| {
            const matched = switch (cmd.spec) {
                .tag_only => matchTagAlias(arg, cmd.name),
                else => std.mem.eql(u8, arg, cmd.name),
            };
            if (matched) return parseImpl(arena, args[1..], command, diag, cmd);
        }
        return diagError(arg, "", diag, error.UnknownCommand);
    }
    const cmd = maybe_cmd.?;
    return switch (cmd.spec) {
        .tag_only => return @field(command.ReturnT, cmd.name),
        .command => |spec| @unionInit(command.ReturnT, cmd.name, try commandParse(arena, cmd.name, spec, args, diag)),
        .sub_commands => |sub_cmds| {
            const Sub = @FieldType(command.ReturnT, cmd.name);
            if (args.len == 0) return diagError("", cmd.name, diag, error.NoSubCommand);
            const sub_arg = args[0];
            inline for (sub_cmds) |sub_cmd| {
                if (std.mem.eql(u8, sub_arg, sub_cmd.name)) {
                    const sub_cmds2 = Command{ .commands = sub_cmds, .ReturnT = Sub };
                    // recurse on the SUB type, then wrap one level
                    const sub = try parseImpl(arena, args[1..], sub_cmds2, diag, sub_cmd);
                    return @unionInit(command.ReturnT, cmd.name, sub);
                }
            }
            return diagError(sub_arg, cmd.name, diag, error.UnknownSubCommand);
        },
    };
}

pub fn parse(
    arena: *std.heap.ArenaAllocator,
    args: []const []const u8,
    comptime command: Command,
    diag: *Diagnostics,
) !command.ReturnT {
    comptime assertAligned(command.ReturnT, command.commands);
    if (args.len <= 1) return error.NoCommand;
    return parseImpl(arena, args[1..], command, diag, null);
}

test "parse dispatches top-level commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const commands = Command{ .commands = &models.stabilis_commands, .ReturnT = CommandResult };

    try std.testing.expectError(error.NoCommand, parse(&arena, &.{"stabilis"}, commands, &diag));
    try std.testing.expectEqual("", diag.arg);
    try std.testing.expectEqual("", diag.name);

    try std.testing.expectEqual(CommandResult.help, try parse(&arena, &.{ "stabilis", "help" }, commands, &diag));
    try std.testing.expectEqual(CommandResult.help, try parse(&arena, &.{ "stabilis", "--help" }, commands, &diag));
    try std.testing.expectEqual(CommandResult.help, try parse(&arena, &.{ "stabilis", "-h" }, commands, &diag));
    try std.testing.expectEqual(CommandResult.version, try parse(&arena, &.{ "stabilis", "version" }, commands, &diag));
    try std.testing.expectEqual(CommandResult.version, try parse(&arena, &.{ "stabilis", "--version" }, commands, &diag));
    try std.testing.expectEqual(CommandResult.version, try parse(&arena, &.{ "stabilis", "-v" }, commands, &diag));

    try std.testing.expectError(error.UnknownCommand, parse(&arena, &.{ "stabilis", "delbongo" }, commands, &diag));
    try std.testing.expectEqual("delbongo", diag.arg);
    try std.testing.expectEqual("", diag.name);

    try std.testing.expectError(error.NoSubCommand, parse(&arena, &.{ "stabilis", "new" }, commands, &diag));
    try std.testing.expectEqual("", diag.arg);
    try std.testing.expectEqual("new", diag.name);
    try std.testing.expectError(error.UnknownSubCommand, parse(&arena, &.{ "stabilis", "new", "unknown" }, commands, &diag));
}

test "parse 'build' parses short, long, and combined flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const commands = Command{ .commands = &models.stabilis_commands, .ReturnT = CommandResult };

    const defaults = try parse(&arena, &.{ "stabilis", "build" }, commands, &diag);
    try std.testing.expect(defaults == .build);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.build.source);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.build.destination);
    try std.testing.expectEqual(false, defaults.build.build_drafts);
    try std.testing.expectEqual(false, defaults.build.minify);
    try std.testing.expectEqual(false, defaults.build.clear_dir);
    try std.testing.expectEqual(false, defaults.build.help);

    const pos = try parse(&arena, &.{ "stabilis", "build", "mycontent" }, commands, &diag);
    try std.testing.expectEqualStrings("mycontent", pos.build.source.?);

    const d = try parse(&arena, &.{ "stabilis", "build", "-d", "out" }, commands, &diag);
    try std.testing.expectEqualStrings("out", d.build.destination.?);

    const dest = try parse(&arena, &.{ "stabilis", "build", "--dest", "out" }, commands, &diag);
    try std.testing.expectEqualStrings("out", dest.build.destination.?);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "-b" }, commands, &diag)).build.build_drafts);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--build-drafts" }, commands, &diag)).build.build_drafts);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--minify" }, commands, &diag)).build.minify);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--clear-dir" }, commands, &diag)).build.clear_dir);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "build", "--help" }, commands, &diag)).build.help);

    const combined = try parse(&arena, &.{ "stabilis", "build", "content", "-d", "public", "-b", "--minify" }, commands, &diag);
    try std.testing.expectEqualStrings("content", combined.build.source.?);
    try std.testing.expectEqualStrings("public", combined.build.destination.?);
    try std.testing.expectEqual(true, combined.build.build_drafts);
    try std.testing.expectEqual(true, combined.build.minify);
}

test "parse 'build' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const commands = Command{ .commands = &models.stabilis_commands, .ReturnT = CommandResult };

    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "build", "--bogus" }, commands, &diag));
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "build", "-d" }, commands, &diag));
}

test "parse 'new post' parses short, long, and list flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const commands = Command{ .commands = &models.stabilis_commands, .ReturnT = CommandResult };

    const defaults = try parse(&arena, &.{ "stabilis", "new", "post", "Hello World" }, commands, &diag);
    try std.testing.expect(defaults == .new);
    try std.testing.expect(defaults.new == .post);
    try std.testing.expectEqualStrings("Hello World", defaults.new.post.title);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.new.post.description);
    try std.testing.expectEqual(@as(usize, 0), defaults.new.post.tags.len);
    try std.testing.expectEqual(false, defaults.new.post.draft);
    try std.testing.expectEqual(false, defaults.new.post.help);

    const d = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-d", "A description" }, commands, &diag);
    try std.testing.expectEqualStrings("A description", d.new.post.description.?);

    const desc = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--desc", "A description" }, commands, &diag);
    try std.testing.expectEqualStrings("A description", desc.new.post.description.?);

    const single = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig" }, commands, &diag);
    try std.testing.expectEqual(@as(usize, 1), single.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", single.new.post.tags[0]);

    const comma = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig,clojure" }, commands, &diag);
    try std.testing.expectEqual(@as(usize, 2), comma.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", comma.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", comma.new.post.tags[1]);

    const repeated = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t", "zig", "-t", "clojure" }, commands, &diag);
    try std.testing.expectEqual(@as(usize, 2), repeated.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", repeated.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", repeated.new.post.tags[1]);

    const long_tags = try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--tags", "zig,clojure" }, commands, &diag);
    try std.testing.expectEqual(@as(usize, 2), long_tags.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", long_tags.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", long_tags.new.post.tags[1]);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--draft" }, commands, &diag)).new.post.draft);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--help" }, commands, &diag)).new.post.help);

    const all = try parse(&arena, &.{
        "stabilis", "new",  "post", "Hello World",
        "-d",       "desc", "-t",   "a,b",
        "--draft",
    }, commands, &diag);
    try std.testing.expectEqualStrings("Hello World", all.new.post.title);
    try std.testing.expectEqualStrings("desc", all.new.post.description.?);
    try std.testing.expectEqual(@as(usize, 2), all.new.post.tags.len);
    try std.testing.expectEqual(true, all.new.post.draft);
}

test "parse 'new post' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const commands = Command{ .commands = &models.stabilis_commands, .ReturnT = CommandResult };

    try std.testing.expectError(error.MissingPositional, parse(&arena, &.{ "stabilis", "new", "post" }, commands, &diag));
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "new", "post", "Hello", "-t" }, commands, &diag));
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "new", "post", "Hello", "--bogus" }, commands, &diag));
}

test "parse 'new page' parses short, long, and list flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const commands = Command{ .commands = &models.stabilis_commands, .ReturnT = CommandResult };

    const defaults = try parse(&arena, &.{ "stabilis", "new", "page", "About Me" }, commands, &diag);
    try std.testing.expect(defaults == .new);
    try std.testing.expect(defaults.new == .page);
    try std.testing.expectEqualStrings("About Me", defaults.new.page.title);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.new.page.slug);
    try std.testing.expectEqual(false, defaults.new.page.draft);
    try std.testing.expectEqual(@as(usize, 0), defaults.new.page.menus.len);
    try std.testing.expectEqual(false, defaults.new.page.help);

    const s = try parse(&arena, &.{ "stabilis", "new", "page", "About", "-s", "about" }, commands, &diag);
    try std.testing.expectEqualStrings("about", s.new.page.slug.?);

    const slug = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--slug", "about" }, commands, &diag);
    try std.testing.expectEqualStrings("about", slug.new.page.slug.?);

    const single = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--menus", "main" }, commands, &diag);
    try std.testing.expectEqual(@as(usize, 1), single.new.page.menus.len);
    try std.testing.expectEqualStrings("main", single.new.page.menus[0]);

    const comma = try parse(&arena, &.{ "stabilis", "new", "page", "About", "--menus", "main,footer" }, commands, &diag);
    try std.testing.expectEqual(@as(usize, 2), comma.new.page.menus.len);
    try std.testing.expectEqualStrings("main", comma.new.page.menus[0]);
    try std.testing.expectEqualStrings("footer", comma.new.page.menus[1]);

    const repeated = try parse(&arena, &.{ "stabilis", "new", "page", "About", "-m", "main", "-m", "footer" }, commands, &diag);
    try std.testing.expectEqual(@as(usize, 2), repeated.new.page.menus.len);
    try std.testing.expectEqualStrings("main", repeated.new.page.menus[0]);
    try std.testing.expectEqualStrings("footer", repeated.new.page.menus[1]);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "page", "About", "--draft" }, commands, &diag)).new.page.draft);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "new", "page", "About", "--help" }, commands, &diag)).new.page.help);

    const all = try parse(&arena, &.{
        "stabilis", "new",   "page",    "About",
        "-s",       "about", "--draft", "--menus",
        "main",
    }, commands, &diag);
    try std.testing.expectEqualStrings("About", all.new.page.title);
    try std.testing.expectEqualStrings("about", all.new.page.slug.?);
    try std.testing.expectEqual(true, all.new.page.draft);
    try std.testing.expectEqual(@as(usize, 1), all.new.page.menus.len);
    try std.testing.expectEqualStrings("main", all.new.page.menus[0]);
}

test "parse 'new page' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const commands = Command{ .commands = &models.stabilis_commands, .ReturnT = CommandResult };

    try std.testing.expectError(error.MissingPositional, parse(&arena, &.{ "stabilis", "new", "page" }, commands, &diag));
    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "new", "page", "About", "-s" }, commands, &diag));
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "new", "page", "About", "--bogus" }, commands, &diag));
}

test "parse 'serve' parses short, long, and combined flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const commands = Command{ .commands = &models.stabilis_commands, .ReturnT = CommandResult };

    const defaults = try parse(&arena, &.{ "stabilis", "serve" }, commands, &diag);
    try std.testing.expect(defaults == .serve);
    try std.testing.expectEqual(@as(?u16, null), defaults.serve.port);
    try std.testing.expectEqual(@as(?[]const u8, null), defaults.serve.bind);
    try std.testing.expectEqual(false, defaults.serve.open);
    try std.testing.expectEqual(false, defaults.serve.no_drafts);
    try std.testing.expectEqual(false, defaults.serve.help);

    const p = try parse(&arena, &.{ "stabilis", "serve", "-p", "8080" }, commands, &diag);
    try std.testing.expectEqual(@as(u16, 8080), p.serve.port.?);

    const port = try parse(&arena, &.{ "stabilis", "serve", "--port", "1313" }, commands, &diag);
    try std.testing.expectEqual(@as(u16, 1313), port.serve.port.?);

    const bind = try parse(&arena, &.{ "stabilis", "serve", "--bind", "0.0.0.0" }, commands, &diag);
    try std.testing.expectEqualStrings("0.0.0.0", bind.serve.bind.?);

    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "serve", "--open" }, commands, &diag)).serve.open);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "serve", "-n" }, commands, &diag)).serve.no_drafts);
    try std.testing.expectEqual(true, (try parse(&arena, &.{ "stabilis", "serve", "--help" }, commands, &diag)).serve.help);

    const combined = try parse(&arena, &.{ "stabilis", "serve", "-p", "8080", "--bind", "0.0.0.0", "--open", "-n" }, commands, &diag);
    try std.testing.expectEqual(@as(u16, 8080), combined.serve.port.?);
    try std.testing.expectEqualStrings("0.0.0.0", combined.serve.bind.?);
    try std.testing.expectEqual(true, combined.serve.open);
    try std.testing.expectEqual(true, combined.serve.no_drafts);
}

test "parse 'serve' returns errors on bad input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diag = Diagnostics{};
    const commands = Command{ .commands = &models.stabilis_commands, .ReturnT = CommandResult };

    try std.testing.expectError(error.MissingValue, parse(&arena, &.{ "stabilis", "serve", "-p" }, commands, &diag));
    try std.testing.expectError(error.InvalidValue, parse(&arena, &.{ "stabilis", "serve", "-p", "abc" }, commands, &diag));
    try std.testing.expectError(error.UnknownFlag, parse(&arena, &.{ "stabilis", "serve", "--bogus" }, commands, &diag));
}
