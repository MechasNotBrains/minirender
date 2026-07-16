//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// TODO: Add these to mmath Rotor

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

  pub fn angle (r: Rotor) f32 {
    return 2.0 * std.math.acos(std.math.clamp(r.s, -1.0, 1.0));
  }
