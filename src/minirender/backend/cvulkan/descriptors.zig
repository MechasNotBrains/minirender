//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const descriptors = @This();
pub const Descriptors = @This().Type;
const This = @This();
// @deps std
const std = @import("std");
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu    = @import("./gpu.zig").Gpu;
  const Buffer = @import("./buffer.zig").Buffer;
  const Atlas  = @import("./atlas.zig").Atlas;
  const sync   = @import("./sync.zig");
};
const sync = minirender.sync;


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  pool    :cvk.descriptor.Pool   = std.mem.zeroes(cvk.descriptor.Pool),
  layout  :cvk.descriptor.Layout = std.mem.zeroes(cvk.descriptor.Layout),
  set     :[sync.frames_Len]cvk.descriptor.Set = std.mem.zeroes([sync.frames_Len]cvk.descriptor.Set),

  pub const create         = This.create;
  pub const destroy        = This.destroy;
  pub const instances_bind = This.instances_bind;
  pub const atlas_bind     = This.atlas_bind;
};


//_______________________________________
// @section Bindings
//_____________________________
pub const instances_id = 0;
pub const atlas_id     = 1;
//__________________
fn instances_binding (buffer :?*const cvk.vk.DescriptorBufferInfo) cvk.descriptor.Binding {
  return .create(.{
    .id     = This.instances_id,
    .kind   = .storage_buffer,
    .stage  = .initOne(.vertex),
    .buffer = buffer,
  });
}
//__________________
fn atlas_binding (image :?*const cvk.vk.DescriptorImageInfo) cvk.descriptor.Binding {
  return .create(.{
    .id    = This.atlas_id,
    .kind  = .combined_image_sampler,
    .stage = .initOne(.fragment),
    .image = image,
  });
}


//_______________________________________
// @section Create/Destroy
//_____________________________
pub fn destroy (D :*const Type, gpu :*minirender.Gpu) void {
  var mutable :*Type= @constCast(D); _= &mutable;
  mutable.pool.destroy(&gpu.device.logical, &gpu.instance);
  mutable.layout.destroy(&gpu.device.logical, &gpu.instance);
}
//__________________
pub fn create (gpu :*minirender.Gpu) Type {
  var result :Type= .{};
  const instances = This.instances_binding(null);
  const atlas     = This.atlas_binding(null);
  result.layout = .create(.{
    .device_logical = &gpu.device.logical,
    .allocator      = &gpu.instance.allocator,
    .bindings       = &.{ instances.layout, atlas.layout },
  });
  result.pool   = .create(.{
    .device_logical = &gpu.device.logical,
    .allocator      = &gpu.instance.allocator,
    .max_sets       = sync.frames_Len,
    .sizes          = &.{ .{
      .type            = @intFromEnum(cvk.vk.DescriptorType.storage_buffer),
      .descriptorCount = sync.frames_Len,
    }, .{
      .type            = @intFromEnum(cvk.vk.DescriptorType.combined_image_sampler),
      .descriptorCount = sync.frames_Len,
    } },
  });
  for (0..sync.frames_Len) |id| result.set[id] = .allocate(.{
    .descriptor_pool = &result.pool,
    .device_logical  = &gpu.device.logical,
    .layouts         = &.{ result.layout },
  });
  return result;
}


//_______________________________________
// @section Process
//_____________________________
pub fn instances_bind (
    D       : *const Type,
    gpu     : *minirender.Gpu,
    frameID : usize,
    B       : *const minirender.Buffer,
  ) void {
  const info :cvk.vk.DescriptorBufferInfo= .{
    .buffer = B.vram.data.ct,
    .offset = 0,
    .range  = cvk.C.VK_WHOLE_SIZE,
  };
  const binding = This.instances_binding(&info);
  D.set[frameID].update(.{
    .device_logical = &gpu.device.logical,
    .binding        = &binding,
  });
}
//__________________
pub fn atlas_bind (
    D       : *const Type,
    gpu     : *minirender.Gpu,
    frameID : usize,
    A       : *const minirender.Atlas,
  ) void {
  const info :cvk.vk.DescriptorImageInfo= .{
    .sampler     = A.sampler.ct,
    .imageView   = A.view.ct,
    .imageLayout = @intFromEnum(cvk.vk.ImageLayout.shader_read_only_optimal),
  };
  const binding = This.atlas_binding(&info);
  D.set[frameID].update(.{
    .device_logical = &gpu.device.logical,
    .binding        = &binding,
  });
}
