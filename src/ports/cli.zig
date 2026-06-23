const std = @import("std");

const models = @import("../models.zig");
const adapters = @import("../adaters/cli.zig");
const Command = models.Command;
const NamedCommand = models.NamedCommand;
const CommandSpec = models.CommandSpec;

fn printCommandHelp(cmd_spec: CommandSpec) void {
    std.debug.print("Options:\n", .{});
    inline for (cmd_spec.flags) |flag| {
        const FieldT = @FieldType(cmd_spec.Result, flag.field);
        const kind = switch (adapters.parseFieldTypes(FieldT)) {
            .list_of_strings => "string array",
            else => @tagName(adapters.parseFieldTypes(FieldT)),
        };
        std.debug.print("    {s}, {s: <9} {s: <14} [{s}]\n", .{
            flag.short,
            flag.long,
            flag.help,
            kind,
        });
    }
}

fn printHelpGeneral(comptime commands: []const NamedCommand) void {
    std.debug.print("stabilis <command>\n\nCommands:\n", .{});
    inline for (commands) |cmd| {
        std.debug.print("    {s: <10} {s}\n", .{ cmd.name, cmd.help });
        switch (cmd.spec) {
            .sub_commands => |sub_commands| {
                inline for (sub_commands) |sub_cmd| {
                    std.debug.print("      {s: <8} {s}\n", .{ sub_cmd.name, sub_cmd.help });
                }
            },
            else => {},
        }
    }
}

pub fn printHelp(
    args: []const []const u8,
    comptime commands: []const NamedCommand,
    comptime maybe_cmd: ?NamedCommand,
) void {
    if (maybe_cmd == null) {
        if (args.len == 0) {
            printHelpGeneral();
            return;
        }
        const name = args[0];
        inline for (commands) |cmd| {
            const matched = switch (cmd.spec) {
                .tag_only => adapters.matchTagAlias(name, cmd.name),
                else => std.mem.eql(u8, name, cmd.name),
            };
            if (matched) {
                printHelp(args[1..], cmd);
                return;
            }
        }

        printHelpGeneral();
        return;
    }
    const cmd = maybe_cmd.?;
    switch (cmd.spec) {
        .tag_only => {},
        .command => |spec| {
            std.debug.print("stabilis {s}", .{cmd.name});
            for (spec.positionals) |a| std.debug.print(" [{s}]", .{a});
            std.debug.print("\n\n{s}\n\n", .{cmd.help});
            printCommandHelp(spec);
        },
        .sub_commands => |sub_cmds| {
            if (args.len == 0) {
                std.debug.print("stabilis {s} <subcommand>\n\n{s}\n\nSubcommands:\n", .{ cmd.name, cmd.help });
                inline for (sub_cmds) |sub_cmd| {
                    std.debug.print("    {s: <10} {s}\n", .{ sub_cmd.name, sub_cmd.help });
                }
                return;
            }
            const sub_name = args[0];
            inline for (sub_cmds) |sub_cmd| {
                if (std.mem.eql(u8, sub_name, sub_cmd.name)) {
                    printHelp(args[1..], sub_cmd);
                    return;
                }
            }
            std.debug.print("unknown subcommand: {s}\n", .{sub_name});
        },
    }
}

// fn handleCommand(cmd: Command) void {
//     switch (cmd) {
//         .build => |b| buildFn(b),
//         .post => |p| newPostFn(p),
//         .page => |p| newPageFn(p),
//         .version => |p| std.debug.print("[9] version: {any}\n", .{p}),
//         .help => |p| std.debug.print("[9] help: {any}\n", .{p}),
//     }
// }
