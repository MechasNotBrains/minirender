//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps std
const std = @import("std");
// @deps debug.renderer
const Vec4     = @import("../math/vector.zig").Vec4;
const Color    = @import("../color.zig").Color;
const Renderer = @import("../../minirender.zig").Renderer;


/// Draw a filled triangle.
pub fn triangle (R :*Renderer, a :Vec4, b :Vec4, cv :Vec4, c :Color) void {
  R.push_vert_tri(a.x, a.y, a.z, c);
  R.push_vert_tri(b.x, b.y, b.z, c);
  R.push_vert_tri(cv.x, cv.y, cv.z, c);
}


/// Draw a plane (small quad) at a point with a normal.
pub fn plane (R: *Renderer, center: Vec4, normal: Vec4, size: f32, c: Color) void {
  const nl = @sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
  if (nl < 1e-6) return;
  const nx = normal.x / nl;
  const ny = normal.y / nl;
  const nz = normal.z / nl;

  // Tangent
  var tx: f32 = 0;
  var ty: f32 = 0;
  var tz: f32 = 0;
  if (@abs(nx) < 0.9) {
    ty = nz;
    tz = -ny;
  } else {
    tx = -nz;
    tz = nx;
  }
  const tl = @sqrt(tx * tx + ty * ty + tz * tz);
  tx /= tl;
  ty /= tl;
  tz /= tl;

  const bx = ny * tz - nz * ty;
  const by = nz * tx - nx * tz;
  const bz = nx * ty - ny * tx;

  const s = size * 0.5;
  const corners = [4]Vec4{
    .{ .x= center.x + (-tx - bx) * s, .y= center.y + (-ty - by) * s, .z= center.z + (-tz - bz) * s },
    .{ .x= center.x + ( tx - bx) * s, .y= center.y + ( ty - by) * s, .z= center.z + ( tz - bz) * s },
    .{ .x= center.x + ( tx + bx) * s, .y= center.y + ( ty + by) * s, .z= center.z + ( tz + bz) * s },
    .{ .x= center.x + (-tx + bx) * s, .y= center.y + (-ty + by) * s, .z= center.z + (-tz + bz) * s },
  };

  const semi = Color{ .r = c.r, .g = c.g, .b = c.b, .a = c.a * 0.3 };
  R.triangle(corners[0], corners[1], corners[2], semi);
  R.triangle(corners[0], corners[2], corners[3], semi);
  // Outline
  for (0..4) |i| {
    R.line(corners[i], corners[(i + 1) % 4], c);
  }
}


/// Draw a wireframe box (axis-aligned).
pub fn box (R: *Renderer, min: Vec4, max: Vec4, c: Color) void {
  const corners = [8]Vec4{
    .{ .x = min.x, .y = min.y, .z = min.z },
    .{ .x = max.x, .y = min.y, .z = min.z },
    .{ .x = max.x, .y = max.y, .z = min.z },
    .{ .x = min.x, .y = max.y, .z = min.z },
    .{ .x = min.x, .y = min.y, .z = max.z },
    .{ .x = max.x, .y = min.y, .z = max.z },
    .{ .x = max.x, .y = max.y, .z = max.z },
    .{ .x = min.x, .y = max.y, .z = max.z },
  };
  const edges = [12][2]u8{
    .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 },
    .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 4 },
    .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 },
  };
  for (edges) |e| {
    R.line(corners[e[0]], corners[e[1]], c);
  }
}


/// Draw a wireframe circle in the XY plane (Z-up).
pub fn circle (R: *Renderer, center: Vec4, radius: f32, segments: u32, c: Color) void {
  const segs: f32 = @floatFromInt(segments);
  var i: u32 = 0;
  while (i < segments) : (i += 1) {
    const a0 = @as(f32, @floatFromInt(i)) / segs * std.math.pi * 2.0;
    const a1 = @as(f32, @floatFromInt(i + 1)) / segs * std.math.pi * 2.0;
    R.line(
      .{ .x = center.x + @cos(a0) * radius, .y = center.y + @sin(a0) * radius, .z = center.z },
      .{ .x = center.x + @cos(a1) * radius, .y = center.y + @sin(a1) * radius, .z = center.z },
      c,
    );
  }
}


/// Draw a wireframe sphere (3 orthogonal rings: XY, XZ, YZ).
pub fn sphere (R: *Renderer, center: Vec4, radius: f32, c: Color) void {
  const segs: u32 = 32;
  const s_f: f32 = @floatFromInt(segs);
  var i: u32 = 0;
  while (i < segs) : (i += 1) {
    const a0 = @as(f32, @floatFromInt(i)) / s_f * std.math.pi * 2.0;
    const a1 = @as(f32, @floatFromInt(i + 1)) / s_f * std.math.pi * 2.0;
    // XY ring
    R.line(
      .{ .x= center.x + @cos(a0) * radius, .y= center.y + @sin(a0) * radius, .z= center.z },
      .{ .x= center.x + @cos(a1) * radius, .y= center.y + @sin(a1) * radius, .z= center.z },
      c,
    );
    // XZ ring
    R.line(
      .{ .x= center.x + @cos(a0) * radius, .y= center.y, .z= center.z + @sin(a0) * radius },
      .{ .x= center.x + @cos(a1) * radius, .y= center.y, .z= center.z + @sin(a1) * radius },
      c,
    );
    // YZ ring
    R.line(
      .{ .x= center.x, .y= center.y + @cos(a0) * radius, .z= center.z + @sin(a0) * radius },
      .{ .x= center.x, .y= center.y + @cos(a1) * radius, .z= center.z + @sin(a1) * radius },
      c,
    );
  }
}

