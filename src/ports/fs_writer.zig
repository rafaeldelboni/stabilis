const std = @import("std");
const Io = std.Io;

const models = @import("../models.zig");
const Config = models.Config;
const Context = models.Context;
const Page = models.Page;
const Site = models.Site;
const page = @import("../adapters/page.zig");

/// Writes `data` to `path` in the current working directory.
pub fn writeFile(io: Io, data: []const u8, path: []const u8) !void {
    return std.Io.Dir.writeFile(std.Io.Dir.cwd(), io, .{
        .sub_path = path,
        .data = data,
    });
}

/// Creates parent directories as needed, then writes `data` to `path`.
pub fn writeFileDeep(io: Io, data: []const u8, path: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |dir_path| {
        try std.Io.Dir.createDirPath(std.Io.Dir.cwd(), io, dir_path);
    }
    try writeFile(io, data, path);
}

/// Recursively deletes the directory tree rooted at `path`.
pub fn deleteDir(io: Io, path: []const u8) !void {
    try std.Io.Dir.deleteTree(std.Io.Dir.cwd(), io, path);
}

/// Renders a page to HTML and writes it under `output_dir` via `writeFileDeep`.
pub fn writePage(
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    cfg: *const Config,
    output_dir: []const u8,
    page_data: Page,
    post_list: []Context,
    site_data: Site,
) !void {
    const file_path = try page.parseFilePath(arena, output_dir, cfg.output_index, page_data);
    const html = try page.parseHtml(arena, page_data, post_list, site_data);
    try writeFileDeep(io, html, file_path);
}

/// Recursively copies `source_path` into `dest_path`, creating dirs as needed.
pub fn copyDir(
    io: Io,
    arena: *std.heap.ArenaAllocator,
    source_path: []const u8,
    dest_path: []const u8,
) !void {
    const allocator = arena.allocator();
    const cwd = std.Io.Dir.cwd();

    const source_dir = try std.Io.Dir.openDir(cwd, io, source_path, .{ .iterate = true });
    defer source_dir.close(io);
    const dir_source_path = try source_dir.realPathFileAlloc(io, ".", allocator);

    try std.Io.Dir.createDirPath(cwd, io, dest_path);
    const dir_dest_path = try cwd.realPathFileAlloc(io, dest_path, allocator);

    var dir_entries = source_dir.iterate();
    while (try dir_entries.next(io)) |dir_entry| {
        switch (dir_entry.kind) {
            .file => {
                const abs_source_path = try std.Io.Dir.path.resolve(allocator, &.{ dir_source_path, dir_entry.name });
                const abs_dest_path = try std.Io.Dir.path.resolve(allocator, &.{ dir_dest_path, dir_entry.name });
                try std.Io.Dir.copyFileAbsolute(abs_source_path, abs_dest_path, io, .{});
            },
            .directory => {
                const branch_source_path = try std.Io.Dir.path.join(allocator, &.{ source_path, dir_entry.name });
                const branch_dest_path = try std.Io.Dir.path.join(allocator, &.{ dest_path, dir_entry.name });
                try copyDir(io, arena, branch_source_path, branch_dest_path);
            },
            else => {},
        }
    }
}

pub fn extractTarToDirPath(io: Io, cwd: std.Io.Dir, tar_path: []const u8, dest_path: []const u8, extract_options: std.tar.ExtractOptions,) !void {
    var tar_file = try cwd.openFile(io, tar_path, .{});
    defer tar_file.close(io);
    var rbuf: [4096]u8 = undefined;
    var tar_reader = tar_file.reader(io, &rbuf);

    try cwd.createDirPath(io, dest_path);
    const dest_dir = try cwd.openDir(io, dest_path, .{});
    try std.tar.extract(io, dest_dir, &tar_reader.interface, extract_options);
}

// integration test: requires example/ directory
test "copyDir mirrors example directory" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();

    const tmp_path = try cwd.realPathFileAlloc(io, ".zig-cache/tmp", arena.allocator());
    const dest_path = try std.Io.Dir.path.join(arena.allocator(), &.{ tmp_path, &tmp.sub_path });

    try copyDir(io, &arena, "example", dest_path);

    var dest_dir = try std.Io.Dir.openDir(cwd, io, dest_path, .{ .iterate = true });
    defer dest_dir.close(io);

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
        "templates/tag-post-list.html",
    };

    for (expected) |rel_path| {
        const abs = try std.Io.Dir.path.resolve(arena.allocator(), &.{ dest_path, rel_path });
        const f = std.Io.Dir.openFile(cwd, io, abs, .{}) catch {
            std.debug.print("missing: {s}\n", .{rel_path});
            return error.TestUnexpectedResult;
        };
        f.close(io);
    }

    try std.testing.expectEqual(expected.len, 10);
}
