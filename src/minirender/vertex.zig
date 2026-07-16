//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps minirender
const minirender = struct {
  const Vec3  = @import("./math.zig").Vec3;
  const Vec2  = @import("./math.zig").Vec2;
  const Color = @import("./math.zig").Color;
  const vec4  = @import("./math.zig").vec4;
  const vec3  = @import("./math.zig").vec3;
  const vec2  = @import("./math.zig").vec2;
};

pub const Vertex = extern struct {
  position  :minirender.Vec3=  minirender.vec3(0, 0, 0),
  color     :minirender.Color= minirender.vec4(1, 1, 1, 1),
  uv        :minirender.Vec2=  minirender.vec2(0, 0),
};
