const std = @import("std");

const models = @import("../models.zig");
const Command = models.Command;
const ServeArgs = models.ServeArgs;
const BuildArgs = models.BuildArgs;
const NewPostArgs = models.NewPostArgs;
const NewPageArgs = models.NewPageArgs;

fn parseBuildArgs(args: []const []const u8) !BuildArgs {
    _ = args;
    const result: BuildArgs = .{};
    // TODO `stabilis build [source] [-d dest] [-D] [--minify] [--cleanDestinationDir]`
    return result;
}

fn parseServeArgs(args: []const []const u8) !ServeArgs {
    _ = args;
    const result: ServeArgs = .{};
    // TODO `stabilis serve [-p port] [--bind addr] [--open] [-D]`
    return result;
}

fn parseNewPostArgs(args: []const []const u8) !NewPostArgs {
    if (args.len == 0) return error.MissingTitle;
    const result: NewPostArgs = .{ .title = args[0] };
    // TODO `stabilis new post <title> [-d desc] [-t tags] [--draft]`
    return result;
}

fn parseNewPageArgs(args: []const []const u8) !NewPageArgs {
    if (args.len == 0) return error.MissingTitle;
    const result: NewPageArgs = .{ .title = args[0] };
    // TODO `stabilis new page <title> [-s slug] [--draft] [--menus main]`
    return result;
}

pub fn parse(args: []const []const u8) !Command {
    if (args.len <= 1) return .help;
    const command_arg = args[1];
    if (std.mem.eql(u8, command_arg, "help") or
        std.mem.eql(u8, command_arg, "--help") or
        std.mem.eql(u8, command_arg, "-h")) return .help;
    if (std.mem.eql(u8, command_arg, "version") or
        std.mem.eql(u8, command_arg, "--version") or
        std.mem.eql(u8, command_arg, "-v")) return .version;
    if (std.mem.eql(u8, command_arg, "serve"))
        return .{ .serve = try parseServeArgs(args[2..]) };
    if (std.mem.eql(u8, command_arg, "build"))
        return .{ .build = try parseBuildArgs(args[2..]) };
    if (std.mem.eql(u8, command_arg, "new")) {
        if (args.len < 3) return .{ .new = .help };
        const sub = args[2];
        if (std.mem.eql(u8, sub, "post"))
            return .{ .new = .{ .post = try parseNewPostArgs(args[3..]) } };
        if (std.mem.eql(u8, sub, "page"))
            return .{ .new = .{ .page = try parseNewPageArgs(args[3..]) } };
        return .{ .new = .help };
    }
    return error.UnknownCommand;
}

test "parse no args shows help" {
    const parsed = try parse(&.{"stabilis"});
    try std.testing.expectEqual(Command.help, parsed);
}

test "parse 'help' shows help" {
    const parsed = try parse(&.{ "stabilis", "help" });
    try std.testing.expectEqual(Command.help, parsed);
}

test "parse '--help' shows help" {
    const parsed = try parse(&.{ "stabilis", "--help" });
    try std.testing.expectEqual(Command.help, parsed);
}

test "parse '-h' shows help" {
    const parsed = try parse(&.{ "stabilis", "-h" });
    try std.testing.expectEqual(Command.help, parsed);
}

test "parse 'version' shows version" {
    const parsed = try parse(&.{ "stabilis", "version" });
    try std.testing.expectEqual(Command.version, parsed);
}

test "parse '--version' shows version" {
    const parsed = try parse(&.{ "stabilis", "--version" });
    try std.testing.expectEqual(Command.version, parsed);
}

test "parse '-v' shows version" {
    const parsed = try parse(&.{ "stabilis", "-v" });
    try std.testing.expectEqual(Command.version, parsed);
}

test "parse unknown command returns UnknownCommand" {
    try std.testing.expectError(error.UnknownCommand, parse(&.{ "stabilis", "delbongo" }));
}

test "parse 'build' with no flags returns defaults" {
    const parsed = try parse(&.{ "stabilis", "build" });
    try std.testing.expect(parsed == .build);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.build.source);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.build.destination);
    try std.testing.expectEqual(false, parsed.build.build_drafts);
    try std.testing.expectEqual(false, parsed.build.minify);
    try std.testing.expectEqual(false, parsed.build.clean_destination_dir);
    try std.testing.expectEqual(false, parsed.build.help);
}

