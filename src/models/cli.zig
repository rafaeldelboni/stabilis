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

/// A collection of flags bound to a result struct.
pub const FlagsSpec = struct {
    Result: type,
    items: []const Flag,
};

/// A collection of commands bound to a result union.
pub const CommandsSpec = struct {
    Result: type,
    items: []const Command,
};

/// The full CLI definition: shared flags and an optional command tree.
pub const Cli = struct {
    flags: FlagsSpec,
    commands: ?CommandsSpec = null,
};
