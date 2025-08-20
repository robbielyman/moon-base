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

    const examples_mod = b.createModule(.{
        .root_source_file = b.path("examples/color.zig"),
        .target = target,
        .optimize = optimize,
    });

    const examples = b.addLibrary(.{
        .root_module = examples_mod,
        .linkage = .dynamic,
        .name = "color",
    });
    examples_mod.addImport("moon-base", moon_base);
    const examples_step = b.step("examples", "build the examples");
    examples_step.dependOn(&b.addInstallArtifact(examples, .{}).step);
}
