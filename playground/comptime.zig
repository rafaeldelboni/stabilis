const std = @import("std");

//  Here's the ladder I'm proposing to get from your hand-written parser to the declarative one:
//
//  ┌──────┬─────────────────────────────────────────┬───────────────────────────────────────────────────────────────────┐
//  │ Step │                 Concept                 │                Why you need it for the arg parser                 │
//  ├──────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
//  │ 1    │ Types are values at comptime            │ The spec/result struct gets passed around as a value              │
//  ├──────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
//  │ 2    │ @typeInfo + inline for over fields      │ Loop over a struct's fields instead of writing each by hand       │
//  ├──────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
//  │ 3    │ @field(x, name) read/write by name      │ Set result.destination when name is just a string                 │
//  ├──────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
//  │ 4    │ A declarative spec table (anon structs) │ .{ .long="--dest", .short="-d", .field="destination", .help=... } │
//  ├──────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
//  │ 5    │ Generate --help from the spec           │ The metadata payoff                                               │
//  ├──────┼─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
//  │ 6    │ Generic fill(result, spec, args)        │ Replace all four parseXArgs with one function                     │
//  └──────┴─────────────────────────────────────────┴───────────────────────────────────────────────────────────────────┘

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
    for (build_flags) |flag| {
        std.debug.print("    {s}, {s: <8} {s}\n", .{ flag.short, flag.long, flag.help });
    }
}

// ----------------------------------------------------------------------------
// Lesson 5 — YOUR TURN: let the field's TYPE decide the flag's behavior.
//
// Step 4 looped the spec and printed help. Now connect spec -> result struct:
// for each Flag, look up the type of the field it targets in BuildArgs, and
// derive whether the flag is a SWITCH (bool, no value) or TAKES A VALUE.
//
// This is the insight the whole parser rests on: you never *store* "takes a
// value" in the spec — you DERIVE it from the field's type. One source of truth.
//
// GOAL: print something like
//      [5] -d, --dest    takes a value  (?[]const u8)
//      [5] -D, --drafts  switch         (bool)
//      [5] -m, --minify  switch         (bool)
//      [5] -p, --port    takes a value  (u16)
//
// HINTS:
//   - This loop MUST be `inline for` (you just saw why — @FieldType needs a
//     comptime-known name, and flag.field only becomes comptime under `inline`).
//   - const FieldT = @FieldType(BuildArgs, flag.field);
//   - const kind = if (FieldT == bool) "switch" else "takes a value";
//   - Print the field's type name with @typeName(FieldT).
// ----------------------------------------------------------------------------
fn lesson5_describe() void {
    std.debug.print("[5] build flags:\n", .{});
    inline for (build_flags) |flag| {
        const FieldT = @FieldType(BuildArgs, flag.field);
        const field_type_name = @typeName(FieldT);
        const kind = if (FieldT == bool) "switch" else "takes a value";
        std.debug.print("    {s}, {s: <9} {s: <14} ({s})\n", .{ flag.short, flag.long, kind, field_type_name });
    }
}