test "parse 'build' with positional source" {
    const parsed = try parse(&.{ "stabilis", "build", "mycontent" });
    try std.testing.expect(parsed == .build);
    try std.testing.expectEqualStrings("mycontent", parsed.build.source.?);
}

test "parse 'build' with -d destination" {
    const parsed = try parse(&.{ "stabilis", "build", "-d", "out" });
    try std.testing.expectEqualStrings("out", parsed.build.destination.?);
}

test "parse 'build' with --destination destination" {
    const parsed = try parse(&.{ "stabilis", "build", "--destination", "out" });
    try std.testing.expectEqualStrings("out", parsed.build.destination.?);
}

test "parse 'build' with -D builds drafts" {
    const parsed = try parse(&.{ "stabilis", "build", "-D" });
    try std.testing.expectEqual(true, parsed.build.build_drafts);
}

test "parse 'build' with --buildDrafts builds drafts" {
    const parsed = try parse(&.{ "stabilis", "build", "--buildDrafts" });
    try std.testing.expectEqual(true, parsed.build.build_drafts);
}

test "parse 'build' with --minify" {
    const parsed = try parse(&.{ "stabilis", "build", "--minify" });
    try std.testing.expectEqual(true, parsed.build.minify);
}

test "parse 'build' with --cleanDestinationDir" {
    const parsed = try parse(&.{ "stabilis", "build", "--cleanDestinationDir" });
    try std.testing.expectEqual(true, parsed.build.clean_destination_dir);
}

test "parse 'build' with --help sets help flag" {
    const parsed = try parse(&.{ "stabilis", "build", "--help" });
    try std.testing.expectEqual(true, parsed.build.help);
}

test "parse 'build' with combined flags" {
    const parsed = try parse(&.{ "stabilis", "build", "content", "-d", "public", "-D", "--minify" });
    try std.testing.expectEqualStrings("content", parsed.build.source.?);
    try std.testing.expectEqualStrings("public", parsed.build.destination.?);
    try std.testing.expectEqual(true, parsed.build.build_drafts);
    try std.testing.expectEqual(true, parsed.build.minify);
}

test "parse 'build' with unknown flag returns UnknownFlag" {
    try std.testing.expectError(error.UnknownFlag, parse(&.{ "stabilis", "build", "--bogus" }));
}

test "parse 'build' with -d missing value returns MissingValue" {
    try std.testing.expectError(error.MissingValue, parse(&.{ "stabilis", "build", "-d" }));
}

test "parse 'new post' with no title returns MissingTitle" {
    try std.testing.expectError(error.MissingTitle, parse(&.{ "stabilis", "new", "post" }));
}

test "parse 'new post' with title returns post with defaults" {
    const parsed = try parse(&.{ "stabilis", "new", "post", "Hello World" });
    try std.testing.expect(parsed == .new);
    try std.testing.expect(parsed.new == .post);
    try std.testing.expectEqualStrings("Hello World", parsed.new.post.title);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.new.post.description);
    try std.testing.expectEqual(@as(usize, 0), parsed.new.post.tags.len);
    try std.testing.expectEqual(false, parsed.new.post.draft);
    try std.testing.expectEqual(false, parsed.new.post.help);
}

test "parse 'new post' with -d description" {
    const parsed = try parse(&.{ "stabilis", "new", "post", "Hello", "-d", "A description" });
    try std.testing.expectEqualStrings("A description", parsed.new.post.description.?);
}

test "parse 'new post' with --description description" {
    const parsed = try parse(&.{ "stabilis", "new", "post", "Hello", "--description", "A description" });
    try std.testing.expectEqualStrings("A description", parsed.new.post.description.?);
}

