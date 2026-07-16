//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub fn build(b: *@import("std").Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mmath_dep = b.dependency("mmath", .{ .target = target, .optimize = optimize });

    const mod = b.addModule("minirender", .{
        .root_source_file = b.path("src/minirender.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("mmath", mmath_dep.module("mmath"));
    mod.linkSystemLibrary("glfw", .{});
    mod.linkSystemLibrary("GL", .{});
}
