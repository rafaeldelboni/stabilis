const models = @import("../models.zig");
const PageKind = models.PageKind;

fn templateFor(kind: PageKind) []const u8 {
    return switch (kind) {
        .home      => "home.html",
        .post      => "post.html",
        .page      => "page.html",
        .post_list => "posts-list.html",
    };
}
