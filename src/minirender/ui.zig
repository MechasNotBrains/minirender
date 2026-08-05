//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const ui = @This();
pub const Ui = @This().Type;
const This = @This();
const std = @import("std");
const mui = @import("mui");
const minirender = struct {
  const ui = This;
  const Ui = This.Type;
  const opengl  = @import("./backend/opengl/ui.zig");
  const cvulkan = struct { pub const Render = void; };
  const vulkan  = struct { pub const Render = void; };
};


pub const View    = mui.View;
pub const Scene   = mui.Scene;
pub const Shape   = mui.Shape;
pub const Pixmap  = @import("./ui/pixmap.zig").Pixmap;
pub const font5x7 = @import("./ui/font5x7.zig");
pub const tree    = @import("./ui/tree.zig");
pub const Tree    = tree.Type;


pub const Backend = union(enum) {
  gl  :minirender.opengl.Render,
  cvk :minirender.cvulkan.Render,
  vk  :minirender.vulkan.Render,
};


pub const Type = struct {
  view    :minirender.Ui.View,
  scene   :minirender.Ui.Scene,
  backend :Backend,

  pub const View  = minirender.ui.View;
  pub const Scene = minirender.ui.Scene;
  pub const Shape = minirender.ui.Shape;


  pub fn destroy (U :*Type) void {
    switch (U.backend) {
      .gl  => |*backend| backend.destroy(),
      .cvk => @panic("cvulkan ui backend not implemented"),
      .vk  => @panic("vulkan ui backend not implemented"),
    }
    U.scene.destroy();
    U.view.destroy();
  }

  pub fn create (A :std.mem.Allocator) !Type {
    return .{
      .view    = minirender.Ui.View.create(.{}),
      .scene   = try minirender.Ui.Scene.create(A, .{}),
      .backend = .{ .gl = try minirender.opengl.Render.create() },
    };
  }


  pub fn add      (U :*Type, shape :minirender.ui.Shape         ) !void { try U.scene.add(shape);       }
  pub fn add_many (U :*Type, shapes :[]const minirender.ui.Shape) !void { try U.scene.add_many(shapes); }

  pub fn sync (U :*Type, screen_width :f32, screen_height :f32) void {
    switch (U.backend) {
      .gl  => |*backend| backend.sync(&U.scene, screen_width, screen_height),
      .cvk => @panic("cvulkan ui backend not implemented"),
      .vk  => @panic("vulkan ui backend not implemented"),
    }
  }
};
