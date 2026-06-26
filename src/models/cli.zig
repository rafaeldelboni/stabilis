/// A single CLI flag definition with long/short forms and field binding.
pub const Flag = struct {
    long: []const u8,
    short: []const u8,
    field: []const u8,
    /// Suppresses required-positional errors regardless of missing args.
    terminal: bool = false,
    help: []const u8,
};

/// Flags and positionals for a leaf command.
pub const CommandOptions = struct {
    Result: type,
    flags: []const Flag,
    positionals: []const []const u8,
};

/// Either a leaf command or a group of subcommands.
const CommandBody = union(enum) {
    command: CommandOptions,
    sub_commands: []const Command,
};

/// A named command entry in the CLI tree.
pub const Command = struct {
    name: []const u8,
    body: CommandBody,
    help: []const u8,
};

/// Carries the offending arg and command name on a parse error.
pub const Diagnostics = struct {
    arg: []const u8 = "",
    name: []const u8 = "",
};

/// The full CLI definition: result types, global flags, and command tree.
pub const Cli = struct {
    ResultT: type,
    GlobalResultT: type,
    global_flags: []const Flag,
    commands: []const Command,
};
