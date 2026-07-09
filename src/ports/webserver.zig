const std = @import("std");
const builtin = @import("builtin");

const logic = @import("../logic/webserver.zig");
const fs_reader = @import("fs_reader.zig");
const sse = @import("sse.zig");

const log = std.log.scoped(.server);

/// Translate target url into extracted file contents
fn staticFileReader(arena: *std.heap.ArenaAllocator, io: std.Io, output_dir: []const u8, url: []const u8) !?[]const u8 {
    const allocator = arena.allocator();
    const strippedUrl = logic.stripUrlQueryAndFragment(url);
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

/// Opens `url` in the user's default browser via `open` (macOS) or `xdg-open` (other).
pub fn openBrowser(io: std.Io, url: []const u8) !void {
    const cmd = switch (builtin.os.tag) {
        .macos => "open",
        else => "xdg-open",
    };
    _ = try std.process.spawn(io, .{
        .argv = &.{ cmd, url },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
}

/// Creates and binds a TCP server socket, returning the ready-to-accept server.
pub fn init(io: std.Io, ip: []const u8, port: u16) !std.Io.net.Server {
    log.info("Listening on http://{s}:{d}", .{ ip, port });
    const addr = try std.Io.net.IpAddress.parseIp4(ip, port);
    return try addr.listen(io, .{ .reuse_address = true });
}

fn handleConnection(
    parent_arena: *std.heap.ArenaAllocator,
    io: std.Io,
    sig: *sse.ReloadSignal,
    stream: std.Io.net.Stream,
    output_dir: []const u8,
) void {
    defer stream.close(io);

    var arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(parent_arena.child_allocator);
    defer arena.deinit();

    var read_buffer: [1024]u8 = undefined;
    var write_buffer: [1024]u8 = undefined;
    var reader = stream.reader(io, &read_buffer);
    var writer = stream.writer(io, &write_buffer);

    var http_server = std.http.Server.init(&reader.interface, &writer.interface);
    var req = http_server.receiveHead() catch return;

    log.info("{s} {s}", .{ @tagName(req.head.method), req.head.target });

    const path = logic.stripUrlQueryAndFragment(req.head.target);
    if (std.mem.eql(u8, path, "/__stabilis_sse")) {
        sse.handler(io, &req, sig) catch return;
        return;
    }

    if (staticFileReader(&arena, io, output_dir, req.head.target) catch null) |contents| {
        const content_type = logic.contentTypeForPath(req.head.target);

        req.respond(logic.injectSseScript(&arena, contents, content_type), .{
            .status = .ok,
            .extra_headers = &.{.{ .name = "content-type", .value = content_type }},
        }) catch return;
    } else {
        req.respond("Not Found!", .{ .status = .not_found }) catch return;
    }
}

/// Accepts connections in a loop, spawning a thread per connection to serve static files from `output_dir`.
pub fn start(
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    sig: *sse.ReloadSignal,
    server: *std.Io.net.Server,
    output_dir: []const u8,
) !void {
    while (true) {
        const stream = try server.accept(io);
        const t = std.Thread.spawn(.{}, handleConnection, .{ arena, io, sig, stream, output_dir }) catch {
            stream.close(io);
            continue;
        };
        t.detach();
    }
}
