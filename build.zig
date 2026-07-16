//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub fn build(B :*@import("std").Build) void {
  const target   = B.standardTargetOptions(.{});
  const optimize = B.standardOptimizeOption(.{});

  const mmath_dep = B.dependency("mmath", .{.target= target, .optimize= optimize });
  const mcam_dep  = B.dependency("mcam",  .{.target= target, .optimize= optimize });
  const msys_dep  = B.dependency("msys",  .{.target= target, .optimize= optimize });
  const mgl_dep   = B.dependency("mgl",   .{.target= target, .optimize= optimize });
  const minp_dep  = B.dependency("minp",  .{.target= target, .optimize= optimize });

  const mod = B.addModule("minirender", .{
    .root_source_file = B.path("src/minirender.zig"),
    .target           = target,
    .optimize         = optimize,
  });
  mod.addImport("mmath", mmath_dep.module("mmath"));
  mod.addImport("mcam",  mcam_dep.module("mcam"));
  mod.addImport("msys",  msys_dep.module("msys"));
  mod.addImport("mgl",   mgl_dep.module("mgl"));
  mod.addImport("minp",  minp_dep.module("minp"));
}

