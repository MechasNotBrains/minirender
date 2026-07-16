//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const ui = @This();
pub const Ui = @This().Type;
const This = @This();
// @deps std
const std = @import("std");
// @deps minirender
const mui = @import("mui");
const minirender = struct {
  const ui = This;
  const Ui = This.Type;
};


//______________________________________
// @section Subtypes
//____________________________
pub const View  = mui.View;
pub const Scene = mui.Scene;
pub const Shape = mui.Shape;


//______________________________________
// @section minirender.Ui
//____________________________
pub const Type = struct {
  //______________________________________
  // @section Object Fields
  //____________________________
  view  :minirender.Ui.View,
  scene :minirender.Ui.Scene,


  //______________________________________
  // @section Subtypes
  //____________________________
  pub const View  = minirender.ui.View;
  pub const Scene = minirender.ui.Scene;
  pub const Shape = minirender.ui.Shape;


  //______________________________________
  // @section Create/Destroy
  //____________________________
  pub fn destroy (U :*Type) void {
    U.scene.destroy();
    U.view.destroy();
  }
  //__________________
  pub fn create (A :std.mem.Allocator) !Type {
    return .{
      .view  = minirender.Ui.View.create(.{}),
      .scene = try minirender.Ui.Scene.create(A, .{}),
    };
  }


  //______________________________________
  // @section Data Management
  //____________________________
  pub fn add      (U :*Type, shape :minirender.ui.Shape         ) !void { try U.scene.add(shape);       }
  pub fn add_many (U :*Type, shapes :[]const minirender.ui.Shape) !void { try U.scene.add_many(shapes); }
};

