//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
const mstd = @import("mstd");
const minirender = struct {
  const Mat4  = @import("./math.zig").Mat4;
  const Color = @import("./math.zig").Color;
};

pub const Shape = struct {
  base_vertex  :i32,
  first_index  :u32,
  index_count  :u32,
  pub const Box = mstd.Box(Shape);
  pub const Id  = Box.Key;
};

pub const Instance = struct {
  shape  :Shape.Box.Key,
  world  :minirender.Mat4,
  color  :minirender.Color,
  pub const Box = mstd.Box(Instance);
  pub const Id  = Box.Key;
};


pub const Vertex = extern struct {
  position :[3]f32 = .{ 0, 0, 0 },
  normal   :[3]f32 = .{ 0, 0, 0 },
};

pub const GpuInstanceData = extern struct {
  world :[16]f32 = .{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  },
  color :[4]f32 = .{ 1, 1, 1, 1 },
};

