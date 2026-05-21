//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps debug.renderer
const Vec4     = @import("../math/vector.zig").Vec4;
const Color    = @import("../color.zig").Color;
const Renderer = @import("../../minirender.zig").Renderer;


/// Draw the standard XYZ axes with thick shafts.
pub fn axes (R :*Renderer, size :f32) void {
  const thickness :f32 = 0.02;
  const origin = Vec4.point(0, 0, 0);
  const tip_x = Vec4{ .x = size, .w = 1 };
  const tip_y = Vec4{ .y = size, .w = 1 };
  const tip_z = Vec4{ .z = size, .w = 1 };

  R.thickLine(origin, tip_x, thickness, Color.red);
  R.thickLine(origin, tip_y, thickness, Color.green);
  R.thickLine(origin, tip_z, thickness, Color.blue);

  R.text3d(.{ .x = size * 1.1 }, "X", Color.red);
  R.text3d(.{ .y = size * 1.1 }, "Y", Color.green);
  R.text3d(.{ .z = size * 1.1 }, "Z", Color.blue);
}


/// Draw a ground grid on the XY plane (Z-up).
pub fn grid (R: *Renderer, half_extent: f32, step: f32) void {
  const c = Color.dark_gray;
  var i: f32 = -half_extent;
  while (i <= half_extent + step * 0.01) : (i += step) {
    R.line(
      .{ .x = i, .y = -half_extent, .z = 0 },
      .{ .x = i, .y = half_extent, .z = 0 },
      c,
    );
    R.line(
      .{ .x = -half_extent, .y = i, .z = 0 },
      .{ .x = half_extent, .y = i, .z = 0 },
      c,
    );
  }
}

