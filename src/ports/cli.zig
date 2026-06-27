const std = @import("std");

const models = @import("../models/cli.zig");
const adapters = @import("../adapters/cli.zig");
const Cli = models.Cli;
const Command = models.Command;
const Flag = models.Flag;
const Diagnostics = models.Diagnostics;

fn printFlags(
    w: *std.Io.Writer,
    comptime T: type,
    comptime flags: []const Flag,
) !void {
    inline for (flags) |flag| {
        const FieldT = @FieldType(T, flag.field);
        const kind = switch (adapters.parseFieldTypes(FieldT)) {
            .list_of_strings => "string array",
            else => @tagName(adapters.parseFieldTypes(FieldT)),
        };
        try w.print("    {s}, {s: <14} {s: <2} [{s}]\n", .{
            flag.short,
            flag.long,
            flag.help,
            kind,
        });
    }
}

fn printHelpGeneral(
    w: *std.Io.Writer,
    comptime cli: Cli,
) !void {
    if (cli.description.len > 0) try w.print("{s} - {s}\n\n", .{ cli.name, cli.description });
    try w.print("{s} <command>\n\nCommands:\n", .{cli.name});
    if (cli.commands) |cli_cmd| {
        inline for (cli_cmd.items) |cmd| {
            try w.print("    {s: <10} {s}\n", .{ cmd.name, cmd.help });
            switch (cmd.body) {
                .sub_commands => |sub_commands| {
                    inline for (sub_commands) |sub_cmd| {
                        try w.print("      {s: <8} {s}\n", .{ sub_cmd.name, sub_cmd.help });
                    }
                },
                else => {},
            }
        }
    }
    if (cli.flags.items.len > 0) {
        try w.print("\nGlobal options:\n", .{});
        try printFlags(w, cli.flags.Result, cli.flags.items);
    }
}

fn printHelpImpl(
    w: *std.Io.Writer,
    args: []const []const u8,
    comptime cli: Cli,
    comptime maybe_cmd: ?Command,
) !void {
    if (maybe_cmd == null) {
        if (args.len == 0) {
            try printHelpGeneral(w, cli);
            return;
        }
        const name = args[0];
        if (cli.commands) |cli_cmd| {
            inline for (cli_cmd.items) |cmd| {
                if (std.mem.eql(u8, name, cmd.name)) {
                    try printHelpImpl(w, args[1..], cli, cmd);
                    return;
                }
            }
        }

        try printHelpGeneral(w, cli);
        return;
    }
    const cmd = maybe_cmd.?;
    switch (cmd.body) {
        .command => |spec| {
            try w.print("{s} {s}", .{ cli.name, cmd.name });
            for (spec.positionals) |a| try w.print(" [{s}]", .{a});
            try w.print("\n\n{s}\n\nOptions:\n", .{cmd.help});
            try printFlags(w, spec.Result, spec.flags);
            try printFlags(w, cli.flags.Result, cli.flags.items);
        },
        .sub_commands => |sub_cmds| {
            if (args.len == 0) {
                try w.print("{s} {s} <subcommand>\n\n{s}\n\nSubcommands:\n", .{ cli.name, cmd.name, cmd.help });
                inline for (sub_cmds) |sub_cmd| {
                    try w.print("    {s: <10} {s}\n", .{ sub_cmd.name, sub_cmd.help });
                }
                return;
            }
            const sub_name = args[0];
            inline for (sub_cmds) |sub_cmd| {
                if (std.mem.eql(u8, sub_name, sub_cmd.name)) {
                    try printHelpImpl(w, args[1..], cli, sub_cmd);
                    return;
                }
            }
            return error.UnknownSubcommand;
        },
    }
}

fn printHelpTo(
    w: *std.Io.Writer,
    args: []const []const u8,
    comptime cli: Cli,
) !void {
    return printHelpImpl(w, args[1..], cli, null) catch |err| {
        if (err == error.UnknownSubcommand) {
            try printHelpImpl(w, args[1 .. args.len - 1], cli, null);
        }
    };
}

/// Prints help text to stdout for the command path in `args`.
pub fn printHelp(
    io: std.Io,
    args: []const []const u8,
    comptime cli: Cli,
) !void {
    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    try printHelpTo(&stdout.interface, args, cli);
    try stdout.flush();
}

fn printDiagErrorTo(w: *std.Io.Writer, diag: *Diagnostics, err: anyerror) !void {
    const msg = switch (err) {
        error.NoCommand => "no command given",
        error.UnknownCommand => "unknown command",
        error.NoSubCommand => "expected a subcommand",
        error.UnknownSubCommand => "unknown subcommand",
        error.UnknownFlag => "unknown flag",
        error.MissingValue => "missing value for flag",
        error.InvalidValue => "invalid value for flag",
        error.MissingPositional => "missing positional argument",
        error.TooManyPositionals => "too many positional arguments",
        else => @errorName(err),
    };
    try w.print("error: {s}: '{s}'\n\n", .{ msg, diag.arg });
}

