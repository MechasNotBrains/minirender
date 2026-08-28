//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const render = @This();
pub const Render = @This().Type;
pub const minirender = @This();
// @deps std
const std = @import("std");
// @deps minirender
const mstd        = @import("mstd");
const gl          = @import("mgl").v4;
const msys        = @import("msys");
const mcam        = @import("mcam");
const minp        = @import("minp");

//______________________________________
// @section Forward Exports
//____________________________
// Math
pub const math     = @import("./math.zig");
pub const Vec4     = minirender.math.Vec4;
pub const Vec3     = minirender.math.Vec3;
pub const Vec2     = minirender.math.Vec2;
pub const Rotor    = minirender.math.Rotor;
pub const Mat4     = minirender.math.Mat4;
pub const vec4     = minirender.math.vec4;
pub const vec3     = minirender.math.vec3;
pub const vec2     = minirender.math.vec2;
// Rendering
pub const color    = @import("./color.zig");
pub const Color    = minirender.color.Type;
pub const camera   = @import("mcam");
pub const Camera   = minirender.camera.Camera;
pub const geometry = @import("./geometry.zig");
pub const Vertex   = minirender.geometry.Vertex;
pub const Shape    = minirender.geometry.Shape;
pub const Instance = minirender.geometry.Instance;
pub const store    = @import("./store.zig");
pub const Store    = minirender.store.Type;
pub const Command  = minirender.store.Command;
pub const Atlas    = @import("./atlas.zig");
const backend      = struct {
  const OpenGL     = @import("./backend/opengl.zig").Type;
  const opengl     = @import("./backend/opengl.zig");
};
// UI
pub const ui       = @import("./ui.zig");
pub const Ui       = minirender.ui.Type;


//______________________________________
// @section Render
//____________________________
pub const Type = struct {
  //______________________________________
  // @section Object Fields
  //____________________________
  system          :msys.System,
  input           :minp.Manager,
  camera          :mcam.Camera,
  backend         :minirender.backend.OpenGL,
  userdata        :?*anyopaque,
  close_on_escape :bool = true,


  //______________________________________
  // @section Create/Destroy
  //____________________________
  pub fn destroy (R :*const @This()) void {
    var mutable :*@This()= @constCast(R); _=&mutable;
    mutable.backend.destroy();
    mutable.system.term();
  }
  //__________________
  pub const create_args = struct {
    title     :mstd.zstring                    = "minirender",
    debug     :bool                            = false,
    mouse     :msys.Options.Input.Mouse.Mode   = .normal,
    resizable :bool                            = true,
    userdata  :?*anyopaque                     = null,
  };
  //__________________
  pub fn create (
      io  : std.Io,
      A   : std.mem.Allocator,
      arg : @This().create_args,
    ) !@This() {
    var result :@This()= undefined;
    result.input  = .empty;
    result.system = try msys.init(io, A, .{
      .api             = .gl,
      .window          = .{
        .title         = arg.title,
        .resizable     = arg.resizable,
      },
      .gl              = .{ .version = .{ .M = 4, .m = 6 } },
      .input           = .{ .mouse = .{ .mode = arg.mouse } },
    }); //:: result.system
    try gl.load(msys.gl.getProc);
    result.camera   = mcam.Camera{};
    result.userdata = arg.userdata;
    result.backend  = try .create(A, .{ .debug= arg.debug });
    result.system.window.user = arg.userdata;
    return result;
  }

  //______________________________________
  // @section Process
  //____________________________
  pub fn close   (R :*const @This()) bool { return R.system.close(); }
  pub fn present (R :*@This()) void { R.system.present(); }
  pub fn update  (R :*@This()      ) void {
    if (R.userdata == null) {
      R.userdata = @ptrCast(R);
      R.system.window.user = R.userdata;
    }
    var events = R.system.events();
    while (events.next()) |ev| {
      R.input.event(ev);
      switch (ev) {
        .resize => |size| minirender.backend.opengl.resize(R, size.w, size.h),
        else    => {},
      }
    }
    R.camera.update(&R.camera, &R.input);
    R.input.mouse.change = .create(0,0,0,0);
    if (R.close_on_escape and R.input.key.active(.escape)) R.system.set_close(true);
  }

  //__________________
  pub fn draw  (R :*@This()) void { R.backend.draw(&R.camera); }
  pub fn clear (R :*const @This()) void { R.backend.clear(); }


  //______________________________________
  // @section Geometry
  //____________________________
  /// @descr
  ///  Returns the shapes and instances given to this renderer.
  ///  Every backend keeps them the same way, so nothing about them is dispatched.
  pub fn store (R :*@This()) *minirender.Store { return &R.backend.store; }
  //__________________
  pub fn shape (
      R     : *@This(),
      verts : []const Vertex,
      inds  : []const u32,
    ) !Shape.Id { return R.store().shape_add(verts, inds, false); }
  //__________________
  pub fn shape_alpha (
      R     : *@This(),
      verts : []const Vertex,
      inds  : []const u32,
    ) !Shape.Id { return R.store().shape_add(verts, inds, true); }
  //__________________
  pub fn instance (
      R     : *@This(),
      id    : Shape.Box.Key,
      world : minirender.Mat4,
      C     : minirender.Color,
    ) !Instance.Id { return R.store().instance_add(id, world, C); }
  //__________________
  /// @descr Drops an instance, so whatever it was drawing stops being drawn.
  pub fn instance_remove (R :*@This(), id :Instance.Id) void { R.store().instance_remove(id); }
  //__________________
  /// @descr Lets go of a shape, along with the geometry it owns.
  pub fn shape_remove (R :*@This(), id :Shape.Id) void { R.store().shape_remove(id); }
  //__________________
  pub fn reassign_instance (
      R     : *@This(),
      id    : Instance.Id,
      S     : Shape.Id,
      world : minirender.Mat4,
      C     : minirender.Color,
    ) void { R.store().instance_reassign(id, S, world, C); }
  //__________________
  pub fn set_selection_lines (
      R         : *@This(),
      positions : []const [3]f32,
      C         : [4]f32,
    ) void { R.backend.set_selection_lines(positions, C); }
  //__________________
  pub fn clear_selection_lines (R :*@This()) void { R.backend.clear_selection_lines(); }
  //__________________
  pub fn update_instance (
      R     : *@This(),
      id    : Instance.Id,
      world : minirender.Mat4,
      C     : minirender.Color,
    ) void { R.backend.update_instance(id, world, C); }

  //______________________________________
  // @section Events
  //____________________________
  pub const resize = minirender.backend.opengl.resize;
};

