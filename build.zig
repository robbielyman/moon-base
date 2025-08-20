const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const moon_base = b.addModule("moon-base", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zlua = b.dependency("zlua", .{
        .target = target,
        .optimize = optimize,
    });
    moon_base.addImport("zlua", zlua.module("zlua"));

    const tests = b.addTest(.{
        .root_module = moon_base,
    });
    const tests_run = b.addRunArtifact(tests);
    const tests_step = b.step("test", "run the tests");
    tests_step.dependOn(&tests_run.step);

    const examples_step = b.step("examples", "build the examples");

    const examples_list: []const []const u8 = &.{
        "color",
    };

    const runfile = b.createModule(.{
        .root_source_file = b.path("src/runfile.zig"),
        .target = target,
        .optimize = optimize,
    });
    runfile.addImport("zlua", zlua.module("zlua"));

    const runner = b.addExecutable(.{ .root_module = runfile, .name = "lua" });

    for (examples_list) |example| {
        const mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example})),
        });
        mod.addImport("moon-base", moon_base);
        const lib = b.addLibrary(.{
            .root_module = mod,
            .linkage = .dynamic,
            .name = example,
        });
        const suffix: []const u8 = if (target.result.os.tag == .windows) "dll" else "so";
        const wf = b.addWriteFiles();
        const name = b.fmt("{s}.{s}", .{ example, suffix });
        const rename = wf.addCopyFile(lib.getEmittedBin(), name);
        const install = b.addInstallFile(rename, name);
        examples_step.dependOn(&install.step);
        const run = b.addRunArtifact(runner);
        run.addFileArg(b.path(b.fmt("examples/{s}.lua", .{example})));
        run.setCwd(wf.getDirectory());
        tests_step.dependOn(&run.step);
    }
}
