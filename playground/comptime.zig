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

// --- Step 6.1 scaffolding ---------------------------------------------------
// A second model (mirrors your real models.NewPostArgs) that exercises the
// three EXTRAS BuildArgs can't: a required positional, a list flag, and the
// attached --flag=value form. Your same generic parser should handle both.
const PostArgs = struct {
    title: []const u8 = "", //          required positional ("" means "not given")
    description: ?[]const u8 = null, //  optional value flag (string)
    tags: []const []const u8 = &.{}, //  list flag: comma-split + repeatable (needs arena)
    draft: bool = false, //              switch
};
const post_flags = [_]Flag{
    .{ .long = "--desc", .short = "-d", .field = "description", .help = "Short description" },
    .{ .long = "--tags", .short = "-t", .field = "tags", .help = "Comma-separated tags" },
    .{ .long = "--draft", .short = "-D", .field = "draft", .help = "Mark as draft" },
};
// Positional fields, in command-line order. This is one answer to "how does the
// parser know which field is positional?": pass the field name(s) as comptime
// data, same idea as the flag spec.
const post_positionals = [_][]const u8{"title"};

// --- Step 7 + 8 scaffolding -------------------------------------------------
// STEP 7: bind a result type to ALL its metadata in one descriptor, flags
// inlined so everything for a command is visible in one place. `Result` is a
// struct field whose VALUE is a type (lesson 1, leveled up).
const CommandSpec = struct {
    Result: type,
    flags: []const Flag,
    positionals: []const []const u8,
};

// (These inline the flag arrays. In a real port the spec is the single source
// of truth and the standalone build_flags/post_flags above go away — they only
// stay here so steps 4-6 keep working unchanged.)
const build_spec = CommandSpec{
    .Result = BuildArgs,
    .flags = &.{
        .{ .long = "--dest", .short = "-d", .field = "destination", .help = "Output directory" },
        .{ .long = "--drafts", .short = "-D", .field = "build_drafts", .help = "Include draft content" },
        .{ .long = "--minify", .short = "-m", .field = "minify", .help = "Minify the output" },
        .{ .long = "--port", .short = "-p", .field = "port", .help = "Port to serve on" },
    },
    .positionals = &.{"source"},
};
const post_spec = CommandSpec{
    .Result = PostArgs,
    .flags = &.{
        .{ .long = "--desc", .short = "-d", .field = "description", .help = "Short description" },
        .{ .long = "--tags", .short = "-t", .field = "tags", .help = "Comma-separated tags" },
        .{ .long = "--draft", .short = "-D", .field = "draft", .help = "Mark as draft" },
    },
    .positionals = &.{"title"},
};

