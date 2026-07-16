//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps minirender
const minirender = struct {
  const Color = @import("./math.zig").Color;
  const vec4  = @import("./math.zig").vec4;
};


//______________________________________
// @section Aliases
//____________________________
pub const white       = minirender.vec4(1, 1, 1, 1);
pub const black       = minirender.vec4(0, 0, 0, 1);
pub const red         = minirender.vec4(1, 0, 0, 1);
pub const green       = minirender.vec4(0, 1, 0, 1);
pub const blue        = minirender.vec4(0, 0, 1, 1);
pub const yellow      = minirender.vec4(1, 1, 0, 1);
pub const cyan        = minirender.vec4(0, 1, 1, 1);
pub const magenta     = minirender.vec4(1, 0, 1, 1);
pub const transparent = minirender.vec4(0, 0, 0, 0);


//______________________________________
// @section Conversion
//____________________________
pub fn from_hex (hex :u32) minirender.Color {
  return minirender.vec4(
    @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0,
    @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
    @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
    @as(f32, @floatFromInt(hex & 0xFF)) / 255.0,
  );
}
//__________________
pub fn from_rgb (hex :u24) minirender.Color {
  return minirender.vec4(
    @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
    @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
    @as(f32, @floatFromInt(hex & 0xFF)) / 255.0,
    1.0,
  );
}

