//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps debug.renderer
const Vec4     = @import("../math/vector.zig").Vec4;
const Color    = @import("../color.zig").Color;
const Renderer = @import("../../minirender.zig").Renderer;


/// Draw a line segment between two points.
pub fn line (R :*Renderer, a :Vec4, b :Vec4, c :Color) void {
  R.push_vert_line(a.x, a.y, a.z, c);
  R.push_vert_line(b.x, b.y, b.z, c);
}


/// Draw a thick line as a camera-facing quad (two triangles).
pub fn thickLine (R :*Renderer, a :Vec4, b :Vec4, width :f32, c :Color) void {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const dz = b.z - a.z;
  const dl = @sqrt(dx * dx + dy * dy + dz * dz);
  if (dl < 1e-6) return;

  // Camera forward vector from view matrix (row 2)
  const fx = R.view[2];
  const fy = R.view[6];
  const fz = R.view[10];

  // Cross line direction with camera forward to get offset perpendicular to both
  var ox = dy * fz - dz * fy;
  var oy = dz * fx - dx * fz;
  var oz = dx * fy - dy * fx;
  const ol = @sqrt(ox * ox + oy * oy + oz * oz);
  if (ol < 1e-6) return;
  const hw = width * 0.5 / ol;
  ox *= hw;
  oy *= hw;
  oz *= hw;

  R.push_vert_tri(a.x - ox, a.y - oy, a.z - oz, c);
  R.push_vert_tri(a.x + ox, a.y + oy, a.z + oz, c);
  R.push_vert_tri(b.x + ox, b.y + oy, b.z + oz, c);
  R.push_vert_tri(a.x - ox, a.y - oy, a.z - oz, c);
  R.push_vert_tri(b.x + ox, b.y + oy, b.z + oz, c);
  R.push_vert_tri(b.x - ox, b.y - oy, b.z - oz, c);
}


/// Draw a point as a small cross.
pub fn point (R :*Renderer, p :Vec4, size :f32, c :Color) void {
  const s = size * 0.5;
  R.line(.{ .x = p.x - s, .y = p.y, .z = p.z }, .{ .x = p.x + s, .y = p.y, .z = p.z }, c);
  R.line(.{ .x = p.x, .y = p.y - s, .z = p.z }, .{ .x = p.x, .y = p.y + s, .z = p.z }, c);
  R.line(.{ .x = p.x, .y = p.y, .z = p.z - s }, .{ .x = p.x, .y = p.y, .z = p.z + s }, c);
}


/// Draw an arrow from `origin` to `origin + direction`.
pub fn arrow (R :*Renderer, origin :Vec4, direction :Vec4, c :Color) void {
  const tip = Vec4{
    .x = origin.x + direction.x,
    .y = origin.y + direction.y,
    .z = origin.z + direction.z,
    .w = origin.w,
  };
  R.line(origin, tip, c);

  // Small arrowhead — 3 lines from tip backwards
  const head_len: f32 = 0.08;
  const len = @sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z);
  if (len < 1e-6) return;

  const dx = direction.x / len;
  const dy = direction.y / len;
  const dz = direction.z / len;

  // Find a perpendicular vector
  var px :f32= 0;
  var py :f32= 0;
  var pz :f32= 0;
  if (@abs(dx) < 0.9) {
    // cross(d, (1,0,0))
    py = dz;
    pz = -dy;
  } else {
    // cross(d, (0,1,0))
    px = -dz;
    pz = dx;
  }
  const pl = @sqrt(px * px + py * py + pz * pz);
  if (pl < 1e-6) return;
  px /= pl;
  py /= pl;
  pz /= pl;

  // Second perpendicular
  const qx = dy * pz - dz * py;
  const qy = dz * px - dx * pz;
  const qz = dx * py - dy * px;

  const hl = head_len * len;
  const hw = hl * 0.4;

  const base_x = tip.x - dx * hl;
  const base_y = tip.y - dy * hl;
  const base_z = tip.z - dz * hl;

  const offsets = [_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
  for (offsets) |off| {
    const ox = base_x + (px * off[0] + qx * off[1]) * hw;
    const oy = base_y + (py * off[0] + qy * off[1]) * hw;
    const oz = base_z + (pz * off[0] + qz * off[1]) * hw;
    R.line(tip, .{ .x = ox, .y = oy, .z = oz }, c);
  }
}