// STEP 8: the orchestrator. Each command parses to a DIFFERENT type, so the
// result is a tagged union — and (the linchpin) each tag NAME equals a command
// name. This is the playground stand-in for your real models.Command.
const Command = union(enum) {
    build: BuildArgs,
    post: PostArgs,
};
const NamedCommand = struct { name: []const u8, spec: CommandSpec, help: []const u8 };
const commands = [_]NamedCommand{
    .{ .name = "build", .spec = build_spec, .help = "Build the site" },
    .{ .name = "post", .spec = post_spec, .help = "Scaffold new post"  },
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
    next_arg: while (i < args.len) : (i += 1) {
        // var flag_found = false;
        const arg = args[i];
        inline for (flags) |flag| {
            if (std.mem.eql(u8, arg, flag.long) or std.mem.eql(u8, arg, flag.short)) {
                const FieldT = @FieldType(T, flag.field);
                if (FieldT == bool) {
                    @field(result, flag.field) = true;
                } else {
                    if (i + 1 >= args.len) return error.MissingValue;

                    const raw = args[i + 1];
                    if (raw.len > 1 and raw[0] == '-' and !std.mem.eql(u8, raw, "--"))
                        return error.MissingValue;

                    i += 1;
                    switch (@typeInfo(FieldT)) {
                        .int => @field(result, flag.field) = try std.fmt.parseInt(FieldT, raw, 10),
                        else => @field(result, flag.field) = raw, // string-ish
                    }
                }
                continue :next_arg;
            }
        }
        return error.UnknownFlag;
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

// ----------------------------------------------------------------------------
// Lesson 6.1 — THE EXTRAS: positional args, list flags, attached --flag=value.
//
// Grow your step-6 parser into `lesson6_1_parse` (kept separate so step 6 stays
// as a clean reference). Two new params appear in the signature:
//   - comptime positionals: []const []const u8   (field names, in CLI order)
//   - arena: *std.heap.ArenaAllocator            (list flags allocate)
//
// THE THREE EXTRAS:
//
// (a) ATTACHED FORM  --desc=hi  /  -d=hi
//     Only the *match* changes. Before falling back to args[i+1], look for '='
//     in the token: if std.mem.indexOfScalar(u8, arg, '=') |eq|, and arg[0..eq]
//     equals flag.long/short, then the value is arg[eq+1..] (don't advance i).
//     bool flags ignore any '=' . The assignment logic afterwards is unchanged.
//
// (b) POSITIONAL  (the `title`)
//     A token that matched NO flag and does not start with '-' is a positional.
//     Assign it to positionals[pos_index] (a comptime name -> @field), then
//     pos_index += 1. After the loop, a positional whose field type is NOT
//     optional and is still "" was required and missing -> error.MissingPositional.
//     (Reuse the @typeInfo(...) == .optional check from before to tell required
//     from optional.) A '-'-leading token that matched nothing is still UnknownFlag.
//
// (c) LIST FLAG  --tags a,b  (repeatable, comma-split)  type []const []const u8
//     Detect with `FieldT == []const []const u8`. The field is a non-growable
//     slice, so accumulate in the arena: split the value on ',' (trim spaces,
//     drop empties) and CONCAT onto the existing slice, so repeats accumulate:
//        @field(result, flag.field) =
//            try concat(arena, @field(result, flag.field), try split(arena, raw));
//     You'll write small `split` and `concat` helpers (your real appendSplit is
//     the model; std.ArrayList(...).empty + append(allocator, x), then arena.alloc
//     + @memcpy for concat).
//
// SELF-CHECK (VERIFIED — match this exactly once implemented):
//
//   [6.1] case 0: Hello World -t zig,clojure --draft
//   [6.1] title: Hello World
//   [6.1] description: null
//   [6.1] tags: [zig, clojure]
//   [6.1] draft: true
//   [6.1] case 1: Hello --desc=A short note -t zig -t clojure
//   [6.1] title: Hello
//   [6.1] description: A short note
//   [6.1] tags: [zig, clojure]
//   [6.1] draft: false
//   [6.1] case 2: Post -d=hi --tags=a,b,c
//   [6.1] title: Post
//   [6.1] description: hi
//   [6.1] tags: [a, b, c]
//   [6.1] draft: false
//   [6.1] case 3: T -t a, b ,,c
//   [6.1] title: T
//   [6.1] description: null
//   [6.1] tags: [a, b, c]
//   [6.1] draft: false
//   [6.1] case 4: -D
//       -> error: MissingPositional
//   [6.1] case 5: Title --bogus
//       -> error: UnknownFlag
//
// What each case pins down: 0 = positional + comma list + switch; 1 = attached
// long form + repeated -t accumulates; 2 = attached short form + attached list;
// 3 = list trims spaces and drops empty items ("a, b ,,c" -> a,b,c); 4 = missing
// required positional errors; 5 = unknown flag still errors.
// ----------------------------------------------------------------------------
fn splitIntoSlice(arena: *std.heap.ArenaAllocator, comptime T: type, buffer: []const T, delimiter: T) ![]const []const T {
    const allocator = arena.allocator();
    var list: std.ArrayList([]const T) = .empty;
    var it = std.mem.splitScalar(T, buffer, delimiter);
    while (it.next()) |chunk| {
        try list.append(allocator, std.mem.trim(T, chunk, " "));
    }
    return list.toOwnedSlice(allocator) catch unreachable;
}

fn parseFields(
    arena: *std.heap.ArenaAllocator,
    comptime T: type,
    comptime flag: Flag,
    value: []const u8,
) !@FieldType(T, flag.field) {
    const FieldT = @FieldType(T, flag.field);
    return switch (@typeInfo(FieldT)) {
        .bool => std.mem.eql(u8, value, "true"),
        .int => try std.fmt.parseInt(FieldT, value, 10),
        .pointer => |info| if (info.size == .slice and @typeInfo(info.child) == .pointer)
            try splitIntoSlice(arena, @typeInfo(info.child).pointer.child, value, ',')
        else
            value,
        else => value,
    };
}

// fn matchFlag(
//     arena: *std.heap.ArenaAllocator,
//     comptime T: type,
//     comptime flags: []const Flag,
//     args: []const []const u8,
//     arg: []const u8,
//     i: *usize,
//     result: *T,
// ) !bool {
//     inline for (flags) |flag| {
//         if (std.mem.eql(u8, arg, flag.long) or std.mem.eql(u8, arg, flag.short)) {
//             const FieldT = @FieldType(T, flag.field);
//             if (@typeInfo(FieldT) == .bool) {
//                 @field(result, flag.field) = true;
//                 return true;
//             }
//             if (i + 1 >= args.len) return error.MissingValue;
//
//             const raw = args[i + 1];
//             if (raw.len > 1 and raw[0] == '-' and !std.mem.eql(u8, raw, "--"))
//                 return error.MissingValue;
//
//             i += 1;
//             @field(result, flag.field) = try parseFields(arena, T, flag, raw);
//
//             return true;
//         } else if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
//             const head = arg[0..eq];
//             if (std.mem.eql(u8, head, flag.long) or std.mem.eql(u8, head, flag.short)) {
//                 const raw = arg[eq + 1 ..];
//                 @field(result, flag.field) = try parseFields(arena, T, flag, raw);
//                 return true;
//             }
//         }
//     }
//     return false;
// }

fn lesson6_1_parse(
    arena: *std.heap.ArenaAllocator,
    comptime T: type,
    comptime flags: []const Flag,
    comptime positionals: []const []const u8,
    args: []const []const u8,
) !T {
    var result: T = .{};
    var i: usize = 0;
    var pos_idx: usize = 0;
    next_arg: while (i < args.len) : (i += 1) {
        const arg = args[i];
        inline for (flags) |flag| {
            if (std.mem.eql(u8, arg, flag.long) or std.mem.eql(u8, arg, flag.short)) {
                const FieldT = @FieldType(T, flag.field);
                if (@typeInfo(FieldT) == .bool) {
                    @field(result, flag.field) = true;
                    continue :next_arg;
                }
                if (i + 1 >= args.len) return error.MissingValue;

                const raw = args[i + 1];
                if (raw.len > 1 and raw[0] == '-' and !std.mem.eql(u8, raw, "--"))
                    return error.MissingValue;

                i += 1;
                @field(result, flag.field) = try parseFields(arena, T, flag, raw);

                continue :next_arg;
            } else if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
                const head = arg[0..eq];
                if (std.mem.eql(u8, head, flag.long) or std.mem.eql(u8, head, flag.short)) {
                    const raw = arg[eq + 1 ..];
                    @field(result, flag.field) = try parseFields(arena, T, flag, raw);
                    continue :next_arg;
                }
            }
        }

        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;

        inline for (positionals, 0..) |pos, j| {
            if (j == pos_idx) {
                @field(result, pos) = arg;
                pos_idx += 1;
                continue :next_arg;
            }
        }

        return error.TooManyPositionals;
    }

    inline for (positionals, 0..) |pos, j| {
        if (j >= pos_idx) {
            const FieldT = @FieldType(T, pos);
            if (@typeInfo(FieldT) != .optional) return error.MissingPositional;
        }
    }
    return result;
}

// Self-check harness (already written — you only implement lesson6_1_parse).
// `printPost` is just a readable printer for PostArgs (tags joined with ", ").
fn printPost(a: PostArgs) void {
    std.debug.print("[6.1] title: {s}\n", .{a.title});
    std.debug.print("[6.1] description: {?s}\n", .{a.description});
    std.debug.print("[6.1] tags: [", .{});
    for (a.tags, 0..) |t, idx| {
        if (idx != 0) std.debug.print(", ", .{});
        std.debug.print("{s}", .{t});
    }
    std.debug.print("]\n", .{});
    std.debug.print("[6.1] draft: {}\n", .{a.draft});
}

fn lesson6_1_demo() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const cases = [_][]const []const u8{
        &.{ "Hello World", "-t", "zig,clojure", "--draft" },
        &.{ "Hello", "--desc=A short note", "-t", "zig", "-t", "clojure" },
        &.{ "Post", "-d=hi", "--tags=a,b,c" },
        &.{ "T", "-t", "a, b ,,c" },
        &.{"-D"},
        &.{ "Title", "--bogus" },
    };
    for (cases, 0..) |input, n| {
        std.debug.print("[6.1] case {d}:", .{n});
        for (input) |a| std.debug.print(" {s}", .{a});
        std.debug.print("\n", .{});
        const result = lesson6_1_parse(&arena, PostArgs, &post_flags, &post_positionals, input) catch |err| {
            std.debug.print("    -> error: {s}\n", .{@errorName(err)});
            continue;
        };
        printPost(result);
    }
}

