const std = @import("std");

/// Strips the query string and fragment from a URL, returning only the path portion.
pub fn stripUrlQueryAndFragment(url: []const u8) []const u8 {
    const qt = std.mem.findScalar(u8, url, '?') orelse url.len;
    const hs = std.mem.findScalar(u8, url, '#') orelse url.len;
    return url[0..@min(qt, hs)];
}

/// Maps a URL path's extension to its MIME type. Paths with no extension
/// (e.g. directory URLs resolving to `index.html`) default to `text/html`.
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
