//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub fn build(B :*@import("std").Build) void {
  const target   = B.standardTargetOptions(.{});
  const optimize = B.standardOptimizeOption(.{});

  const mstd  = B.dependency("mstd",  .{.target= target, .optimize= optimize });
  const mmath = B.dependency("mmath", .{.target= target, .optimize= optimize });
  const mcam  = B.dependency("mcam",  .{.target= target, .optimize= optimize });
  const msys  = B.dependency("msys",  .{.target= target, .optimize= optimize });
  const minp  = B.dependency("minp",  .{.target= target, .optimize= optimize });
  const mui   = B.dependency("mui",   .{.target= target, .optimize= optimize });

  const mod = B.addModule("minirender", .{
    .root_source_file = B.path("src/minirender.zig"),
    .target           = target,
    .optimize         = optimize,
  });
  mod.addImport("mstd",  mstd.module("mstd"));
  mod.addImport("mmath", mmath.module("mmath"));
  mod.addImport("mcam",  mcam.module("mcam"));
  mod.addImport("msys",  msys.module("msys"));
  mod.addImport("minp",  minp.module("minp"));
  mod.addImport("mui",   mui.module("mui"));
  if (B.lazyDependency("cvulkan", .{.target= target, .optimize= optimize })) |cvulkan| {
    mod.addImport("cvulkan", cvulkan.module("cvulkan"));
  }

  const gl = B.addModule("minirender_gl", .{
    .root_source_file = B.path("src/minirender/core.gl.zig"),
    .target           = target,
    .optimize         = optimize,
  });
  gl.addImport("mstd",  mstd.module("mstd"));
  gl.addImport("mmath", mmath.module("mmath"));
  gl.addImport("mcam",  mcam.module("mcam"));
  gl.addImport("msys",  msys.module("msys"));
  gl.addImport("minp",  minp.module("minp"));
  gl.addImport("mui",   mui.module("mui"));
  if (B.lazyDependency("mgl", .{.target= target, .optimize= optimize })) |mgl| {
    gl.addImport("mgl", mgl.module("mgl"));
  }
}

