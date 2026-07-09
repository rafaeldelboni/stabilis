const std = @import("std");

pub const ReloadSignal = struct {
    mutex: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    generation: u64 = 0,
    shutting_down: bool = false,

    /// Notifies waiting SSE clients that a rebuild completed.
    pub fn notify(self: *ReloadSignal, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        self.generation += 1;
        self.cond.broadcast(io);
    }

    /// Blocks until generation changes, a ping interval elapses, or shutdown is signaled.
    pub fn waitChange(self: *ReloadSignal, io: std.Io, seen_gen: *u64, ping_interval: i64) WaitResult {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        while (self.generation == seen_gen.* and !self.shutting_down) {
            self.mutex.unlock(io);
            io.sleep(std.Io.Duration.fromMilliseconds(ping_interval), .awake) catch {};
            self.mutex.lockUncancelable(io);
        }

        if (self.shutting_down) return .shutdown;
        if (self.generation == seen_gen.*) return .ping;
        seen_gen.* = self.generation;
        return .reload;
    }

    pub const WaitResult = enum { reload, ping, shutdown };
};

/// Streams server-sent reload events to an SSE client connection.
pub fn handler(io: std.Io, req: *std.http.Server.Request, sig: *ReloadSignal) !void {
    var buf: [4096]u8 = undefined;
    var body = req.respondStreaming(&buf, .{
        .respond_options = .{
            .status = .ok,
            .keep_alive = true,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/event-stream" },
                .{ .name = "cache-control", .value = "no-cache" },
            },
            // transfer_encoding left null + no content_length => chunked
        },
    }) catch return;

    try body.writer.writeAll("retry: 2000\n\n");
    try body.writer.flush();
    try body.flush();

    var seen_gen: u64 = sig.generation;
    while (true) {
        switch (sig.waitChange(io, &seen_gen, 500)) {
            .reload => {
                try body.writer.print("event: reload\ndata: {d}\n\n", .{seen_gen});
            },
            .ping => {
                body.writer.writeAll(": ping\n\n") catch break;
            },
            .shutdown => return,
        }
        body.writer.flush() catch break;
        body.flush() catch break;
    }

    body.end() catch {};
}
