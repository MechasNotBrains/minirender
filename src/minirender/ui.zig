//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const ui = @This();
pub const Ui = @This().Type;
// @deps std
const std = @import("std");
// @deps minirender
const mui = @import("mui");

pub const View   = mui.View;
pub const Scene  = mui.Scene;
pub const Shape  = mui.Shape;

pub const Type = struct {
  view  :mui.View,
  scene :mui.Scene,

  pub fn create (allocator :std.mem.Allocator) !Type {
    return .{
      .view  = mui.View.create(.{}),
      .scene = try mui.Scene.create(allocator, .{}),
    };
  }

  pub fn destroy (U :*Type) void {
    U.scene.destroy();
    U.view.destroy();
  }

  pub fn add (U :*Type, shape :mui.Shape) !void {
    try U.scene.add(shape);
  }

  pub fn add_many (U :*Type, shapes :[]const mui.Shape) !void {
    try U.scene.add_many(shapes);
  }
};
