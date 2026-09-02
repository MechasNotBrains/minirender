//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const depth = @This();
pub const Depth = @This().Type;
const This = @This();
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu  = @import("./gpu.zig").Gpu;
  const Sync = @import("./sync.zig").Sync;
};


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  data    :cvk.image.Data = .{},
  memory  :cvk.Memory     = .{},
  view    :cvk.image.View = .{},
  format  :cvk.vk.Format  = .undefined,

  pub const create  = This.create;
  pub const destroy = This.destroy;
};


//_______________________________________
// @section Create/Destroy
//_____________________________
pub fn destroy (D :*const Type, gpu :*minirender.Gpu) void {
  var mutable :*Type= @constCast(D); _= &mutable;
  mutable.view.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.data.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.format = .undefined;
}
//__________________
pub fn create (
    gpu    : *minirender.Gpu,
    S      : *const minirender.Sync,
    format : cvk.vk.Format,
  ) Type {
  var result :Type= .{ .format = format };
  result.data   = .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .format          = format,
    .usage           = .initOne(.depth_stencil_attachment),
    .memory_flags    = .initOne(.device_local),
    .dimensions      = .dim2d,
    .width           = gpu.device.swapchain.cfg.imageExtent.width,
    .height          = gpu.device.swapchain.cfg.imageExtent.height,
  });
  result.memory = .create(.{
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size_alloc      = result.data.memory.requirements.size,
    .kind            = result.data.memory.kind,
  });
  result.data.bind(.{
    .device_logical  = &gpu.device.logical,
    .memory          = &result.memory,
  });
  result.view   = .create(.{
    .image_data      = &result.data,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .aspect          = .initOne(.depth),
  });
  const buffer = S.buffer_begin_onetime(gpu);
  buffer.image_data_transition(&result.data, .{
    .layout_old = .undefined,
    .layout_new = .depth_attachment_optimal,
    .access_trg = .initMany(&.{ .depth_stencil_attachment_read, .depth_stencil_attachment_write }),
    .stage_src  = .initOne(.top_of_pipe),
    .stage_trg  = .initOne(.early_fragment_tests),
    .aspect     = .initOne(.depth),
  });
  S.buffer_end_onetime(&buffer, gpu);
  return result;
}
