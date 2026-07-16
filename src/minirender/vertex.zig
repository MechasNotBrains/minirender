//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________

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
