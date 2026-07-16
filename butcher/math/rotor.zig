//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// Rotor: scalar + bivector (geometric product of two vectors)
//
// R = a·b + a∧b = s + B
// Rotation: v' = R v R~   (sandwich product)
// @deps std
const std = @import("std");
const Vec4  = @import("./vector.zig").Vec4;
const BiVec = @import("./vector.zig").BiVec;

pub const Rotor = struct {
  s  :f32 = 1,
  xy :f32 = 0,
  xz :f32 = 0,
  yz :f32 = 0,

  pub fn fromVectors (from: Vec4, to: Vec4) Rotor {
    const wedge = Vec4.wedge(to, from);
    const result = Rotor{ .s = 1 + Vec4.dot(to, from), .xy = wedge.xy, .xz = wedge.xz, .yz = wedge.yz };
    return result.normalize();
  }

  pub fn fromAnglePlane (radians: f32, plane: BiVec) Rotor {
    const unit = plane.normalize();
    const half = radians * 0.5;
    const cos_h = @cos(half);
    const sin_h = -@sin(half);
    return .{
      .s  = cos_h,
      .xy = sin_h * unit.xy,
      .xz = sin_h * unit.xz,
      .yz = sin_h * unit.yz,
    };
  }

  pub fn reverse (r: Rotor) Rotor {
    return .{ .s = r.s, .xy = -r.xy, .xz = -r.xz, .yz = -r.yz };
  }

  pub fn len_sq (r: Rotor) f32 {
    return r.s * r.s + r.xy * r.xy + r.xz * r.xz + r.yz * r.yz;
  }

  pub fn normalize (r: Rotor) Rotor {
    const length = @sqrt(r.len_sq());
    if (length < 1e-6) return Rotor{};
    return .{
      .s  = r.s  / length,
      .xy = r.xy / length,
      .xz = r.xz / length,
      .yz = r.yz / length,
    };
  }

  pub fn mul (a: Rotor, b: Rotor) Rotor {
    return .{
      .s  = a.s * b.s  - a.xy * b.xy - a.xz * b.xz - a.yz * b.yz,
      .xy = a.s * b.xy + a.xy * b.s  - a.xz * b.yz + a.yz * b.xz,
      .xz = a.s * b.xz + a.xy * b.yz + a.xz * b.s  - a.yz * b.xy,
      .yz = a.s * b.yz - a.xy * b.xz + a.xz * b.xy + a.yz * b.s,
    };
  }

  pub fn apply (r: Rotor, v: Vec4) Vec4 {
    // Sandwich product: R v R~
    // Expand R v first, then multiply by R~
    // R v where R = s + xy*exy + xz*exz + yz*eyz
    //         and v = vx*ex + vy*ey + vz*ez
    const rv_x   = r.s  * v.x + r.xy * v.y + r.xz * v.z;
    const rv_y   = r.s  * v.y - r.xy * v.x + r.yz * v.z;
    const rv_z   = r.s  * v.z - r.xz * v.x - r.yz * v.y;
    const rv_xyz = r.xy * v.z - r.xz * v.y + r.yz * v.x;

    // (Rv) R~ where R~ = s - xy*exy - xz*exz - yz*eyz
    const rr = r.reverse();
    return .{
      .x= rv_x * rr.s  - rv_y * rr.xy - rv_z * rr.xz - rv_xyz * rr.yz,
      .y= rv_x * rr.xy + rv_y * rr.s  - rv_z * rr.yz + rv_xyz * rr.xz,
      .z= rv_x * rr.xz + rv_y * rr.yz + rv_z * rr.s  - rv_xyz * rr.xy,
      .w= v.w,
    };
  }

  pub fn bivector (r: Rotor) BiVec {
    return .{ .xy = r.xy, .xz = r.xz, .yz = r.yz };
  }

  pub fn angle (r: Rotor) f32 {
    return 2.0 * std.math.acos(std.math.clamp(r.s, -1.0, 1.0));
  }
};

