const std = @import("std");

/// Strips the query string and fragment from a URL, returning only the path portion.
pub fn stripUrlQueryAndFragment(url: []const u8) []const u8 {
    const qt = std.mem.findScalar(u8, url, '?') orelse url.len;
    const hs = std.mem.findScalar(u8, url, '#') orelse url.len;
    return url[0..@min(qt, hs)];
}

/// Injects the live-reload SSE script into HTML content before `</head>`.
pub fn injectSseScript(
    arena: *std.heap.ArenaAllocator,
    contents: []const u8,
    content_type: []const u8,
) []const u8 {
    if (std.mem.eql(u8, content_type, "text/html")) {
        const script =
            \\<script>
            \\const eventSource = new EventSource('/__stabilis_sse');
            \\eventSource.onopen = function() { console.log('SSE connection established'); };
            \\eventSource.addEventListener('reload', function(e) { window.location.reload(); });
            \\</script>
        ;
        const head_close = std.mem.indexOf(u8, contents, "</head>") orelse {
            return contents;
        };

        const merged = std.mem.concat(arena.allocator(), u8, &.{
            contents[0..head_close],
            script,
            contents[head_close..],
        }) catch return contents;

        return merged;
    } else return contents;
}

/// Maps a URL path's extension to its MIME type, defaulting to `text/html`.
pub fn contentTypeForPath(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return "text/html";
    if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return "text/html";
    if (std.mem.eql(u8, ext, ".css")) return "text/css";
    if (std.mem.eql(u8, ext, ".js")) return "application/javascript";
    if (std.mem.eql(u8, ext, ".json")) return "application/json";
    if (std.mem.eql(u8, ext, ".xml")) return "application/xml";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".gif")) return "image/gif";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, ".woff")) return "font/woff";
    if (std.mem.eql(u8, ext, ".woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, ".txt")) return "text/plain";
    return "application/octet-stream";
}

test "stripUrlQueryAndFragment strips query and fragment" {
    try std.testing.expectEqualStrings("/path", stripUrlQueryAndFragment("/path?query=1#frag"));
    try std.testing.expectEqualStrings("/path", stripUrlQueryAndFragment("/path#frag"));
    try std.testing.expectEqualStrings("/path", stripUrlQueryAndFragment("/path?query=1"));
    try std.testing.expectEqualStrings("/path", stripUrlQueryAndFragment("/path"));
}

test "contentTypeForPath maps extensions to mime types" {
    try std.testing.expectEqualStrings("text/html", contentTypeForPath("/index.html"));
    try std.testing.expectEqualStrings("text/html", contentTypeForPath("/page.htm"));
    try std.testing.expectEqualStrings("text/css", contentTypeForPath("/style.css"));
    try std.testing.expectEqualStrings("application/javascript", contentTypeForPath("/main.js"));
    try std.testing.expectEqualStrings("image/png", contentTypeForPath("/img/logo.png"));
    try std.testing.expectEqualStrings("image/jpeg", contentTypeForPath("/img/photo.jpg"));
    try std.testing.expectEqualStrings("image/svg+xml", contentTypeForPath("/img/icon.svg"));
    try std.testing.expectEqualStrings("text/plain", contentTypeForPath("/robots.txt"));
    try std.testing.expectEqualStrings("application/octet-stream", contentTypeForPath("/file.xyz"));
}

test "contentTypeForPath defaults to text/html for extensionless paths" {
    try std.testing.expectEqualStrings("text/html", contentTypeForPath("/"));
    try std.testing.expectEqualStrings("text/html", contentTypeForPath("/posts/"));
    try std.testing.expectEqualStrings("text/html", contentTypeForPath("/posts/hello"));
}

test "injectSseScript injects script into HTML before </head>" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const html = "<html><head><title>Test</title></head><body>Hello</body></html>";
    const result = injectSseScript(&arena, html, "text/html");

    // The script should be inserted before </head>
    try std.testing.expect(std.mem.indexOf(u8, result, "<script>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "EventSource") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "</head>") != null);

    // The script should appear before the </head> tag
    const script_pos = std.mem.indexOf(u8, result, "<script>").?;
    const head_close_pos = std.mem.indexOf(u8, result, "</head>").?;
    try std.testing.expect(script_pos < head_close_pos);

    // Everything after </head> should be unchanged
    const orig_head_close = std.mem.indexOf(u8, html, "</head>").?;
    try std.testing.expectEqualStrings(html[orig_head_close..], result[head_close_pos..]);
}

test "injectSseScript returns unchanged when content type is not HTML" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const css = "body { color: red; }";
    const result = injectSseScript(&arena, css, "text/css");
    try std.testing.expectEqualStrings(css, result);
}

test "injectSseScript returns unchanged when no </head> tag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const html = "<html><body>No head tag here</body></html>";
    const result = injectSseScript(&arena, html, "text/html");
    try std.testing.expectEqualStrings(html, result);
}
