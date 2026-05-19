const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "stabilis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const md4c_dep = b.dependency("md4c", .{});
    const md4c_lib = b.addLibrary(.{ .name = "md4c", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }), .linkage = .static });
    md4c_lib.root_module.addCSourceFiles(.{
        .root = md4c_dep.path(""),
        .files = &.{
            "src/md4c.c",
            "src/md4c-html.c",
            "src/entity.c",
        },
        .flags = &.{"-O2"},
    });
    md4c_lib.root_module.addIncludePath(md4c_dep.path("src"));

    exe.root_module.linkLibrary(md4c_lib);

    b.installArtifact(exe);

    // https://zigtools.org/zls/guides/build-on-save/
    const exe_check = b.addExecutable(.{
        .name = "stabilis-check",
        .root_module = exe.root_module,
    });
    const check = b.step("check", "Check if stabilis compiles");
    check.dependOn(&exe_check.step);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