// ----------------------------------------------------------------------------
// Lesson 7 + 8 — bundle the spec, then orchestrate command selection.
//
// Prereq: finish 6.1 first — lesson7_parse IS your 6.1 parser, just repackaged.
//
// STEP 7 — lesson7_parse(comptime spec: CommandSpec, arena, args) !spec.Result
//   Take your finished lesson6_1_parse body and substitute:
//       T            -> spec.Result
//       flags        -> spec.flags
//       positionals  -> spec.positionals
//   Note `spec.Result` is used BOTH as a type (`var result: spec.Result = .{}`)
//   and as the return type (`!spec.Result`) — a return type read off the arg.
//   Nothing else changes; the parsing logic is identical.
//
// STEP 8 — lesson8_dispatch(arena, args) !Command
//   Pick the command from args[0], parse the rest, wrap in the union:
//     1. if (args.len == 0) return error.NoCommand;
//     2. const name = args[0];
//     3. inline for (commands) |cmd| {            // inline: cmd.name/cmd.spec must be comptime
//            if (std.mem.eql(u8, name, cmd.name))
//                return @unionInit(Command, cmd.name, try lesson7_parse(cmd.spec, arena, args[1..]));
//        }
//     4. return error.UnknownCommand;
//
//   THE NEW BUILTIN: @unionInit(UnionType, comptime tag_name, value) builds the
//   union variant whose tag NAME is `tag_name` — the union analog of @field for
//   structs. It works here only because each command name string is also a tag
//   name in `Command` ("build" -> .build). That string-equals-tag coupling is
//   the whole trick, exactly like flag.field matching a struct field name.
//
// `printCommand` consumes the union with a switch + payload capture, handing each
// variant to the printer you already wrote (so build rows show "[3]", post "[6.1]").
//
// SELF-CHECK (VERIFIED — match once 7 and 8 are implemented):
//
//   [7/8] case 0: build content -d out --minify
//       -> .build
//   [3] source: content
//   [3] destination: out
//   [3] build_drafts: false
//   [3] minify: true
//   [3] port: 1313
//   [7/8] case 1: post Hello World -t zig,clojure --draft
//       -> .post
//   [6.1] title: Hello World
//   [6.1] description: null
//   [6.1] tags: [zig, clojure]
//   [6.1] draft: true
//   [7/8] case 2: post Hi --desc=quick -t a,b
//       -> .post
//   [6.1] title: Hi
//   [6.1] description: quick
//   [6.1] tags: [a, b]
//   [6.1] draft: false
//   [7/8] case 3: build --port 8080
//       -> .build
//   [3] source: null
//   [3] destination: null
//   [3] build_drafts: false
//   [3] minify: false
//   [3] port: 8080
//   [7/8] case 4: deploy
//       -> error: UnknownCommand
//   [7/8] case 5: build --bogus
//       -> error: UnknownFlag
//
// (In the demo, args[0] is the command itself. Your real cli.zig skips argv[0]
// the program name, so it dispatches on args[1] and parses args[2..].)
//
// EXTENSIONS toward the real models.Command: tag-only commands (`help`,
// `version`) that carry no spec, and a nested level (`new post` / `new page`)
// where a command entry holds another command table instead of a spec.
// ----------------------------------------------------------------------------
fn lesson7_parse(
    arena: *std.heap.ArenaAllocator,
    comptime spec: CommandSpec,
    args: []const []const u8,
) !spec.Result {

    // TODO: port your lesson6_1_parse body (T->spec.Result, flags->spec.flags,
    //       positionals->spec.positionals). Returns defaults for now.
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
                if (i + 1 >= args.len) return error.MissingValue;

                const raw = args[i + 1];
                if (raw.len > 1 and raw[0] == '-' and !std.mem.eql(u8, raw, "--"))
                    return error.MissingValue;

                i += 1;
                @field(result, flag.field) = try parseFields(arena, spec.Result, flag, raw);

                continue :next_arg;
            } else if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
                const head = arg[0..eq];
                if (std.mem.eql(u8, head, flag.long) or std.mem.eql(u8, head, flag.short)) {
                    const raw = arg[eq + 1 ..];
                    @field(result, flag.field) = try parseFields(arena, spec.Result, flag, raw);
                    continue :next_arg;
                }
            }
        }

        if (arg.len > 0 and arg[0] == '-') return error.UnknownFlag;

        inline for (spec.positionals, 0..) |pos, j| {
            if (j == pos_idx) {
                @field(result, pos) = arg;
                pos_idx += 1;
                continue :next_arg;
            }
        }

        return error.TooManyPositionals;
    }

    inline for (spec.positionals, 0..) |pos, j| {
        if (j >= pos_idx) {
            const FieldT = @FieldType(spec.Result, pos);
            if (@typeInfo(FieldT) != .optional) return error.MissingPositional;
        }
    }
    return result;
}

