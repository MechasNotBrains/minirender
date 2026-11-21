//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const texture = @This();
pub const Texture = @This().Type;
const This = @This();
// @deps std
const std  = @import("std");
const mstd = @import("mstd");
const mimg = @import("mimg");
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu  = @import("./gpu.zig").Gpu;
  const Sync = @import("./sync.zig").Sync;
};


//_______________________________________
// @section Formats
//_____________________________
pub fn format (F :mimg.Image.Format) cvk.vk.Format {
  return switch (F) {
    .r8    => .r8_unorm,
    .rgba8 => .r8g8b8a8_srgb,
  };
}


//_______________________________________
// @section Object Fields
//_____________________________
pub const Id = u32;
//__________________
pub const List = mstd.seq(Type);
//__________________
pub const Type = struct {
  data     :cvk.image.Data    = .{},
  memory   :cvk.Memory        = .{},
  view     :cvk.image.View    = .{},
  sampler  :cvk.image.Sampler = .{},
  width    :u32 = 0,
  height   :u32 = 0,
  format   :mimg.Image.Format = .rgba8,

  pub const Id      = This.Id;
  pub const List    = This.List;
  pub const create  = This.create;
  pub const destroy = This.destroy;
  pub const info    = This.info;
};


//_______________________________________
// @section Create/Destroy
//_____________________________
pub fn destroy (T :*const Type, gpu :*minirender.Gpu) void {
  var mutable :*Type= @constCast(T); _= &mutable;
  mutable.sampler.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.view.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.data.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.* = .{};
}
//__________________
pub fn create (
    gpu   : *minirender.Gpu,
    S     : *const minirender.Sync,
    image : *const mimg.Image,
  ) !Type {
  if (image.len() == 0) return error.minirender_texture_EmptyImage;
  if (image.size() != image.len() * image.format.size()) return error.minirender_texture_InvalidLength;
  var result :Type= .{
    .width  = @intCast(image.width()),
    .height = @intCast(image.height()),
    .format = image.format,
  };
  result.data    = .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .format          = This.format(image.format),
    .usage           = .create(&.{ .transfer_dst, .sampled }),
    .memory_flags    = .create(.device_local),
    .dimensions      = .dim2d,
    .width           = result.width,
    .height          = result.height,
  });
  result.memory  = .create(.{
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size_alloc      = result.data.memory.requirements.size,
    .kind            = result.data.memory.kind,
  });
  result.data.bind(.{
    .device_logical  = &gpu.device.logical,
    .memory          = &result.memory,
  });
  result.view    = .create(.{
    .image_data      = &result.data,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .aspect          = .create(.color),
  });
  result.sampler = .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .filter_min      = .nearest,
    .filter_mag      = .nearest,
    .address_U       = .clamp_to_edge,
    .address_V       = .clamp_to_edge,
    .address_W       = .clamp_to_edge,
  });

  const size = image.size();
  var staging :cvk.Buffer= .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size            = size,
    .usage           = .create(.transfer_src),
    .memory_flags    = .create(&.{ .host_visible, .host_coherent }),
  });
  defer staging.destroy(&gpu.device.logical, &gpu.instance.allocator);
  var memory :cvk.Memory= .create(.{
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size_alloc      = staging.memory.requirements.size,
    .size_data       = size,
    .kind            = staging.memory.kind,
    .data            = @constCast(@ptrCast(image.bytes().ptr)),
  });
  defer memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
  staging.bind(.{
    .device_logical  = &gpu.device.logical,
    .memory          = &memory,
  });

  const buffer = S.buffer_begin_onetime(gpu);
  buffer.image_data_transition(&result.data, .{
    .layout_old = .undefined,
    .layout_new = .transfer_dst_optimal,
    .access_trg = .create(.transfer_write),
    .stage_src  = .create(.top_of_pipe),
    .stage_trg  = .create(.transfer),
    .aspect     = .create(.color),
  });
  buffer.image_data_copy_fromBuffer(&result.data, &staging, .{
    .extent       = .{ .width = result.width, .height = result.height, .depth = 1 },
    .offset_image = .{ .x = 0, .y = 0, .z = 0 },
  });
  buffer.image_data_transition(&result.data, .{
    .layout_old = .transfer_dst_optimal,
    .layout_new = .shader_read_only_optimal,
    .access_src = .create(.transfer_write),
    .access_trg = .create(.shader_read),
    .stage_src  = .create(.transfer),
    .stage_trg  = .create(.fragment_shader),
    .aspect     = .create(.color),
  });
  S.buffer_end_onetime(&buffer, gpu);
  return result;
}


//_______________________________________
// @section Descriptors
//_____________________________
pub fn info (T :*const Type) cvk.vk.DescriptorImageInfo {
  return .{
    .sampler     = T.sampler.ct,
    .imageView   = T.view.ct,
    .imageLayout = @backingInt(cvk.vk.ImageLayout.shader_read_only_optimal),
  };
}
