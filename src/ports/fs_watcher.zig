const std = @import("std");
const builtin = @import("builtin");

pub const WaitResult = enum { changed, timeout };

/// Strips a leading `./` so prefix comparisons work with `./public/` or `public/`.
fn stripDotSlash(path: []const u8) []const u8 {
    if (path.len >= 2 and path[0] == '.' and path[1] == '/') return path[2..];
    return path;
}

/// Returns true when `dir_path` is equal to or nested under any of `excludes`.
fn isPathExcluded(dir_path: []const u8, excludes: []const []const u8) bool {
    if (excludes.len == 0) return false;
    const stripped = stripDotSlash(dir_path);
    for (excludes) |ex| {
        const ex_stripped = stripDotSlash(ex);
        if (std.mem.eql(u8, stripped, ex_stripped)) return true;
        // dir is nested under ex: check "ex/" prefix
        const prefix_len = ex_stripped.len + 1;
        if (stripped.len > prefix_len and
            std.mem.eql(u8, stripped[0..ex_stripped.len], ex_stripped) and
            stripped[ex_stripped.len] == '/')
        {
            return true;
        }
    }
    return false;
}

pub const Watcher = struct {
    impl: Impl,

    const Impl = switch (builtin.os.tag) {
        .linux => Linux,
        .macos => MacOs,
        else => @compileError("fs_watcher: unsupported OS, only Linux and macOS"),
    };

    /// Creates a watcher monitoring `paths`, ignoring changes inside `excludes`.
    pub fn init(
        io: std.Io,
        arena: *std.heap.ArenaAllocator,
        paths: []const []const u8,
        excludes: []const []const u8,
    ) !Watcher {
        return .{ .impl = try Impl.init(io, arena, paths, excludes) };
    }

    /// Releases OS resources held by the watcher (does not free arena memory).
    pub fn deinit(self: *Watcher) void {
        self.impl.deinit();
    }

    /// Blocks for up to `timeout_ms` waiting for a change; returns `.timeout` if none.
    pub fn wait(self: *Watcher, timeout_ms: u32) !WaitResult {
        return self.impl.wait(timeout_ms);
    }
};

/// Closes a file descriptor using the OS-appropriate syscall.
fn closeFd(fd: std.posix.fd_t) void {
    switch (builtin.os.tag) {
        .linux => _ = std.os.linux.close(fd),
        .macos => _ = std.c.close(fd),
        else => unreachable,
    }
}