test "parse 'new post' with -t single tag" {
    const parsed = try parse(&.{ "stabilis", "new", "post", "Hello", "-t", "zig" });
    try std.testing.expectEqual(@as(usize, 1), parsed.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", parsed.new.post.tags[0]);
}

test "parse 'new post' with -t comma-separated tags" {
    const parsed = try parse(&.{ "stabilis", "new", "post", "Hello", "-t", "zig,clojure" });
    try std.testing.expectEqual(@as(usize, 2), parsed.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", parsed.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", parsed.new.post.tags[1]);
}

test "parse 'new post' with -t repeated tags" {
    const parsed = try parse(&.{ "stabilis", "new", "post", "Hello", "-t", "zig", "-t", "clojure" });
    try std.testing.expectEqual(@as(usize, 2), parsed.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", parsed.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", parsed.new.post.tags[1]);
}

test "parse 'new post' with --tags comma-separated tags" {
    const parsed = try parse(&.{ "stabilis", "new", "post", "Hello", "--tags", "zig,clojure" });
    try std.testing.expectEqual(@as(usize, 2), parsed.new.post.tags.len);
    try std.testing.expectEqualStrings("zig", parsed.new.post.tags[0]);
    try std.testing.expectEqualStrings("clojure", parsed.new.post.tags[1]);
}

test "parse 'new post' with --draft" {
    const parsed = try parse(&.{ "stabilis", "new", "post", "Hello", "--draft" });
    try std.testing.expectEqual(true, parsed.new.post.draft);
}

test "parse 'new post' with --help sets help flag" {
    const parsed = try parse(&.{ "stabilis", "new", "post", "Hello", "--help" });
    try std.testing.expectEqual(true, parsed.new.post.help);
}

test "parse 'new post' with all flags" {
    const parsed = try parse(&.{
        "stabilis", "new",  "post", "Hello World",
        "-d",       "desc", "-t",   "a,b",
        "--draft",
    });
    try std.testing.expectEqualStrings("Hello World", parsed.new.post.title);
    try std.testing.expectEqualStrings("desc", parsed.new.post.description.?);
    try std.testing.expectEqual(@as(usize, 2), parsed.new.post.tags.len);
    try std.testing.expectEqual(true, parsed.new.post.draft);
}

test "parse 'new post' with -t missing value returns MissingValue" {
    try std.testing.expectError(error.MissingValue, parse(&.{ "stabilis", "new", "post", "Hello", "-t" }));
}

test "parse 'new post' with unknown flag returns UnknownFlag" {
    try std.testing.expectError(error.UnknownFlag, parse(&.{ "stabilis", "new", "post", "Hello", "--bogus" }));
}

test "parse 'new page' with no title returns MissingTitle" {
    try std.testing.expectError(error.MissingTitle, parse(&.{ "stabilis", "new", "page" }));
}

test "parse 'new page' with title returns page with defaults" {
    const parsed = try parse(&.{ "stabilis", "new", "page", "About Me" });
    try std.testing.expect(parsed == .new);
    try std.testing.expect(parsed.new == .page);
    try std.testing.expectEqualStrings("About Me", parsed.new.page.title);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.new.page.slug);
    try std.testing.expectEqual(false, parsed.new.page.draft);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.new.page.menus);
    try std.testing.expectEqual(false, parsed.new.page.help);
}

test "parse 'new page' with -s slug" {
    const parsed = try parse(&.{ "stabilis", "new", "page", "About", "-s", "about" });
    try std.testing.expectEqualStrings("about", parsed.new.page.slug.?);
}

test "parse 'new page' with --slug slug" {
    const parsed = try parse(&.{ "stabilis", "new", "page", "About", "--slug", "about" });
    try std.testing.expectEqualStrings("about", parsed.new.page.slug.?);
}

test "parse 'new page' with --draft" {
    const parsed = try parse(&.{ "stabilis", "new", "page", "About", "--draft" });
    try std.testing.expectEqual(true, parsed.new.page.draft);
}

test "parse 'new page' with --menus main" {
    const parsed = try parse(&.{ "stabilis", "new", "page", "About", "--menus", "main" });
    try std.testing.expectEqualStrings("main", parsed.new.page.menus.?);
}

test "parse 'new page' with --help sets help flag" {
    const parsed = try parse(&.{ "stabilis", "new", "page", "About", "--help" });
    try std.testing.expectEqual(true, parsed.new.page.help);
}