fn lesson8_dispatch(arena: *std.heap.ArenaAllocator, args: []const []const u8) !Command {
    if (args.len == 0) return error.NoCommand;
    const name = args[0];
    inline for (commands) |cmd| {
        if (std.mem.eql(u8, name, cmd.name))
            return @unionInit(Command, cmd.name, try lesson7_parse(arena, cmd.spec, args[1..]));
    }
    return error.UnknownCommand;
}

// Harness: consume the union and route each variant to its existing printer.
fn printCommand(cmd: Command) void {
    switch (cmd) {
        .build => |b| lesson3_readValues(b),
        .post => |p| printPost(p),
    }
}

fn lesson78_demo() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const cases = [_][]const []const u8{
        &.{ "build", "content", "-d", "out", "--minify" },
        &.{ "post", "Hello World", "-t", "zig,clojure", "--draft" },
        &.{ "post", "Hi", "--desc=quick", "-t", "a,b" },
        &.{ "build", "--port", "8080" },
        &.{"deploy"},
        &.{ "build", "--bogus" },
    };
    for (cases, 0..) |input, n| {
        std.debug.print("[7/8] case {d}:", .{n});
        for (input) |a| std.debug.print(" {s}", .{a});
        std.debug.print("\n", .{});
        const cmd = lesson8_dispatch(&arena, input) catch |err| {
            std.debug.print("    -> error: {s}\n", .{@errorName(err)});
            continue;
        };
        std.debug.print("    -> .{s}\n", .{@tagName(cmd)});
        printCommand(cmd);
    }
}

pub fn main() void {
    // lesson1_typesAreValues();
    // std.debug.print("\n", .{});
    // lesson2_reflect();
    // std.debug.print("\n", .{});
    //
    // // A sample instance with a few non-default values, for lesson 3 to inspect.
    // const sample: BuildArgs = .{ .destination = "out", .build_drafts = true, .port = 8080 };
    // lesson3_readValues(sample);
    // std.debug.print("\n", .{});
    //
    // lesson4_help();
    // std.debug.print("\n", .{});
    //
    // lesson5_describe();
    // std.debug.print("\n", .{});
    //
    // lesson6_demo();
    // std.debug.print("\n", .{});

    // lesson6_1_demo();
    // std.debug.print("\n", .{});

    lesson78_demo();
}
