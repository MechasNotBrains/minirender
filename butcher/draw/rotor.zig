//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps std
const std = @import("std");
// @deps debug.renderer
const Vec4     = @import("../math/vector.zig").Vec4;
const Rotor    = @import("../math/rotor.zig").Rotor;
const Color    = @import("../color.zig").Color;
const Renderer = @import("../../minirender.zig").Renderer;


/// Draw a rotor: the rotation plane parallelogram, input vector, and rotated result.
pub fn rotor (R :*Renderer, rot :Rotor, v :Vec4, name :[]const u8, c :Color) void {
  const rotated = rot.apply(v);
  const origin  = Vec4.point(0, 0, 0);
  R.arrow(origin, v, Color.yellow);
  R.text3d(v, name, Color.yellow);
  R.arrow(origin, rotated, c);
  R.text3d(rotated, "rotated", c);
  R.parallelogram(origin, v, rotated, c);
  R.angle(v, rotated, 0.5, c);
}


/// Draw a rotor's projection onto its basis planes
pub fn rotor_basis (
    R    : *Renderer,
    rot  : Rotor,
    v    : Vec4,
    c_xy : Color,
    c_xz : Color,
    c_yz : Color,
  ) void {
  // v' = v.rotated
  const r      = rot.apply(v);
  const origin = Vec4.point(0, 0, 0);

  // XY  (drop z):   a = (v.x, v.y,  0 )    b = (v'.x, v'.y,  0 )
  const xy_a = Vec4.dir(v.x, v.y, 0);
  const xy_b = Vec4.dir(r.x, r.y, 0);
  R.parallelogram(origin, xy_a, xy_b, c_xy);

  // XZ  (drop y):   a = (v.x,  0,  v.z)    b = (v'.x,  0,  v'.z)
  const xz_a = Vec4.dir(v.x, 0, v.z);
  const xz_b = Vec4.dir(r.x, 0, r.z);
  R.parallelogram(origin, xz_a, xz_b, c_xz);

  // YZ  (drop x):   a = ( 0,  v.y, v.z)    b = ( 0,  v'.y, v'.z)
  const yz_a = Vec4.dir(0, v.y, v.z);
  const yz_b = Vec4.dir(0, r.y, r.z);
  R.parallelogram(origin, yz_a, yz_b, c_yz);
}