test "parse 'new page' with all flags" {
    const parsed = try parse(&.{
        "stabilis", "new",   "page",    "About",
        "-s",       "about", "--draft", "--menus",
        "main",
    });
    try std.testing.expectEqualStrings("About", parsed.new.page.title);
    try std.testing.expectEqualStrings("about", parsed.new.page.slug.?);
    try std.testing.expectEqual(true, parsed.new.page.draft);
    try std.testing.expectEqualStrings("main", parsed.new.page.menus.?);
}

test "parse 'new page' with -s missing value returns MissingValue" {
    try std.testing.expectError(error.MissingValue, parse(&.{ "stabilis", "new", "page", "About", "-s" }));
}

test "parse 'new page' with unknown flag returns UnknownFlag" {
    try std.testing.expectError(error.UnknownFlag, parse(&.{ "stabilis", "new", "page", "About", "--bogus" }));
}

test "parse 'new' with no subcommand returns new help" {
    const parsed = try parse(&.{ "stabilis", "new" });
    try std.testing.expect(parsed == .new);
    try std.testing.expect(parsed.new == .help);
}

test "parse 'new unknown' returns new help" {
    const parsed = try parse(&.{ "stabilis", "new", "unknown" });
    try std.testing.expect(parsed == .new);
    try std.testing.expect(parsed.new == .help);
}

test "parse 'serve' with no flags returns defaults" {
    const parsed = try parse(&.{ "stabilis", "serve" });
    try std.testing.expect(parsed == .serve);
    try std.testing.expectEqual(@as(?u16, null), parsed.serve.port);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.serve.bind);
    try std.testing.expectEqual(false, parsed.serve.open);
    try std.testing.expectEqual(false, parsed.serve.build_drafts);
    try std.testing.expectEqual(false, parsed.serve.help);
}

test "parse 'serve' with -p port" {
    const parsed = try parse(&.{ "stabilis", "serve", "-p", "8080" });
    try std.testing.expectEqual(@as(u16, 8080), parsed.serve.port.?);
}

test "parse 'serve' with --port port" {
    const parsed = try parse(&.{ "stabilis", "serve", "--port", "1313" });
    try std.testing.expectEqual(@as(u16, 1313), parsed.serve.port.?);
}

test "parse 'serve' with --bind addr" {
    const parsed = try parse(&.{ "stabilis", "serve", "--bind", "0.0.0.0" });
    try std.testing.expectEqualStrings("0.0.0.0", parsed.serve.bind.?);
}

test "parse 'serve' with --open" {
    const parsed = try parse(&.{ "stabilis", "serve", "--open" });
    try std.testing.expectEqual(true, parsed.serve.open);
}

test "parse 'serve' with -D builds drafts" {
    const parsed = try parse(&.{ "stabilis", "serve", "-D" });
    try std.testing.expectEqual(true, parsed.serve.build_drafts);
}

test "parse 'serve' with --help sets help flag" {
    const parsed = try parse(&.{ "stabilis", "serve", "--help" });
    try std.testing.expectEqual(true, parsed.serve.help);
}

test "parse 'serve' with combined flags" {
    const parsed = try parse(&.{ "stabilis", "serve", "-p", "8080", "--bind", "0.0.0.0", "--open", "-D" });
    try std.testing.expectEqual(@as(u16, 8080), parsed.serve.port.?);
    try std.testing.expectEqualStrings("0.0.0.0", parsed.serve.bind.?);
    try std.testing.expectEqual(true, parsed.serve.open);
    try std.testing.expectEqual(true, parsed.serve.build_drafts);
}

test "parse 'serve' with -p missing value returns MissingValue" {
    try std.testing.expectError(error.MissingValue, parse(&.{ "stabilis", "serve", "-p" }));
}

test "parse 'serve' with -p non-numeric returns InvalidValue" {
    try std.testing.expectError(error.InvalidValue, parse(&.{ "stabilis", "serve", "-p", "abc" }));
}

test "parse 'serve' with unknown flag returns UnknownFlag" {
    try std.testing.expectError(error.UnknownFlag, parse(&.{ "stabilis", "serve", "--bogus" }));
}
