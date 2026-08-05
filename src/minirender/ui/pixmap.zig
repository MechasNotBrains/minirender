//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
const std = @import("std");


pub fn Pixmap (comptime width :comptime_int, comptime height :comptime_int) type {
  return struct {
    pub const W :usize = width;
    pub const H :usize = height;
    const Data = std.bit_set.IntegerBitSet(W * H);
    data :Data,

    pub fn parse (comptime pattern :*const [W * H]u8) @This() {
      @setEvalBranchQuota(20000);
      var result :@This() = .{ .data = Data.initEmpty() };
      for (0..W * H) |index| {
        if (pattern[index] != ' ') result.data.set(index);
      }
      return result;
    }

    pub fn pixel (self :@This(), column :usize, row :usize) bool {
      return self.data.isSet(row * W + column);
    }
  };
}
