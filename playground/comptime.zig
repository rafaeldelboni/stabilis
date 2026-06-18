const std = @import("std");

// ============================================================================
// Comptime playground — step toward a declarative CLI arg parser.
//
// Run it:   zig run playground/comptime.zig
//
// Each `lessonN_*` is one rung on the ladder. Steps 1 and 2 are worked
// examples: READ them, RUN the file, see what prints. Step 3 is YOUR TURN.
// ============================================================================

// A stand-in for one of your real arg structs (models.BuildArgs). We keep a
// copy here so the playground is self-contained and you can poke at it freely.
const BuildArgs = struct {
    source: ?[]const u8 = null,
    destination: ?[]const u8 = null,
    build_drafts: bool = false,
    minify: bool = false,
    port: u16 = 1313,
};

// --- Step 4 scaffolding -----------------------------------------------------
// One row of the declarative spec. Instead of hand-writing parse logic per
// flag, we describe each flag as DATA: its names, which result field it targets,
// and the help text. This struct is the "schema" for a flag.
const Flag = struct {
    long: []const u8, //   e.g. "--dest"
    short: []const u8, //  e.g. "-d"
    field: []const u8, //  must match a field name in BuildArgs (e.g. "destination")
    help: []const u8, //   description shown in --help
};

// The spec table: a plain array of Flag values, known at comptime. This is the
// declarative core of your idea — adding a flag later means adding a row here,
// nothing else. (`source` isn't listed: it's a positional arg, not a flag.)
const build_flags = [_]Flag{
    .{ .long = "--dest", .short = "-d", .field = "destination", .help = "Output directory" },
    .{ .long = "--drafts", .short = "-D", .field = "build_drafts", .help = "Include draft content" },
    .{ .long = "--minify", .short = "-m", .field = "minify", .help = "Minify the output" },
    .{ .long = "--port", .short = "-p", .field = "port", .help = "Port to serve on" },
};

// ----------------------------------------------------------------------------
// Lesson 1 — A *type* is a value (at comptime).
//
// In Zig, `type` is itself a type, and a specific type like `u32` is a value
// of it. You can store it in a `const`, pass it to a function, return it. The
// catch: this only works at compile time. That's the whole game — "comptime"
// just means "the compiler evaluates this while building, not at runtime".
// ----------------------------------------------------------------------------
fn lesson1_typesAreValues() void {
    const T = u32; // T is a const whose *value* is the type u32.
    std.debug.print("[1] T is '{s}', {d} bits wide\n", .{ @typeName(T), @bitSizeOf(T) });

    // @TypeOf gives you the type of any expression, as a value:
    const x: i8 = 42;
    std.debug.print("[1] @TypeOf(x) = {s}\n", .{@typeName(@TypeOf(x))});
}

// ----------------------------------------------------------------------------
// Lesson 2 — Reflect over a struct's fields with @typeInfo + inline for.
//
// @typeInfo(T) returns a std.builtin.Type — a tagged union describing T. For a
// struct, the payload lives under `.@"struct"` (quoted because `struct` is a
// keyword). `.fields` is a comptime slice; each element has `.name` and `.type`.
//
// Why `inline for` and not a normal `for`? Because each field has a DIFFERENT
// type, the loop body must be specialized per-iteration at compile time. A
// regular runtime `for` can't do that. `inline for` unrolls the loop at comptime
// so each iteration is its own little block with `field` known concretely.
// ----------------------------------------------------------------------------
fn lesson2_reflect() void {
    const fields = @typeInfo(BuildArgs).@"struct".fields;
    std.debug.print("[2] BuildArgs has {d} fields:\n", .{fields.len});
    inline for (fields) |field| {
        std.debug.print("      {s}: {s}\n", .{ field.name, @typeName(field.type) });
    }
}

// ----------------------------------------------------------------------------
// Lesson 3 — YOUR TURN: read field *values* by name with @field.
//
// `@field(value, "name")` is like `value.name`, except the name is a comptime
// string. Combined with the `inline for` from lesson 2, you can walk an actual
// INSTANCE and print every field's value — without naming any field by hand.
//
// GOAL: make this print something like:
//      [3] source = null
//      [3] destination = out
//      [3] build_drafts = true
//      [3] minify = false
//      [3] port = 8080
//
// HINTS:
//   - Reuse `@typeInfo(BuildArgs).@"struct".fields` + `inline for`.
//   - Inside the loop:  const value = @field(args, field.name);
//   - The fields have different types (?[]const u8, bool, u16). The `{any}`
//     format specifier prints any type, so `{s} = {any}` is a fine start.
//   - `field.name` is the string; print it with `{s}`.
// ----------------------------------------------------------------------------
fn lesson3_readValues(args: BuildArgs) void {
    const fields = @typeInfo(@TypeOf(args)).@"struct".fields;

    inline for (fields) |field| {
        const value = @field(args, field.name);
        if (field.type == ?[]const u8 or field.type == []const u8)
            std.debug.print("[3] {s}: {?s}\n", .{ field.name, value })
        else
            std.debug.print("[3] {s}: {any}\n", .{ field.name, value });
    }
}

// ----------------------------------------------------------------------------
// Lesson 4 — YOUR TURN: generate --help by looping the spec table.
//
// You've looped over a struct's *fields* (lesson 2-3). Now loop over the
// *spec* — `build_flags` — and print a help line per flag. This is the first
// standalone piece of your original goal: help text driven by metadata.
//
// GOAL: print something like
//      [4] build flags:
//          -d, --dest    Output directory
//          -D, --drafts  Include draft content
//          -m, --minify  Minify the output
//          -p, --port    Port to serve on
//
// HINTS:
//   - Loop:  for (build_flags) |flag| { ... }
//   - Each `flag` has .short, .long, .help — all []const u8, print with {s}.
//   - Don't worry about perfect column alignment; a couple of spaces is fine.
//
// THINK (we'll discuss): in lesson 2 you NEEDED `inline for`. Here a plain
// runtime `for` works too. Why? What's different about the elements you're
// looping over? Try `for` first; try `inline for` and see it still works.
// ----------------------------------------------------------------------------
fn lesson4_help() void {
    std.debug.print("[4] build flags:\n", .{});
    inline for (build_flags) |flag| {
        std.debug.print("    {s}, {s: <8} {s}\n", .{ flag.short, flag.long, flag.help });
    }
}

pub fn main() void {
    lesson1_typesAreValues();
    std.debug.print("\n", .{});
    lesson2_reflect();
    std.debug.print("\n", .{});

    // A sample instance with a few non-default values, for lesson 3 to inspect.
    const sample: BuildArgs = .{ .destination = "out", .build_drafts = true, .port = 8080 };
    lesson3_readValues(sample);
    std.debug.print("\n", .{});

    lesson4_help();
}
