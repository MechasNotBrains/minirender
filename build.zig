//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
const b = @This();
// @deps std
const std = @import("std");
pub fn build (B :*std.Build) void {
  const target   = B.standardTargetOptions(.{});
  const optimize = B.standardOptimizeOption(.{});
  //__________________
  // Cvulkan Backend
  const mod = B.addModule("minirender", .{
    .root_source_file = B.path("src/minirender.zig"),
    .target           = target,
    .optimize         = optimize,
  });
  b.add_dependencies(mod, B, target, optimize);
  if (B.lazyDependency("cvulkan", .{.target= target, .optimize= optimize })) |cvulkan| mod.addImport("cvulkan", cvulkan.module("cvulkan"));
  //__________________
  // OpenGL Backend
  const gl = B.addModule("minirender_gl", .{
    .root_source_file = B.path("src/minirender/core.gl.zig"),
    .target           = target,
    .optimize         = optimize,
  });
  b.add_dependencies(gl, B, target, optimize);
  if (B.lazyDependency("mgl", .{.target= target, .optimize= optimize })) |mgl| gl.addImport("mgl", mgl.module("mgl"));
}

//______________________________________
// @section Dependencies
//____________________________
fn add_dependencies (
    mod : *std.Build.Module,
    B   : *std.Build,
    trg : std.Build.ResolvedTarget,
    opt : std.builtin.OptimizeMode,
  ) void {
  const mstd  = B.dependency("mstd",  .{.target= trg, .optimize= opt });
  const mmath = B.dependency("mmath", .{.target= trg, .optimize= opt });
  const mcam  = B.dependency("mcam",  .{.target= trg, .optimize= opt });
  const msys  = B.dependency("msys",  .{.target= trg, .optimize= opt });
  const minp  = B.dependency("minp",  .{.target= trg, .optimize= opt });
  const mui   = B.dependency("mui",   .{.target= trg, .optimize= opt });
  mod.addImport("mstd",  mstd.module("mstd"));
  mod.addImport("mmath", mmath.module("mmath"));
  mod.addImport("mcam",  mcam.module("mcam"));
  mod.addImport("msys",  msys.module("msys"));
  mod.addImport("minp",  minp.module("minp"));
  mod.addImport("mui",   mui.module("mui"));
}

