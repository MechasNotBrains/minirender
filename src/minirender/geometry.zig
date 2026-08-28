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
  /// How many vertices the shape owns from `base_vertex` on.
  /// Without it there is no telling where one shape's vertices end once another between them
  /// has been let go of.
  vertex_count :u32 = 0,
  /// Whether the shape holds see-through faces, drawn after every opaque one.
  alpha        :bool = false,
  center       :[3]f32 = .{ 0, 0, 0 },
  extent       :[3]f32 = .{ 0, 0, 0 },
  pub const Box = mstd.Box(Shape);
  pub const Id  = Box.Key;

  pub const Bounds = struct { center :[3]f32 = .{ 0, 0, 0 }, extent :[3]f32 = .{ 0, 0, 0 } };

  pub fn bounds (verts :[]const Vertex) Bounds {
    if (verts.len == 0) return .{};
    var low  = verts[0].position;
    var high = verts[0].position;
    for (verts[1..]) |vertex| for (0..3) |axis| {
      low[axis]  = @min(low[axis],  vertex.position[axis]);
      high[axis] = @max(high[axis], vertex.position[axis]);
    };
    var result :Bounds= .{};
    for (0..3) |axis| {
      result.center[axis] = (high[axis] + low[axis]) * 0.5;
      result.extent[axis] = (high[axis] - low[axis]) * 0.5;
    }
    return result;
  }
};

pub const Instance = struct {
  shape      :Shape.Box.Key,
  world      :minirender.Mat4,
  color      :minirender.Color,
  gpu_offset :?u32 = null,
  pub const Box = mstd.Box(Instance);
  pub const Id  = Box.Key;
  pub const Gpu = GpuInstanceData;
};


pub const Vertex = extern struct {
  position     :[3]f32 = .{ 0, 0, 0 },
  normal       :[3]f32 = .{ 0, 0, 0 },
  uv           :[2]f32 = .{ 0, 0 },
  atlas_offset :[2]f32 = .{ 0, 0 },
  atlas_scale  :[2]f32 = .{ 0, 0 },
  color        :[4]f32 = .{ 1, 1, 1, 1 },
};

pub const GpuInstanceData = extern struct {
  world :[16]f32 = .{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  },
  color  :[4]f32 = .{ 1, 1, 1, 1 },
  center :[4]f32 = .{ 0, 0, 0, 1 },
  extent :[4]f32 = .{ 0, 0, 0, 0 },
};

