pub const Flag = struct {
    long: []const u8,
    short: []const u8,
    field: []const u8,
    help: []const u8,
};

pub const CommandSpec = struct {
    Result: type,
    flags: []const Flag,
    positionals: []const []const u8,
};

const Spec = union(enum) {
    command: CommandSpec,
    sub_commands: []const NamedCommand,
    tag_only,
};

pub const NamedCommand = struct {
    name: []const u8,
    spec: Spec,
    help: []const u8,
};

pub const Diagnostics = struct {
    arg: []const u8 = "",
    name: []const u8 = "",
};

pub const Command = struct {
    ReturnT: type,
    commands: []const NamedCommand,
};
