//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const render = @This();
pub const Render = @This().Type;
// @deps std
const std = @import("std");
// @deps minirender
const mstd       = @import("mstd");
const msys       = @import("msys");
const mgl        = @import("mgl");
const mcam       = @import("mcam");
const minp       = @import("minp");
const minirender = struct {
  const Mat4     = @import("./math.zig").Mat4;
  const Color    = @import("./math.zig").Color;
  const opengl   = @import("./backend/opengl.zig");
  const cvulkan  = @import("./backend/cvulkan.zig");
  const vulkan   = @import("./backend/vulkan.zig");
};


//______________________________________
// @section Subtypes
//____________________________
pub const Shape    = @import("./geometry.zig").Shape;
pub const Instance = @import("./geometry.zig").Instance;
pub const Vertex   = @import("./geometry.zig").Vertex;
pub const Backend  = union(enum) {
  gl   :minirender.opengl.Render,
  cvk  :minirender.cvulkan.Render,
  vk   :minirender.vulkan.Render,
};


//______________________________________
// @section Render
//____________________________
pub const Type = struct {
  //______________________________________
  // @section Object Fields
  //____________________________
  system   :msys.System,
  input    :minp.Manager,
  camera   :mcam.Camera,
  backend  :Backend,


  //______________________________________
  // @section Create/Destroy
  //____________________________
  pub fn destroy (R :*Type) void {
    switch (R.backend) {
      .gl  => |*backend| backend.destroy(),
      .cvk => @panic("cvulkan backend not implemented"),
      .vk  => @panic("vulkan backend not implemented"),
    }
    R.input.destroy();
    R.system.term();
  }
  //__________________
  pub const create_args = struct {
    title  :mstd.zstring = "minirender",
    debug  :bool         = false,
  };
  //__________________
  pub fn create (
      A   : std.mem.Allocator,
      arg : Type.create_args,
    ) !Type {
    var result :Type= undefined;
    result.input  = minp.Manager.create(A, .{});
    result.system = try msys.init(A, .{
      .api             = .gl,
      .window          = .{ .title   = arg.title },
      .gl              = .{ .version = .{ .M = 4, .m = 6 } },
      .input           = .{
        .mouse         = .{ .mode = .disabled },
        .cb            = .{
          .key         = result.input.key.cb,
          .mouseBtn    = result.input.mouse.cb.btn,
          .mousePos    = result.input.mouse.cb.pos,
          .mouseScroll = result.input.mouse.cb.scroll,
        }, //:: result.system.input.cb
      }, //:: result.system.input
    }); //:: result.system
    try mgl.v4.load(msys.gl.getProc);
    result.camera  = mcam.Camera{};
    result.backend = .{.gl= try minirender.opengl.Render.create(A, .{ .debug= arg.debug }) };
    return result;
  }

  //______________________________________
  // @section Process
  //____________________________
  pub fn close   (R :*const Type) bool { return R.system.close(); }
  pub fn present (R :*const Type) void { R.system.present(); }
  pub fn update  (R :*Type      ) void {
    R.system.update();
    R.camera.update(&R.camera, &R.input);
    R.input.mouse.change_reset();
    if (R.input.key.active(.escape)) R.system.set_close(true);
  }
  //__________________
  pub fn sync (R :*Type) void {
    switch (R.backend) {
      .gl  => |*backend| backend.sync(&R.camera),
      .cvk => @panic("cvulkan backend not implemented"),
      .vk  => @panic("vulkan backend not implemented"),
    }
  }
  //__________________
  pub fn clear (R :*const Type) void { switch (R.backend) {
    .gl  => |backend| backend.clear(),
    .cvk => @panic("cvulkan backend not implemented"),
    .vk  => @panic("vulkan backend not implemented"),
  }}


  //______________________________________
  // @section Geometry
  //____________________________
  pub fn shape (
      R     : *Type,
      verts : []const Vertex,
      inds  : []const u32,
    ) !Shape.Id { return switch (R.backend) {
    .gl  => |*backend| backend.shape(verts, inds),
    .cvk => @panic("cvulkan backend not implemented"),
    .vk  => @panic("vulkan backend not implemented"),
  };}
  //__________________
  pub fn instance (
      R     : *Type,
      id    : Shape.Box.Key,
      world : minirender.Mat4,
      color : minirender.Color,
    ) !Instance.Id { return switch (R.backend) {
    .gl  => |*backend| backend.instance(id, world, color),
    .cvk => @panic("cvulkan backend not implemented"),
    .vk  => @panic("vulkan backend not implemented"),
  };}
};

