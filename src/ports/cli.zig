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
    try w.print("stabilis <command>\n\nCommands:\n", .{});
    inline for (cli.commands) |cmd| {
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
    if (cli.global_flags.len > 0) {
        try w.print("\nGlobal options:\n", .{});
        try printFlags(w, cli.GlobalResultT, cli.global_flags);
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
        inline for (cli.commands) |cmd| {
            if (std.mem.eql(u8, name, cmd.name)) {
                try printHelpImpl(w, args[1..], cli, cmd);
                return;
            }
        }

        try printHelpGeneral(w, cli);
        return;
    }
    const cmd = maybe_cmd.?;
    switch (cmd.body) {
        .command => |spec| {
            try w.print("stabilis {s}", .{cmd.name});
            for (spec.positionals) |a| try w.print(" [{s}]", .{a});
            try w.print("\n\n{s}\n\nOptions:\n", .{cmd.help});
            try printFlags(w, spec.Result, spec.flags);
            try printFlags(w, cli.GlobalResultT, cli.global_flags);
        },
        .sub_commands => |sub_cmds| {
            if (args.len == 0) {
                try w.print("stabilis {s} <subcommand>\n\n{s}\n\nSubcommands:\n", .{ cmd.name, cmd.help });
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

const test_models = @import("../models.zig");

fn captureHelp(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    try printHelpTo(&aw.writer, args, test_models.stabilis_cli);
    return try aw.toOwnedSlice();
}

test "printHelp general shows commands and global options" {
    const out = try captureHelp(std.testing.allocator, &.{ "stabilis", "--help" });
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "stabilis <command>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Commands:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "serve") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "new") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Global options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--help") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--version") != null);
}

test "printHelp build shows flags and globals" {
    const out = try captureHelp(std.testing.allocator, &.{ "stabilis", "build", "--help" });
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "stabilis build [source]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Build the site") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--dest") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--build-drafts") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--minify") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--clear-dir") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--help") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--version") != null);
}

test "printHelp new shows subcommands" {
    const out = try captureHelp(std.testing.allocator, &.{ "stabilis", "new", "--help" });
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "stabilis new <subcommand>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Subcommands:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "post") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "page") != null);
}

test "printHelp new post shows flags and globals" {
    const out = try captureHelp(std.testing.allocator, &.{ "stabilis", "new", "post", "--help" });
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "stabilis post [title]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Scaffold new post") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--desc") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--tags") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--draft") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--help") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--version") != null);
}

test "printDiagError formats error message" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    var diag = Diagnostics{ .arg = "delbongo", .name = "" };
    try printDiagErrorTo(&aw.writer, &diag, error.UnknownCommand);
    const out = try aw.toOwnedSlice();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "error: unknown command: 'delbongo'") != null);
}

test "printDiagError missing positional" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    var diag = Diagnostics{ .arg = "title", .name = "post" };
    try printDiagErrorTo(&aw.writer, &diag, error.MissingPositional);
    const out = try aw.toOwnedSlice();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "error: missing positional argument: 'title'") != null);
}