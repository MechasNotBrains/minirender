//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
const mstd = @import("mstd");

pub const Shape = struct {
  base_vertex :i32,
  first_index :u32,
  index_count :u32,
};

pub const Instance = struct {
  shape :ShapeKey,
  world :[16]f32,
  color :[4]f32,
};

pub const ShapeBox    = mstd.Box(Shape);
pub const InstanceBox = mstd.Box(Instance);
pub const ShapeKey    = ShapeBox.Key;
pub const InstanceKey = InstanceBox.Key;
