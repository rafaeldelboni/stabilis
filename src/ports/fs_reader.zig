const std = @import("std");
const Io = std.Io;

const File = struct {
    cwd_path: []const u8,
    dir_path: []const u8,
    abs_path: []const u8,
    file_ext: []const u8,
    file_name: []const u8,
    contents: []const u8,
};

pub fn readFile(io: Io, arena: *std.heap.ArenaAllocator, path: []const u8) ![]u8 {
    const allocator = arena.allocator();
    return try std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited);
}

/// Recursively walks `path`, returning a slice of every file found.
/// Directory entries that are not files or directories (symlinks, etc.) are ignored.
/// All strings in the returned `File` values are arena-allocated.
pub fn walkDir(io: Io, arena: *std.heap.ArenaAllocator, path: []const u8) ![]File {
    const allocator = arena.allocator();
    var output: std.ArrayList(File) = .empty;
    const cwd = std.Io.Dir.cwd();
    const dir = try std.Io.Dir.openDir(cwd, io, path, .{ .iterate = true });
    defer dir.close(io);

    const dir_path = try dir.realPathFileAlloc(io, ".", allocator);
    var dir_entries = dir.iterate();
    while (try dir_entries.next(io)) |dir_entry| {
        switch (dir_entry.kind) {
            .file => {
                const cwd_path = try cwd.realPathFileAlloc(io, ".", allocator);
                try output.append(allocator, File{
                    .cwd_path = cwd_path,
                    .dir_path = dir_path,
                    .abs_path = try std.Io.Dir.path.resolve(allocator, &.{ dir_path, dir_entry.name }),
                    .file_ext = try allocator.dupe(u8, std.Io.Dir.path.extension(dir_entry.name)),
                    .file_name = try allocator.dupe(u8, dir_entry.name),
                    .contents = try std.Io.Dir.readFileAlloc(dir, io, dir_entry.name, allocator, .unlimited),
                });
            },
            .directory => {
                const branch_path = try std.Io.Dir.path.join(allocator, &.{ path, dir_entry.name });
                try output.appendSlice(allocator, try walkDir(io, arena, branch_path));
            },
            else => {},
        }
    }
    return output.items;
}

// integration test: requires example/ directory
test "walkDir reads example directory" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const results = try walkDir(std.testing.io, &arena, "example");

    try std.testing.expectEqual(9, results.len);

    const expected: []const []const u8 = &.{
        "content/_index.md",
        "content/posts/_index.md",
        "content/posts/hello-world.md",
        "site.yaml",
        "templates/home.html",
        "templates/page.html",
        "templates/partials/header.html",
        "templates/post-list.html",
        "templates/post.html",
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