// ----------------------------------------------------------------------------
// Lesson 6 — THE CAPSTONE (do this one solo): one generic parser.
//
// Everything so far was prep. Now write a SINGLE function that replaces all four
// of your hand-written parseXArgs. It takes the result type, the spec table, and
// the argv slice, and fills a result by walking the args and matching flags.
//
// SIGNATURE (already stubbed below):
//   fn lesson6_parse(comptime T: type, comptime flags: []const Flag,
//                    args: []const []const u8) !T
//
// ALGORITHM:
//   1. var result: T = .{};                 // every field starts at its default
//   2. Walk args with an index `i` (use `while`, not `for` — value flags need to
//      consume the *next* arg by advancing i).
//   3. For each token, `inline for (flags) |flag|` and check if the token equals
//      flag.long or flag.short (std.mem.eql(u8, ...)).
//   4. On a match, look at  const FieldT = @FieldType(T, flag.field);
//        - if (FieldT == bool):  @field(result, flag.field) = true;   // a switch
//        - else:                 it takes a value — grab args[i+1], advance i,
//          return error.MissingValue if there is no next arg, then assign:
//            * switch (@typeInfo(FieldT)) {
//                  .int => @field(result, flag.field) = try std.fmt.parseInt(FieldT, raw, 10),
//                  else => @field(result, flag.field) = raw,   // string-ish
//              }
//   5. If no flag matched the token, return error.UnknownFlag.
//   6. return result;
//
// THE PAYOFF — WHY THIS COMPILES AT ALL:
//   Inside the inline for, `if (FieldT == bool)` is comptime-known, so on a bool
//   field the value-assignment branch (which would be a type error: string into
//   bool) is PRUNED before it's compiled; on a string/int field the `= true`
//   branch is pruned. That dead-branch pruning (lesson 3's deep-dive) is exactly
//   what lets ONE loop body serve fields of every type. That is the whole trick.
//
// SELF-CHECK: `lesson6_demo` below runs your parser on real inputs and prints the
// result via lesson3's printer (so values show with a "[3]" prefix — that's fine).
// You're done when the output matches:
//
//   [6] case 0: --dest out --minify
//   [3] source: null
//   [3] destination: out
//   [3] build_drafts: false
//   [3] minify: true
//   [3] port: 1313
//   [6] case 1: -D -p 8080
//   [3] source: null
//   [3] destination: null
//   [3] build_drafts: true
//   [3] minify: false
//   [3] port: 8080
//   [6] case 2: --bogus
//       -> error: UnknownFlag
//   [6] case 3: -p
//       -> error: MissingValue
//
// EXTENSIONS (not needed to "pass", but this is how you port it to the real
// adapters/cli.zig): positional args like `source`, list flags like tags/menus
// ([]const []const u8, comma-split/repeatable), and the attached `--dest=out`
// form. Each is a small addition on top of this skeleton — try them once the
// base passes.
// ----------------------------------------------------------------------------
fn lesson6_parse(comptime T: type, comptime flags: []const Flag, args: []const []const u8) !T {
    var result: T = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        var flag_found = false;
        const arg = args[i];
        inline for (flags) |flag| {
            if (std.mem.eql(u8, arg, flag.long) or std.mem.eql(u8, arg, flag.short)) {
                const FieldT = @FieldType(T, flag.field);
                if (FieldT == bool) {
                    @field(result, flag.field) = true;
                    flag_found = true;
                } else {
                    if (i + 1 >= args.len) return error.MissingValue;

                    const raw = args[i + 1];
                    if (raw.len > 1 and raw[0] == '-' and !std.mem.eql(u8, raw, "--"))
                        return error.MissingValue;

                    i += 1;
                    switch (@typeInfo(FieldT)) {
                        .int => {
                            @field(result, flag.field) = try std.fmt.parseInt(FieldT, raw, 10);
                            flag_found = true;
                        },
                        else => {
                            @field(result, flag.field) = raw; // string-ish
                            flag_found = true;
                        },
                    }
                }
            }
        }
        if (!flag_found) return error.UnknownFlag;
    }
    return result;
}

// Self-check harness (already written — you only implement lesson6_parse).
fn lesson6_demo() void {
    const cases = [_][]const []const u8{
        &.{ "--dest", "out", "--minify" },
        &.{ "-D", "-p", "8080" },
        &.{"--bogus"},
        &.{"-p"},
    };
    for (cases, 0..) |input, n| {
        std.debug.print("[6] case {d}:", .{n});
        for (input) |a| std.debug.print(" {s}", .{a});
        std.debug.print("\n", .{});
        const result = lesson6_parse(BuildArgs, &build_flags, input) catch |err| {
            std.debug.print("    -> error: {s}\n", .{@errorName(err)});
            continue;
        };
        lesson3_readValues(result);
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
    std.debug.print("\n", .{});

    lesson5_describe();
    std.debug.print("\n", .{});

    lesson6_demo();
}
