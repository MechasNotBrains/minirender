//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// Bitfont text drawing in 3D
// @deps std
const std = @import("std");
// @deps debug.renderer
const Vec4     = @import("../math/vector.zig").Vec4;
const Color    = @import("../color.zig").Color;
const font     = @import("../font.zig");
const Renderer = @import("../../minirender.zig").Renderer;


/// Draw text at a 3D position. The text is drawn as tiny line
/// segments using the 5×7 bitfont, billboarded toward the camera.
/// `glyph_size` controls how big each pixel of the font is in
/// world units.
pub fn text3d (R: *Renderer, pos: Vec4, text: []const u8, c: Color) void {
  R.text3dSized(pos, text, c, 0.012);
}


pub fn text3dSized (R: *Renderer, pos: Vec4, text: []const u8, c: Color, glyph_size: f32) void {
  // Billboard vectors from the view matrix (rows of the 3×3 = camera right/up)
  const m = R.view.data;
  var rx :f32 = @floatCast(m[0]);
  var ry :f32 = @floatCast(m[4]);
  var rz :f32 = @floatCast(m[8]);
  var rl = @sqrt(rx * rx + ry * ry + rz * rz);
  if (rl < 1e-6) rl = 1;
  rx /= rl;
  ry /= rl;
  rz /= rl;

  var ux :f32 = @floatCast(m[1]);
  var uy :f32 = @floatCast(m[5]);
  var uz :f32 = @floatCast(m[9]);
  var ul = @sqrt(ux * ux + uy * uy + uz * uz);
  if (ul < 1e-6) ul = 1;
  ux /= ul;
  uy /= ul;
  uz /= ul;

  const s = glyph_size;
  var cursor_x: f32 = 0;

  for (text) |ch| {
    if (ch < 0x20 or ch > 0x7E) {
      cursor_x += 6;
      continue;
    }

    for (0..5) |col_idx| {
      const col: u3 = @intCast(col_idx);
      for (0..7) |row_idx| {
        const row: u3 = @intCast(row_idx);
        if (!font.glyphPixel(ch, col, row)) continue;

        // Position of this pixel
        const px_x = cursor_x + @as(f32, @floatFromInt(col));
        const px_y = -@as(f32, @floatFromInt(row)); // Y goes up
        const offset_x = px_x * s;
        const offset_y = px_y * s;

        const wx = pos.x + rx * offset_x + ux * offset_y;
        const wy = pos.y + ry * offset_x + uy * offset_y;
        const wz = pos.z + rz * offset_x + uz * offset_y;

        // Draw pixel as a tiny quad (two triangles), slightly oversized to fill gaps
        const hs = s * 0.55;
        const x0 = wx - rx * hs - ux * hs;
        const y0 = wy - ry * hs - uy * hs;
        const z0 = wz - rz * hs - uz * hs;

        const x1 = wx + rx * hs - ux * hs;
        const y1 = wy + ry * hs - uy * hs;
        const z1 = wz + rz * hs - uz * hs;

        const x2 = wx + rx * hs + ux * hs;
        const y2 = wy + ry * hs + uy * hs;
        const z2 = wz + rz * hs + uz * hs;

        const x3 = wx - rx * hs + ux * hs;
        const y3 = wy - ry * hs + uy * hs;
        const z3 = wz - rz * hs + uz * hs;

        R.push_vert_text(x0, y0, z0, c);
        R.push_vert_text(x1, y1, z1, c);
        R.push_vert_text(x2, y2, z2, c);
        R.push_vert_text(x0, y0, z0, c);
        R.push_vert_text(x2, y2, z2, c);
        R.push_vert_text(x3, y3, z3, c);
      }
    }
    cursor_x += 6; // 5 pixel glyph + 1 pixel gap
  }
}

pub fn textScreen (
    R          : *Renderer,
    screen_x   : f32,
    screen_y   : f32,
    text       : []const u8,
    color      : Color,
    pixel_size : f32,
  ) void {
  var cursor_x: f32 = 0;
  for (text) |ch| {
    if (ch < 0x20 or ch > 0x7E) { cursor_x += 6; continue; }
    for (0..5) |col_idx| {
      const col: u3 = @intCast(col_idx);
      for (0..7) |row_idx| {
        const row: u3 = @intCast(row_idx);
        if (!font.glyphPixel(ch, col, row)) continue;
        const px = screen_x + (cursor_x + @as(f32, @floatFromInt(col))) * pixel_size;
        const py = screen_y + @as(f32, @floatFromInt(row)) * pixel_size;
        const hs = pixel_size * 0.55;
        R.push_vert_tri(px,      py,      0, color);
        R.push_vert_tri(px + hs, py,      0, color);
        R.push_vert_tri(px + hs, py + hs, 0, color);
        R.push_vert_tri(px,      py,      0, color);
        R.push_vert_tri(px + hs, py + hs, 0, color);
        R.push_vert_tri(px,      py + hs, 0, color);
      }
    }
    cursor_x += 6;
  }
}

/// Format and draw a Vec4's numeric values at a position.
pub fn vec4Label (R: *Renderer, pos: Vec4, v: Vec4, name: []const u8, c: Color) void {
  var buf: [128]u8 = undefined;
  const s = std.fmt.bufPrint(&buf, "{s}({d:.2},{d:.2},{d:.2},{d:.2})", .{ name, v.x, v.y, v.z, v.w }) catch return;
  R.text3d(pos, s, c);
}