const Linux = struct {
    fd: std.posix.fd_t,
    io: std.Io,
    mask: std.os.linux.fanotify.MarkMask,
    watch_dir: []const u8,
    excludes: []const []const u8,

    fn init(io: std.Io, arena: *std.heap.ArenaAllocator, paths: []const []const u8, excludes: []const []const u8) !Linux {
        const fan = std.os.linux.fanotify;
        const fd = try fanotify_init();
        errdefer closeFd(fd);

        const mask: fan.MarkMask = .{
            .CLOSE_WRITE = true,
            .CREATE = true,
            .DELETE = true,
            .DELETE_SELF = true,
            .EVENT_ON_CHILD = true,
            .MOVED_FROM = true,
            .MOVED_TO = true,
            .MOVE_SELF = true,
            .ONDIR = true,
        };

        for (paths) |path| {
            markDirTree(io, fd, mask, path, excludes);
        }
        const watch_dir = try arena.allocator().dupe(u8, paths[0]);
        const ex = try arena.allocator().dupe([]const u8, excludes);
        return .{ .fd = fd, .io = io, .mask = mask, .watch_dir = watch_dir, .excludes = ex };
    }

    fn deinit(self: *Linux) void {
        closeFd(self.fd);
    }

    fn wait(self: *Linux, timeout_ms: u32) !WaitResult {
        var pfds: [1]std.posix.pollfd = .{.{
            .fd = self.fd,
            .events = std.posix.POLL.IN,
            .revents = undefined,
        }};
        const n = try std.posix.poll(&pfds, @intCast(timeout_ms));
        if (n == 0) return .timeout;

        var buf: [4096]u8 = undefined;
        // NONBLOCK fd: EAGAIN means no events yet, treat as timeout.
        const len = std.posix.read(self.fd, &buf) catch |err| switch (err) {
            error.WouldBlock => return .timeout,
            else => return err,
        };

        try self.parseEvents(buf[0..len]);
        // 50ms debounce: drain follow-up events (matching macOS latency)
        while (true) {
            const n2 = std.posix.poll(&pfds, 50) catch break;
            if (n2 == 0) break;
            const len2 = std.posix.read(self.fd, &buf) catch break;
            self.parseEvents(buf[0..len2]) catch break;
        }
        return .changed;
    }

    /// Parse events to auto-mark newly created subdirectories.
    fn parseEvents(self: *Linux, buf: []u8) !void {
        const fan = std.os.linux.fanotify;
        const M = fan.event_metadata;
        var meta: [*]align(1) M = @ptrCast(@alignCast(buf.ptr));
        var remaining = buf.len;
        while (remaining >= @sizeOf(M) and meta[0].event_len >= @sizeOf(M) and meta[0].event_len <= remaining) {
            if (meta[0].mask.CREATE and meta[0].mask.ONDIR) {
                const fid: *align(1) fan.event_info_fid = @ptrCast(meta + 1);
                if (fid.hdr.info_type == .DFID_NAME) {
                    const file_handle: *align(1) std.os.linux.file_handle = @ptrCast(&fid.handle);
                    const name_ptr: [*:0]u8 = @ptrCast((&file_handle.f_handle).ptr + file_handle.handle_bytes);
                    const name = std.mem.span(name_ptr);
                    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    if (std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ self.watch_dir, name })) |new_dir| {
                        if (!isPathExcluded(new_dir, self.excludes)) {
                            markDirTree(self.io, self.fd, self.mask, new_dir, self.excludes);
                        }
                    } else |_| {}
                }
            }
            remaining -= meta[0].event_len;
            meta = @ptrCast(@as([*]u8, @ptrCast(meta)) + meta[0].event_len);
        }
    }

    /// Recursively marks `dir_path` and subdirectories on the fanotify `fd`, skipping `excludes`.
    fn markDirTree(io: std.Io, fd: std.posix.fd_t, mask: std.os.linux.fanotify.MarkMask, dir_path: []const u8, excludes: []const []const u8) void {
        if (isPathExcluded(dir_path, excludes)) return;
        const cwd = std.Io.Dir.cwd();
        fanotify_mark(fd, mask, cwd, dir_path);
        var dir = cwd.openDir(io, dir_path, .{ .iterate = true }) catch return;
        defer dir.close(io);
        var iter = dir.iterate();
        while (iter.next(io) catch null) |entry| {
            if (entry.kind != .directory) continue;
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const sub = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir_path, entry.name }) catch continue;
            markDirTree(io, fd, mask, sub, excludes);
        }
    }

    /// Allocate and initialize a fanotify group, returning its file descriptor.
    fn fanotify_init() !std.posix.fd_t {
        const rc = std.os.linux.fanotify_init(.{
            .CLOEXEC = true,
            .NONBLOCK = true,
            .CLASS = .NOTIF,
            .REPORT_NAME = true,
            .REPORT_DIR_FID = true,
            .REPORT_FID = true,
            .REPORT_TARGET_FID = true,
        }, 0);
        return switch (std.os.linux.errno(rc)) {
            .SUCCESS => @intCast(rc),
            .INVAL => return error.UnsupportedFlags,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NFILE => return error.SystemFdQuotaExceeded,
            .NOMEM => return error.SystemResources,
            .PERM => return error.PermissionDenied,
            else => |err| return std.posix.unexpectedErrno(err),
        };
    }

    /// Add a watch mark on `dir_path` (relative to `cwd`) for the given event `mask`.
    fn fanotify_mark(
        fd: std.posix.fd_t,
        mask: std.os.linux.fanotify.MarkMask,
        cwd: std.Io.Dir,
        dir_path: []const u8,
    ) void {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path_c = std.fmt.bufPrintZ(&path_buf, "{s}", .{dir_path}) catch return;
        const rc2 = std.os.linux.fanotify_mark(
            fd,
            .{ .ADD = true, .ONLYDIR = true },
            mask,
            cwd.handle,
            path_c,
        );
        switch (std.os.linux.errno(rc2)) {
            .SUCCESS => {},
            // markDirTree is best-effort: swallow all errnos.
            else => {},
        }
    }
};

