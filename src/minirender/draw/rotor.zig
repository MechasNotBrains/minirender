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
pub fn rotor (R: *Renderer, rot: Rotor, v: Vec4, c: Color) void {
  const rotated = rot.apply(v);
  const origin = Vec4.point(0, 0, 0);

  R.arrow(origin, v, Color.yellow);
  R.text3d(v, "original", Color.yellow);
  R.arrow(origin, rotated, c);
  R.text3d(rotated, "rotated", c);

  const bv           = rot.bivector();
  const plane_normal = bv.normal().normalize();
  const half_angle   = std.math.acos(std.math.clamp(rot.s, -1.0, 1.0));

  // Two tangent vectors in the bivector plane, separated by half_angle.
  // Their wedge product forms the parallelogram representing the rotor.
  var tangent_a: Vec4 = undefined;
  if (@abs(plane_normal.x) < 0.9) {
    tangent_a = Vec4.cross(plane_normal, Vec4.dir(1, 0, 0)).normalize();
  } else {
    tangent_a = Vec4.cross(plane_normal, Vec4.dir(0, 1, 0)).normalize();
  }
  const tangent_perp = Vec4.cross(plane_normal, tangent_a).normalize();
  const cos_h = @cos(half_angle);
  const sin_h = @sin(half_angle);
  const tangent_b = tangent_a.scale(cos_h).add(tangent_perp.scale(sin_h));

  R.bivec(origin, tangent_a, tangent_b, c);
  R.angle(v, rotated, 0.5, c);
}

