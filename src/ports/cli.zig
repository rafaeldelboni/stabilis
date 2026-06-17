const std = @import("std");

const models = @import("../models.zig");
const Command = models.Command;

// switch (try parse(&arena, args)) {
//     .help    =>    printTopHelp(io),
//     .version =>    printVersion(io),
//     .build   => |a| if (a.help) printBuildHelp(io) else try runBuild(arena, io, a),
//     .serve   => |a| if (a.help) printServeHelp(io) else try runServe(arena, io, a),
//     .new     => |s| switch (s) {
//         .post => |a| if (a.help) printNewPostHelp(io) else try runNewPost(arena, io, a),
//         .page => |a| if (a.help) printNewPageHelp(io) else try runNewPage(arena, io, a),
//     },
// }
