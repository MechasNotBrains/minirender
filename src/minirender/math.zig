//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps minirender
const mmath = @import("mmath");

//______________________________________
// @section Aliases
//____________________________
pub const Float    = mmath.vector.Float;
pub const Vec4     = mmath.vector.Vec4;
pub const vec4     = mmath.vector.vec4;
pub const Vec3     = mmath.vector.Vec3;
pub const vec3     = mmath.vector.vec3;
pub const Vec2     = mmath.vector.Vec2;
pub const vec2     = mmath.vector.vec2;
pub const Color    = mmath.vector.Color;
pub const color    = mmath.vector.color;
pub const Rotor    = mmath.vector.Rotor;
pub const rotor    = mmath.vector.rotor;
pub const Mat4     = mmath.matrix.Mat4;
pub const mat4     = mmath.matrix.mat4;
pub const Identity = Mat4.Identity;


//______________________________________
// @section Conversion
//____________________________
pub fn mat4_to_f32 (M :*const Mat4) [16]f32 {
  var result :[16]f32 = undefined;
  for (0..16) |index| result[index] = @floatCast(M.data[index]);
  return result;
}
//__________________
pub fn vec4_to_f32 (V :*const Vec4) [4]f32 {
  var result :[4]f32 = undefined;
  for (0..4) |index| result[index] = @floatCast(V.data[index]);
  return result;
}