const MacOs = struct {
    core_services: std.DynLib,
    rs: ResolvedSymbols,
    semaphore: std.c.dispatch.semaphore_t,
    dispatch_queue: std.c.dispatch.queue_t,
    stream: ?FSEventStreamRef = null,
    watch_roots: [][:0]const u8,
    excludes: []const []const u8,

    fn init(_: std.Io, arena: *std.heap.ArenaAllocator, paths: []const []const u8, excludes: []const []const u8) !MacOs {
        var core_services = std.DynLib.open(
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
        ) catch return error.OpenFrameworkFailed;
        errdefer core_services.close();

        var rs: ResolvedSymbols = undefined;
        inline for (@typeInfo(ResolvedSymbols).@"struct".fields) |f| {
            @field(rs, f.name) = core_services.lookup(f.type, f.name) orelse {
                std.log.err("fs_watcher: missing CoreServices symbol: {s}", .{f.name});
                return error.MissingCoreServicesSymbol;
            };
        }

        const semaphore = std.c.dispatch.semaphore_create(0) orelse return error.SystemResources;
        errdefer semaphore.as_object().release();

        const dispatch_queue = std.c.dispatch.queue_create("watcher-playground", .SERIAL()) orelse return error.SystemResources;
        errdefer dispatch_queue.as_object().release();

        const allocator = arena.allocator();
        const watch_roots = try allocator.alloc([:0]const u8, paths.len);
        for (paths, watch_roots) |path, *root| {
            root.* = try allocator.dupeZ(u8, path);
        }
        const ex = try allocator.dupe([]const u8, excludes);

        var self: MacOs = .{
            .core_services = core_services,
            .rs = rs,
            .semaphore = semaphore,
            .dispatch_queue = dispatch_queue,
            .stream = null,
            .watch_roots = watch_roots,
            .excludes = ex,
        };

        try self.startStream(allocator);
        return self;
    }

    fn deinit(self: *MacOs) void {
        if (self.stream) |stream| {
            self.rs.FSEventStreamStop(stream);
            self.rs.FSEventStreamInvalidate(stream);
            self.rs.FSEventStreamRelease(stream);
        }
        self.semaphore.as_object().release();
        self.dispatch_queue.as_object().release();
        self.core_services.close();
    }

    fn wait(self: *MacOs, timeout_ms: u32) !WaitResult {
        const timeout_ns: u64 = @as(u64, timeout_ms) * std.time.ns_per_ms;
        const result = self.semaphore.wait(.time(.NOW, @intCast(timeout_ns)));
        return switch (result) {
            0 => .changed,
            else => .timeout,
        };
    }

    /// Creates and starts the FSEvents stream on the dispatch queue, then drains initial history events.
    fn startStream(self: *MacOs, allocator: std.mem.Allocator) !void {
        const rs = self.rs;

        const cf_paths = try allocator.alloc(?CFStringRef, self.watch_roots.len);
        defer allocator.free(cf_paths);
        @memset(cf_paths, null);
        defer for (cf_paths) |o| if (o) |p| rs.CFRelease(p);

        for (self.watch_roots, cf_paths) |path, *cf_path| {
            cf_path.* = rs.CFStringCreateWithCString(null, path, .utf8);
        }

        const cf_paths_array = rs.CFArrayCreate(null, @ptrCast(cf_paths), @intCast(cf_paths.len), null);
        defer rs.CFRelease(cf_paths_array);

        const stream = rs.FSEventStreamCreate(
            null,
            &eventCallback,
            &.{
                .version = 0,
                .info = @ptrCast(self.semaphore),
                .retain = null,
                .release = null,
                .copy_description = null,
            },
            cf_paths_array,
            .since_now,
            0.05,
            .{ .watch_root = true, .file_events = true, .ignore_self = self.excludes.len > 0 },
        );
        if (stream == null) return error.StreamCreateFailed;
        self.stream = stream;

        rs.FSEventStreamSetDispatchQueue(stream, self.dispatch_queue);
        if (!rs.FSEventStreamStart(stream)) return error.StreamStartFailed;

        // Drain the initial history_done/root-scan burst so the first
        // real `wait` doesn't report stale history as a change.
        var attempts: u8 = 0;
        while (attempts < 20) : (attempts += 1) {
            const r = self.semaphore.wait(.time(.NOW, 100 * std.time.ns_per_ms));
            if (r != 0) break;
        }
    }

    /// FSEvents callback: signals the semaphore on the first non-history event (ignore_self filters build writes).
    fn eventCallback(
        _: ConstFSEventStreamRef,
        client_callback_info: ?*anyopaque,
        num_events: usize,
        _: *anyopaque,
        events_flags: [*]const FSEventStreamEventFlags,
        _: [*]const FSEventStreamEventId,
    ) callconv(.c) void {
        const sem: std.c.dispatch.semaphore_t = @ptrCast(@alignCast(client_callback_info));
        var i: usize = 0;
        while (i < num_events) : (i += 1) {
            if (events_flags[i].history_done) continue;
            _ = std.c.dispatch.semaphore_signal(sem);
            return;
        }
    }

    const ResolvedSymbols = struct {
        FSEventStreamCreate: *const fn (
            allocator: CFAllocatorRef,
            callback: FSEventStreamCallback,
            ctx: ?*const FSEventStreamContext,
            paths_to_watch: CFArrayRef,
            since_when: FSEventStreamEventId,
            latency: CFTimeInterval,
            flags: FSEventStreamCreateFlags,
        ) callconv(.c) FSEventStreamRef,
        FSEventStreamSetDispatchQueue: *const fn (stream: FSEventStreamRef, queue: std.c.dispatch.queue_t) callconv(.c) void,
        FSEventStreamStart: *const fn (stream: FSEventStreamRef) callconv(.c) bool,
        FSEventStreamStop: *const fn (stream: FSEventStreamRef) callconv(.c) void,
        FSEventStreamInvalidate: *const fn (stream: FSEventStreamRef) callconv(.c) void,
        FSEventStreamRelease: *const fn (stream: FSEventStreamRef) callconv(.c) void,
        CFRelease: *const fn (cf: *const anyopaque) callconv(.c) void,
        CFArrayCreate: *const fn (
            allocator: CFAllocatorRef,
            values: [*]const usize,
            num_values: CFIndex,
            call_backs: ?*const CFArrayCallBacks,
        ) callconv(.c) CFArrayRef,
        CFStringCreateWithCString: *const fn (
            alloc: CFAllocatorRef,
            c_str: [*:0]const u8,
            encoding: CFStringEncoding,
        ) callconv(.c) CFStringRef,
    };

    const CFAllocatorRef = ?*const opaque {};
    const CFArrayRef = *const opaque {};
    const CFStringRef = *const opaque {};
    const CFTimeInterval = f64;
    const CFIndex = i32;
    const FSEventStreamRef = ?*opaque {};
    const ConstFSEventStreamRef = ?*const opaque {};

    const FSEventStreamCallback = *const fn (
        stream: ConstFSEventStreamRef,
        client_callback_info: ?*anyopaque,
        num_events: usize,
        event_paths: *anyopaque,
        event_flags: [*]const FSEventStreamEventFlags,
        event_ids: [*]const FSEventStreamEventId,
    ) callconv(.c) void;

    const FSEventStreamContext = extern struct {
        version: CFIndex,
        info: ?*anyopaque,
        retain: ?*const fn (?*const anyopaque) callconv(.c) *const anyopaque,
        release: ?*const fn (?*const anyopaque) callconv(.c) void,
        copy_description: ?*const fn (?*const anyopaque) callconv(.c) CFStringRef,
    };

    const FSEventStreamEventId = enum(u64) {
        since_now = std.math.maxInt(u64),
        _,
    };

    const FSEventStreamCreateFlags = packed struct(u32) {
        use_cf_types: bool = false,
        no_defer: bool = false,
        watch_root: bool = false,
        ignore_self: bool = false,
        file_events: bool = false,
        _: u27 = 0,
    };

    const FSEventStreamEventFlags = packed struct(u32) {
        must_scan_sub_dirs: bool,
        user_dropped: bool,
        kernel_dropped: bool,
        event_ids_wrapped: bool,
        history_done: bool,
        root_changed: bool,
        mount: bool,
        unmount: bool,
        _: u24 = 0,
    };

    const CFStringEncoding = enum(u32) {
        invalid_id = std.math.maxInt(u32),
        mac_roman = 0,
        windows_latin_1 = 0x500,
        iso_latin_1 = 0x201,
        next_step_latin = 0xB01,
        ascii = 0x600,
        unicode = 0x100,
        utf8 = 0x8000100,
        non_lossy_ascii = 0xBFF,
    };

    const CFArrayCallBacks = opaque {};
};

