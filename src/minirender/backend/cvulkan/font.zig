//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const font = @This();
const This = @This();
// @deps minirender
const minirender = struct {
  const Gpu     = @import("./gpu.zig").Gpu;
  const Sync    = @import("./sync.zig").Sync;
  const Atlas   = @import("./atlas.zig").Atlas;
  const font5x7 = @import("../../ui/font5x7.zig");
};
const font5x7 = minirender.font5x7;


//_______________________________________
// @section Process
//_____________________________
pub const glyphs_len :u32= font5x7.glyphs.len;
//__________________
pub fn reset () void {
  font5x7.uploaded = false;
  font5x7.regions  = @splat(.{ 0, 0, 0, 0 });
}
//__________________
pub fn upload (
    A   : *minirender.Atlas,
    gpu : *minirender.Gpu,
    S   : *const minirender.Sync,
  ) void {
  if (font5x7.uploaded) return;
  var pixels :[font5x7.W * font5x7.H * 4]u8 = undefined;
  for (font5x7.glyphs, 0..) |glyph, id| {
    for (0..font5x7.H) |row| for (0..font5x7.W) |column| {
      const index = (row * font5x7.W + column) * 4;
      pixels[index + 0] = 255;
      pixels[index + 1] = 255;
      pixels[index + 2] = 255;
      pixels[index + 3] = if (glyph.pixel(column, row)) 255 else 0;
    };
    const handle = A.load(gpu, S, &pixels, .{ .width = font5x7.W, .height = font5x7.H }) orelse return;
    const offset = A.cell_offset(handle);
    const scale  = A.image_scale(handle);
    font5x7.regions[id] = .{ offset[0], offset[1], scale[0], scale[1] };
  }
  font5x7.uploaded = true;
}
