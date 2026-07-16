//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub fn build(B :*@import("std").Build) void {
  const target   = B.standardTargetOptions(.{});
  const optimize = B.standardOptimizeOption(.{});

  const mmath = B.dependency("mmath", .{.target= target, .optimize= optimize });
  const mcam  = B.dependency("mcam",  .{.target= target, .optimize= optimize });
  const msys  = B.dependency("msys",  .{.target= target, .optimize= optimize });
  const mgl   = B.dependency("mgl",   .{.target= target, .optimize= optimize });
  const minp  = B.dependency("minp",  .{.target= target, .optimize= optimize });
  const mui   = B.dependency("mui",   .{.target= target, .optimize= optimize });

  const mod = B.addModule("minirender", .{
    .root_source_file = B.path("src/minirender.zig"),
    .target           = target,
    .optimize         = optimize,
  });
  mod.addImport("mmath", mmath.module("mmath"));
  mod.addImport("mcam",  mcam.module("mcam"));
  mod.addImport("msys",  msys.module("msys"));
  mod.addImport("mgl",   mgl.module("mgl"));
  mod.addImport("minp",  minp.module("minp"));
  mod.addImport("mui",   mui.module("mui"));
}