/// Prints a diagnostic error message to stderr.
pub fn printDiagError(io: std.Io, diag: *Diagnostics, err: anyerror) !void {
    var buf: [256]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buf);
    try printDiagErrorTo(&stderr.interface, diag, err);
    try stderr.flush();
}

const modelsCli = @import("../models/cli.zig");

// ----- Test fixtures -----

const t_top_flags = struct {
    version: bool = false,
    help: bool = false,
    name: []const u8 = "",
};
const t_top_items = [_]modelsCli.Flag{
    .{ .long = "--help", .short = "-h", .field = "help", .terminal = true, .help = "Show help" },
    .{ .long = "--version", .short = "-v", .field = "version", .terminal = true, .help = "Print version" },
    .{ .long = "--name", .short = "-n", .field = "name", .help = "Name" },
};

const t_leaf_result = struct {
    bool_flag: bool = false,
    str_flag: []const u8 = "",
    num_flag: ?u16 = null,
    list_flag: []const []const u8 = &.{},
};
const t_leaf_items = [_]modelsCli.Flag{
    .{ .long = "--bool", .short = "-b", .field = "bool_flag", .help = "A bool" },
    .{ .long = "--str", .short = "-s", .field = "str_flag", .help = "A string" },
    .{ .long = "--num", .short = "-N", .field = "num_flag", .help = "A number" },
    .{ .long = "--list", .short = "-l", .field = "list_flag", .help = "A list" },
};
const t_sub_result = struct {
    title: []const u8 = "",
};
const t_sub_items = [_]modelsCli.Flag{};
fn t_leaf_cli() modelsCli.Cli {
    return .{
        .name = "app",
        .description = "test app",
        .flags = .{ .Result = t_top_flags, .items = &t_top_items },
        .commands = .{
            .Result = union(enum) { leaf: t_leaf_result },
            .items = &.{.{
                .name = "leaf",
                .help = "Leaf help",
                .body = .{ .command = .{
                    .Result = t_leaf_result,
                    .flags = &t_leaf_items,
                    .positionals = &.{"source"},
                } },
            }},
        },
    };
}
fn t_group_cli() modelsCli.Cli {
    return .{
        .name = "app",
        .flags = .{ .Result = t_top_flags, .items = &t_top_items },
        .commands = .{
            .Result = union(enum) { grp: union(enum) { sub: t_sub_result } },
            .items = &.{.{
                .name = "grp",
                .help = "Group help",
                .body = .{ .sub_commands = &.{.{
                    .name = "sub",
                    .help = "Sub help",
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

fn captureHelp(allocator: std.mem.Allocator, cli: modelsCli.Cli, args: []const []const u8) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    try printHelpTo(&aw.writer, args, cli);
    return try aw.toOwnedSlice();
}

// ----- Printer tests -----

test "printHelp general lists commands, subcommands and global options" {
    const out = try captureHelp(std.testing.allocator, t_leaf_cli(), &.{ "app", "--help" });
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "app <command>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "app - test app") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Commands:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Global options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--help") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--version") != null);
}

test "printHelp leaf shows header, help, and options incl globals" {
    const out = try captureHelp(std.testing.allocator, t_leaf_cli(), &.{ "app", "leaf", "--help" });
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "app leaf [source]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Leaf help") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--str") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--num") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--list") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--help") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--version") != null);
}

test "printHelp group shows <subcommand> and Subcommands list" {
    const out = try captureHelp(std.testing.allocator, t_group_cli(), &.{ "app", "grp", "--help" });
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "app grp <subcommand>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Subcommands:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "sub") != null);
}

test "printHelp nested leaf shows header and options" {
    const out = try captureHelp(std.testing.allocator, t_group_cli(), &.{ "app", "grp", "sub", "--help" });
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "app sub [title]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Sub help") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--help") != null);
}

test "printDiagError formats UnknownCommand" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    var diag = Diagnostics{ .arg = "delbongo", .name = "" };
    try printDiagErrorTo(&aw.writer, &diag, error.UnknownCommand);
    const out = try aw.toOwnedSlice();
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "error: unknown command: 'delbongo'") != null);
}

test "printDiagError formats MissingPositional" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    var diag = Diagnostics{ .arg = "title", .name = "post" };
    try printDiagErrorTo(&aw.writer, &diag, error.MissingPositional);
    const out = try aw.toOwnedSlice();
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "error: missing positional argument: 'title'") != null);
}
