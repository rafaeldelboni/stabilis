const std = @import("std");

const models = @import("../models.zig");
const fs_reader = @import("fs_reader.zig");

const log = std.log.scoped(.server);

const LISTEN_ADDR = "127.0.0.1";
const LISTEN_PORT = 8000;

// TODO move to logic and test
pub fn stripUrlQueryAndFragment(url: []const u8) []const u8 {
    const qt = std.mem.findScalar(u8, url, '?') orelse url.len;
    const hs = std.mem.findScalar(u8, url, '#') orelse url.len;
    return url[0..@min(qt, hs)];
}

/// Translate target url into extracted file contents
pub fn staticFileReader(arena: *std.heap.ArenaAllocator, io: std.Io, output_dir: []const u8, url: []const u8) !?[]const u8 {
    const allocator = arena.allocator();
    const strippedUrl = stripUrlQueryAndFragment(url);
    const file_path = try std.Io.Dir.path.join(allocator, &.{ output_dir, strippedUrl });
    const kind = try fs_reader.readFileKind(io, file_path);
    return switch (kind) {
        .directory => {
            const index_path = try std.Io.Dir.path.join(allocator, &.{ file_path, "index.html" });
            return try fs_reader.readFileContents(io, arena, index_path);
        },
        .file => try fs_reader.readFileContents(io, arena, file_path),
        else => null,
    };
}

// https://github.com/doprz/zig-http-server/
pub fn start(arena: *std.heap.ArenaAllocator, io: std.Io, server: *std.Io.net.Server, output_dir: []const u8) !void {
    log.info("Listening on http://{s}:{d}", .{ LISTEN_ADDR, LISTEN_PORT });

    while (true) {
        var stream = try server.accept(io);
        defer stream.close(io);

        // Wrap the raw stream in buffered Io.Reader / Io.Writer
        var read_buffer: [1024]u8 = undefined;
        var write_buffer: [1024]u8 = undefined;
        var reader = stream.reader(io, &read_buffer);
        var writer = stream.writer(io, &write_buffer);

        // HTTP layer: parse the byte stream at HTTP/1.1
        var http_server = std.http.Server.init(&reader.interface, &writer.interface);
        var req = try http_server.receiveHead();

        log.info("{s} {s}", .{ @tagName(req.head.method), req.head.target });

        // returing request response data
        if (try staticFileReader(arena, io, output_dir, req.head.target)) |contents| {
            try req.respond(contents, .{ .status = .ok });
        } else {
            try req.respond("Not Found!", .{ .status = .not_found });
        }
    }
}
