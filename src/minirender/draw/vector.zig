//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps std
const std = @import("std");
// @deps debug.renderer
const Vec4     = @import("../math/vector.zig").Vec4;
const Color    = @import("../color.zig").Color;
const Renderer = @import("../../minirender.zig").Renderer;


/// Draw a Vec4 as an arrow from the origin, labeled.
pub fn vec (R :*Renderer, v :Vec4, label :?[]const u8, c :Color) void {
  R.arrow(Vec4.point(0, 0, 0), v, c);
  if (label) |lbl| {
    R.text3d(.{ .x = v.x, .y = v.y, .z = v.z }, lbl, c);
  }
}


/// Draw a Vec4 as an arrow from a given origin, labeled.
pub fn vecAt (R: *Renderer, origin: Vec4, v: Vec4, label: ?[]const u8, c: Color) void {
  R.arrow(origin, v, c);
  if (label) |lbl| {
    R.text3d(.{ .x = origin.x + v.x, .y = origin.y + v.y, .z = origin.z + v.z }, lbl, c);
  }
}


/// Visualize a cross product: draw A, B, and A×B.
pub fn cross (R: *Renderer, a: Vec4, b: Vec4) void {
  const cx = a.y * b.z - a.z * b.y;
  const cy = a.z * b.x - a.x * b.z;
  const cz = a.x * b.y - a.y * b.x;
  const result = Vec4.dir(cx, cy, cz);

  const o = Vec4.point(0, 0, 0);
  R.arrow(o, a, Color.red);
  R.arrow(o, b, Color.green);
  R.arrow(o, result, Color.yellow);
  R.text3d(.{ .x = a.x, .y = a.y, .z = a.z }, "A", Color.red);
  R.text3d(.{ .x = b.x, .y = b.y, .z = b.z }, "B", Color.green);
  R.text3d(.{ .x = cx, .y = cy, .z = cz }, "AxB", Color.yellow);
}

/// Visualize projection of A onto B.
pub fn projection (R: *Renderer, a: Vec4, b: Vec4) void {
  const dot = a.x * b.x + a.y * b.y + a.z * b.z;
  const b_len_sq = b.x * b.x + b.y * b.y + b.z * b.z;
  if (b_len_sq < 1e-9) return;
  const t = dot / b_len_sq;
  const proj = Vec4.dir(b.x * t, b.y * t, b.z * t);

  const o = Vec4.point(0, 0, 0);
  R.arrow(o, a, Color.cyan);
  R.arrow(o, b, Color.magenta);
  R.arrow(o, proj, Color.yellow);
  R.text3d(.{ .x = a.x, .y = a.y, .z = a.z }, "A", Color.cyan);
  R.text3d(.{ .x = b.x, .y = b.y, .z = b.z }, "B", Color.magenta);
  R.text3d(.{ .x = proj.x, .y = proj.y, .z = proj.z }, "proj", Color.yellow);

  // Dashed line from A to proj
  R.line(
    .{ .x = a.x, .y = a.y, .z = a.z },
    .{ .x = proj.x, .y = proj.y, .z = proj.z },
    Color.gray,
  );
}


/// Draw a basis (3 orthogonal arrows) at a position.
pub fn basis (R: *Renderer, origin: Vec4, right: Vec4, up: Vec4, forward: Vec4, size: f32) void {
  R.arrow(origin, .{ .x = right.x * size, .y = right.y * size, .z = right.z * size }, Color.red);
  R.arrow(origin, .{ .x = up.x * size, .y = up.y * size, .z = up.z * size }, Color.green);
  R.arrow(origin, .{ .x = forward.x * size, .y = forward.y * size, .z = forward.z * size }, Color.blue);
}


/// Draw an angle arc between two vectors at the origin.
pub fn angle (R: *Renderer, a: Vec4, b: Vec4, radius: f32, c: Color) void {
  const al = @sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
  const bl = @sqrt(b.x * b.x + b.y * b.y + b.z * b.z);
  if (al < 1e-6 or bl < 1e-6) return;

  const ax = a.x / al;
  const ay = a.y / al;
  const az = a.z / al;
  const bx = b.x / bl;
  const by = b.y / bl;
  const bz = b.z / bl;

  const segs: u32 = 24;
  const dot = ax * bx + ay * by + az * bz;
  const angle_val = std.math.acos(std.math.clamp(dot, -1.0, 1.0));

  var prev = Vec4{ .x = ax * radius, .y = ay * radius, .z = az * radius };
  for (1..segs + 1) |i| {
    const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs));
    const theta = angle_val * t;
    const sin_a = @sin(angle_val);
    if (sin_a < 1e-6) break;
    const sa = @sin(angle_val - theta) / sin_a;
    const sb = @sin(theta) / sin_a;
    const cur = Vec4{
      .x = (ax * sa + bx * sb) * radius,
      .y = (ay * sa + by * sb) * radius,
      .z = (az * sa + bz * sb) * radius,
    };
    R.line(prev, cur, c);
    prev = cur;
  }
}


/// Draw a bivector as a parallelogram from two vectors at a given origin.
pub fn bivec (R: *Renderer, origin: Vec4, a: Vec4, b: Vec4, c: Color) void {
  const tip_a = origin.add(a);
  const tip_b = origin.add(b);
  const tip_ab = origin.add(a).add(b);
  const semi = Color{ .r = c.r, .g = c.g, .b = c.b, .a = c.a * 0.25 };
  R.triangle(origin, tip_a, tip_ab, semi);
  R.triangle(origin, tip_ab, tip_b, semi);
  R.line(origin, tip_a, c);
  R.line(tip_a, tip_ab, c);
  R.line(tip_ab, tip_b, c);
  R.line(tip_b, origin, c);
}


/// Draw a reflection: original vector, mirror plane, and reflected result.
pub fn reflection (R: *Renderer, v: Vec4, mirror: Vec4) void {
  const reflected = v.reflect(mirror);
  const origin = Vec4.point(0, 0, 0);
  R.arrow(origin, v, Color.yellow);
  R.text3d(v, "v", Color.yellow);
  R.arrow(origin, reflected, Color.cyan);
  R.text3d(reflected, "reflected", Color.cyan);
  R.arrow(origin, mirror, Color.white);
  R.text3d(mirror, "mirror", Color.white);
  R.plane(origin, mirror, 1.5, Color.gray);
}

