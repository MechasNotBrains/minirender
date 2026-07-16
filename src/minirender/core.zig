//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const render = @This();
pub const Render = @This().Type;
// @deps std
const std = @import("std");
// @deps minirender
const msys = @import("msys");
const mgl  = @import("mgl");
const mcam = @import("mcam");
const minirender = struct {
  const opengl  = @import("./backend/opengl.zig");
  const cvulkan = @import("./backend/cvulkan.zig");
  const vulkan  = @import("./backend/vulkan.zig");
};

pub const Backend = union(enum) {
  gl   :minirender.opengl.Render,
  cvk  :minirender.cvulkan.Render,
  vk   :minirender.vulkan.Render,
};

pub const Options = struct {
  title :[:0]const u8 = "minirender",
};

const shapes = @import("./shape.zig");
const vertex = @import("./vertex.zig");

pub const ShapeKey    = shapes.ShapeKey;
pub const InstanceKey = shapes.InstanceKey;
pub const Vertex      = vertex.Vertex;

pub const Type = struct {
  system  :msys.System,
  camera  :mcam.Camera,
  backend :Backend,

  pub fn create (allocator :std.mem.Allocator, options :Options) !Type {
    const system = try msys.init(allocator, .{
      .api    = .gl,
      .window = .{ .title = options.title },
      .gl     = .{ .version = .{ .M = 4, .m = 6 } },
    });
    try mgl.v4.load(msys.gl.getProc);
    return Type{
      .system  = system,
      .camera  = mcam.Camera{},
      .backend = .{ .gl = try minirender.opengl.Render.create(allocator) },
    };
  }

  pub fn destroy (R :*Type) void {
    switch (R.backend) {
      .gl  => |*backend| backend.destroy(),
      .cvk => @panic("cvulkan backend not implemented"),
      .vk  => @panic("vulkan backend not implemented"),
    }
    R.system.term();
  }

  pub fn shape (R :*Type, vertices :[]const Vertex, indices :[]const u32) !ShapeKey {
    return switch (R.backend) {
      .gl  => |*backend| backend.shape(vertices, indices),
      .cvk => @panic("cvulkan backend not implemented"),
      .vk  => @panic("vulkan backend not implemented"),
    };
  }

  pub fn instance (R :*Type, shape_key :ShapeKey, world :[16]f32, color :[4]f32) !InstanceKey {
    return switch (R.backend) {
      .gl  => |*backend| backend.instance(shape_key, world, color),
      .cvk => @panic("cvulkan backend not implemented"),
      .vk  => @panic("vulkan backend not implemented"),
    };
  }

  pub fn sync (R :*Type) void {
    const view_projection = R.camera.view_projection();
    switch (R.backend) {
      .gl  => |*backend| backend.sync(view_projection),
      .cvk => @panic("cvulkan backend not implemented"),
      .vk  => @panic("vulkan backend not implemented"),
    }
  }

  pub fn clear (R :*const Type) void {
    switch (R.backend) {
      .gl  => |backend| backend.clear(),
      .cvk => @panic("cvulkan backend not implemented"),
      .vk  => @panic("vulkan backend not implemented"),
    }
  }

  pub fn present (R :*const Type) void { R.system.present(); }
  pub fn close   (R :*const Type) bool { return R.system.close(); }
  pub fn update  (R :*Type)       void { R.system.update(); }
};