test "watcher detects file modification" {
    const io = std.testing.io;

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", arena.allocator());

    var watcher = try Watcher.init(io, &arena, &.{dir_path}, &.{});
    defer watcher.deinit();

    const initial = try watcher.wait(200);
    try std.testing.expectEqual(.timeout, initial);

    try tmp_dir.dir.writeFile(io, .{ .sub_path = "test.txt", .data = "hello" });

    const result = try waitForChange(&watcher, 2000);
    try std.testing.expectEqual(.changed, result);
}

test "watcher returns timeout when nothing changes" {
    const io = std.testing.io;

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", arena.allocator());

    var watcher = try Watcher.init(io, &arena, &.{dir_path}, &.{});
    defer watcher.deinit();

    const result = try watcher.wait(300);
    try std.testing.expectEqual(.timeout, result);
}

test "watcher detects changes in subdirectory" {
    const io = std.testing.io;

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", arena.allocator());

    var watcher = try Watcher.init(io, &arena, &.{dir_path}, &.{});
    defer watcher.deinit();

    const initial = try watcher.wait(200);
    try std.testing.expectEqual(.timeout, initial);

    // 1. Create subdirectory → should trigger change
    try tmp_dir.dir.createDir(io, "sub", .default_dir);
    try std.testing.expectEqual(.changed, try waitForChange(&watcher, 2000));

    // 2. Write file in subdirectory → should trigger change
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "sub/nested.txt", .data = "first" });
    try std.testing.expectEqual(.changed, try waitForChange(&watcher, 2000));

    // 3. Modify that file → should trigger change
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "sub/nested.txt", .data = "second" });
    try std.testing.expectEqual(.changed, try waitForChange(&watcher, 2000));
}

fn waitForChange(watcher: *Watcher, total_timeout_ms: u32) !WaitResult {
    var elapsed: u32 = 0;
    const poll_ms: u32 = 50;
    while (elapsed < total_timeout_ms) {
        const result = try watcher.wait(poll_ms);
        if (result == .changed) return .changed;
        elapsed += poll_ms;
    }
    return .timeout;
}
