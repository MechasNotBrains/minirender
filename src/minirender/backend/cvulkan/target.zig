//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const target = @This();
pub const Target = @This().Type;
const This = @This();
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu   = @import("./gpu.zig").Gpu;
  const Sync  = @import("./sync.zig").Sync;
  const Depth = @import("./depth.zig").Depth;
};


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  ct :cvk.Rendering = .{},

  pub const create_args = This.create_args;
  pub const create      = This.create;
  pub const destroy     = This.destroy;
  pub const clear       = This.clear;
  pub const draw        = This.draw;
  pub const depth_bind  = This.depth_bind;
  pub const view_bind   = This.view_bind;
  pub const begin       = This.begin;
  pub const end         = This.end;
};


//_______________________________________
// @section Create/Destroy
//_____________________________
pub const create_args = cvk.Rendering.create_args;
//__________________
pub fn destroy (R :*const Type) void {
  var mutable :*Type= @constCast(R); _= &mutable;
  mutable.ct = .{};
}
//__________________
pub fn create (arg :This.create_args) Type { return .{ .ct = .create(arg) }; }
//__________________
pub fn clear (
    gpu   : *const minirender.Gpu,
    color : [4]f32,
  ) Type {
  const color_clear :cvk.vk.ClearValue= .{ .color = .{ .float32 = color } };
  const depth_clear :cvk.vk.ClearValue= .{ .depthStencil = .{ .depth = 0.0, .stencil = 0 } };
  return Type.create(.{
    .color_format        = @enumFromInt(gpu.device.swapchain.cfg.imageFormat),
    .extent              = gpu.device.swapchain.cfg.imageExtent,
    .color_load          = .clear,
    .color_clear         = &color_clear,
    .depth_stencil_load  = .clear,
    .depth_stencil_clear = &depth_clear,
    .depth_enabled       = true,
  });
}
//__________________
pub fn draw (gpu :*const minirender.Gpu) Type {
  return Type.create(.{
    .color_format  = @enumFromInt(gpu.device.swapchain.cfg.imageFormat),
    .extent        = gpu.device.swapchain.cfg.imageExtent,
    .depth_enabled = true,
  });
}


//_______________________________________
// @section Process
//_____________________________
pub fn depth_bind (R :*Type, D :*const minirender.Depth) void { R.ct.depth_stencil.view = D.view.ct; }
//__________________
pub fn view_bind (R :*Type, view :cvk.vk.ImageView) void { R.ct.color.view = view; }
//__________________
pub fn begin (
    R       : *Type,
    gpu     : *minirender.Gpu,
    S       : *minirender.Sync,
    imageID : usize,
    first   : bool,
  ) void {
  if (first) S.buffer[S.frameID].image_handle_transition(gpu.device.swapchain.images.ptr[imageID].ct, .{
    .layout_old = .undefined,
    .layout_new = .color_attachment_optimal,
    .access_trg = .initOne(.color_attachment_write),
    .stage_src  = .initOne(.top_of_pipe),
    .stage_trg  = .initOne(.color_attachment_output),
  });
  R.view_bind(gpu.device.swapchain.images.ptr[imageID].view);
  S.buffer[S.frameID].rendering_begin(.{ .rendering = &R.ct });
}
//__________________
pub fn end (
    R       : *const Type,
    gpu     : *minirender.Gpu,
    S       : *minirender.Sync,
    imageID : usize,
    last    : bool,
  ) void { _=R;
  S.buffer[S.frameID].rendering_end();
  if (last) S.buffer[S.frameID].image_handle_transition(gpu.device.swapchain.images.ptr[imageID].ct, .{
    .layout_old = .color_attachment_optimal,
    .layout_new = .present_src,
    .access_src = .initOne(.color_attachment_write),
    .stage_src  = .initOne(.color_attachment_output),
    .stage_trg  = .initOne(.bottom_of_pipe),
  });
}
