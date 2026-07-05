const std = @import("std");
const Io = std.Io;

const logicConfig = @import("../logic/config.zig");
const models = @import("../models.zig");
const Config = models.Config;
const File = models.File;

/// Reads a single file relative to `base_path` and returns a populated `File`.
pub fn readFile(io: Io, arena: *std.heap.ArenaAllocator, base_path: []const u8, path: []const u8) !File {
    const allocator = arena.allocator();
    const cwd = std.Io.Dir.cwd();

    const full_path = try std.Io.Dir.path.join(allocator, &.{ base_path, path });
    const abs_path = try cwd.realPathFileAlloc(io, full_path, allocator);
    const dir_path = std.Io.Dir.path.dirname(abs_path) orelse abs_path;
    const rel_path = if (std.mem.startsWith(u8, abs_path, base_path))
        abs_path[base_path.len + 1 ..]
    else
        try allocator.dupe(u8, std.Io.Dir.path.basename(path));

    return File{
        .dir_path = dir_path,
        .abs_path = abs_path,
        .rel_path = rel_path,
        .file_ext = try allocator.dupe(u8, std.Io.Dir.path.extension(path)),
        .file_name = try allocator.dupe(u8, std.Io.Dir.path.basename(path)),
        .contents = try std.Io.Dir.readFileAlloc(cwd, io, full_path, allocator, .unlimited),
    };
}

fn walkDirImpl(io: Io, arena: *std.heap.ArenaAllocator, base_path: []const u8, path: []const u8) ![]File {
    const allocator = arena.allocator();
    var output: std.ArrayList(File) = .empty;
    const cwd = std.Io.Dir.cwd();

    const dir_open_path = try std.Io.Dir.path.join(allocator, &.{ base_path, path });
    const dir = try std.Io.Dir.openDir(cwd, io, dir_open_path, .{ .iterate = true });
    defer dir.close(io);

    const dir_path = try dir.realPathFileAlloc(io, ".", allocator);
    var dir_entries = dir.iterate();
    while (try dir_entries.next(io)) |dir_entry| {
        switch (dir_entry.kind) {
            .file => {
                const abs_path = try std.Io.Dir.path.resolve(allocator, &.{ dir_path, dir_entry.name });
                try output.append(allocator, File{
                    .dir_path = dir_open_path,
                    .abs_path = abs_path,
                    .rel_path = abs_path[base_path.len + 1 ..],
                    .file_ext = try allocator.dupe(u8, std.Io.Dir.path.extension(dir_entry.name)),
                    .file_name = try allocator.dupe(u8, dir_entry.name),
                    .contents = try std.Io.Dir.readFileAlloc(dir, io, dir_entry.name, allocator, .unlimited),
                });
            },
            .directory => {
                const branch_path = try std.Io.Dir.path.join(allocator, &.{ path, dir_entry.name });
                try output.appendSlice(allocator, try walkDirImpl(io, arena, base_path, branch_path));
            },
            else => {},
        }
    }
    return output.items;
}

/// Recursively walks `path`, returning a slice of every file found.
/// Directory entries that are not files or directories (symlinks, etc.) are ignored.
/// All strings in the returned `File` values are arena-allocated.
pub fn walkDir(io: Io, arena: *std.heap.ArenaAllocator, path: []const u8) ![]File {
    const cwd = std.Io.Dir.cwd();
    const abs_path = try cwd.realPathFileAlloc(io, path, arena.allocator());
    return walkDirImpl(io, arena, abs_path, "/");
}

/// Loads the config, content, and template files from `source_dir` into one slice.
pub fn loadFiles(arena: *std.heap.ArenaAllocator, io: std.Io, cfg: Config, source_dir: []const u8) ![]models.File {
    const allocator = arena.allocator();
    const cwd = std.Io.Dir.cwd();
    const base_path = try cwd.realPathFileAlloc(io, source_dir, allocator);

    const content_files = try walkDirImpl(io, arena, base_path, cfg.content_dir);
    const template_files = try walkDirImpl(io, arena, base_path, cfg.templates_dir);

    return try std.mem.concat(allocator, models.File, &.{ content_files, template_files });
}

// integration test: requires example/ directory
test "walkDir reads example directory" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const results = try walkDir(std.testing.io, &arena, "example");

    try std.testing.expectEqual(12, results.len);

    const expected: []const []const u8 = &.{
        "content/_index.md",
        "content/posts/_index.md",
        "content/posts/github-flavored-markdown-syntax-guide.md",
        "content/posts/hello-world.md",
        "site.yaml",
        "static/images/manly-palmer-hall-alchemical-manuscript.jpg",
        "templates/home.html",
        "templates/page.html",
        "templates/partials/header.html",
        "templates/post-list.html",
        "templates/post.html",
        "templates/tag-post-list.html",
    };

    for (expected) |rel_path| {
        var found = false;
        for (results) |f| {
            if (std.mem.endsWith(u8, f.abs_path, rel_path)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("missing file: {s}\n", .{rel_path});
            return error.TestUnexpectedResult;
        }
    }
}
