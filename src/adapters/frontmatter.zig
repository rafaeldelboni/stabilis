const std = @import("std");

pub fn parse(text: []const u8) !struct { frontmatter: []const u8, body: []const u8 } {
    _ = text;
    @panic("unimplemented");
}

test "parse returns frontmatter and body split by --- delimiters" {
    const input =
        \\---
        \\title: Hello
        \\---
        \\Content here
    ;
    const result = try parse(input);
    _ = result;
    @panic("unimplemented");
}
