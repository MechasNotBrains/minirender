//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const cull = @This();
pub const Cull = @This().Type;
const This = @This();
// @deps std
const std = @import("std");
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu     = @import("./gpu.zig").Gpu;
  const Sync    = @import("./sync.zig").Sync;
  const sync    = @import("./sync.zig");
  const Buffer  = @import("./buffer.zig").Buffer;
  const Host    = @import("./buffer.zig").buffer.Host;
  const Command = @import("../../store.zig").Command;
  const GpuInstanceData = @import("../../geometry.zig").GpuInstanceData;
};
const sync = minirender.sync;


//_______________________________________
// @section Constants
//_____________________________
pub const group_size   = 64;
pub const planes_len   = 6;
pub const counters_len = 3;


//_______________________________________
// @section Push Constants
//_____________________________
pub const Push = extern struct {
  planes       :[This.planes_len][4]f32 = @splat(.{ 0, 0, 0, 0 }),
  commands_len :u32 = 0,
  opaque_len   :u32 = 0,
};


//_______________________________________
// @section Frustum
//_____________________________
inline fn add (a :[4]f32, b :[4]f32) [4]f32 { return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3] }; }
inline fn sub (a :[4]f32, b :[4]f32) [4]f32 { return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3] }; }
//__________________
pub fn planes (viewProjection :*const [16]f32) [This.planes_len][4]f32 {
  const M = viewProjection;
  const col :[4][4]f32 = .{
    .{ M[0],  M[4],  M[8],  M[12] },
    .{ M[1],  M[5],  M[9],  M[13] },
    .{ M[2],  M[6],  M[10], M[14] },
    .{ M[3],  M[7],  M[11], M[15] },
  };
  var result :[This.planes_len][4]f32= .{
    This.add(col[3], col[0]),
    This.sub(col[3], col[0]),
    This.add(col[3], col[1]),
    This.sub(col[3], col[1]),
    col[2],
    This.sub(col[3], col[2]),
  };
  for (&result) |*plane| {
    const length = @sqrt(plane[0] * plane[0] + plane[1] * plane[1] + plane[2] * plane[2]);
    if (length == 0.0) continue;
    for (plane) |*component| component.* /= length;
  }
  return result;
}


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  shader     :cvk.Shader             = .{},
  compute    :cvk.pipeline.Compute   = .{},
  pool       :cvk.descriptor.Pool    = std.mem.zeroes(cvk.descriptor.Pool),
  layout     :cvk.descriptor.Layout  = std.mem.zeroes(cvk.descriptor.Layout),
  set        :[sync.frames_Len]cvk.descriptor.Set = std.mem.zeroes([sync.frames_Len]cvk.descriptor.Set),
  instances  :[sync.frames_Len]minirender.Buffer = @splat(.{ .usage = .initMany(&.{ .storage_buffer, .transfer_src }) }),
  commands   :[sync.frames_Len]minirender.Buffer = @splat(.{ .usage = .initMany(&.{ .indirect_buffer, .storage_buffer, .transfer_src }) }),
  counters   :[sync.frames_Len]minirender.Buffer = @splat(.{ .usage = .initMany(&.{ .indirect_buffer, .storage_buffer, .transfer_src }) }),

  pub const Push    = This.Push;
  pub const planes  = This.planes;
  pub const create   = This.create;
  pub const destroy  = This.destroy;
  pub const resize   = This.resize;
  pub const record   = This.record;
  pub const counters_read = This.counters_read;
  pub const buffer_read   = This.buffer_read;
};
//__________________
pub const Counters = extern struct {
  opaque_len   :u32 = 0,
  alpha_len    :u32 = 0,
  instance_len :u32 = 0,
};


//_______________________________________
// @section Bindings
//_____________________________
pub const bindings_len = 5;
//__________________
fn binding (id :u32, buffer :?*const cvk.vk.DescriptorBufferInfo) cvk.descriptor.Binding {
  return .create(.{
    .id     = id,
    .kind   = .storage_buffer,
    .stage  = .initOne(.compute),
    .buffer = buffer,
  });
}


//_______________________________________
// @section SpirV Module
//_____________________________
const module = struct {
  const array align(@alignOf(u32)) = @embedFile("./shaders/cull.comp.spv").*;
  const code :[]const u32 = @ptrCast(@alignCast(&array));
};


//_______________________________________
// @section Create/Destroy
//_____________________________
pub fn destroy (C :*const Type, gpu :*minirender.Gpu) void {
  var mutable :*Type= @constCast(C); _= &mutable;
  for (&mutable.instances) |*B| B.destroy(gpu);
  for (&mutable.commands)  |*B| B.destroy(gpu);
  for (&mutable.counters)  |*B| B.destroy(gpu);
  mutable.compute.destroy(&gpu.device.logical, &gpu.instance);
  mutable.pool.destroy(&gpu.device.logical, &gpu.instance);
  mutable.layout.destroy(&gpu.device.logical, &gpu.instance);
  mutable.shader.destroy(&gpu.device.logical, &gpu.instance);
}
//__________________
pub fn create (gpu :*minirender.Gpu) Type {
  var result :Type= .{};
  result.shader = .create(.{
    .device_logical = &gpu.device.logical,
    .allocator      = &gpu.instance.allocator,
    .stage          = .initOne(.compute),
    .code           = This.module.code,
  });

  var layout_bindings :[This.bindings_len]cvk.vk.DescriptorSetLayoutBinding= undefined;
  for (&layout_bindings, 0..) |*entry, id| entry.* = This.binding(@intCast(id), null).layout;
  result.layout = .create(.{
    .device_logical = &gpu.device.logical,
    .allocator      = &gpu.instance.allocator,
    .bindings       = &layout_bindings,
  });
  result.pool   = .create(.{
    .device_logical = &gpu.device.logical,
    .allocator      = &gpu.instance.allocator,
    .max_sets       = sync.frames_Len,
    .sizes          = &.{ .{
      .type            = @intFromEnum(cvk.vk.DescriptorType.storage_buffer),
      .descriptorCount = sync.frames_Len * This.bindings_len,
    } },
  });
  for (0..sync.frames_Len) |id| result.set[id] = .allocate(.{
    .descriptor_pool = &result.pool,
    .device_logical  = &gpu.device.logical,
    .layouts         = &.{ result.layout },
  });

  result.compute = .create(.{
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .shader          = &result.shader,
    .sets            = &.{ result.layout.ct },
    .pushConstants   = &.{ .{
      .stageFlags    = cvk.vk.ShaderStage.Flags.initOne(.compute).bits.mask,
      .offset        = 0,
      .size          = @sizeOf(This.Push),
    } },
  });
  return result;
}


//_______________________________________
// @section Process
//_____________________________
fn buffer_fit (B :*minirender.Buffer, gpu :*minirender.Gpu, bytes :usize) void {
  if (B.size >= bytes) return;
  const usage = B.usage;
  gpu.device.wait();
  B.destroy(gpu);
  B.* = .create(gpu, bytes, usage, null);
}
//__________________
pub fn resize (
    C             : *Type,
    gpu           : *minirender.Gpu,
    S             : *const minirender.Sync,
    instances_len : usize,
    commands_len  : usize,
  ) void {
  This.buffer_fit(&C.instances[S.frameID], gpu, instances_len * @sizeOf(minirender.GpuInstanceData));
  This.buffer_fit(&C.commands[S.frameID],  gpu, commands_len  * @sizeOf(minirender.Command));
  This.buffer_fit(&C.counters[S.frameID],  gpu, This.counters_len * @sizeOf(u32));
}
//__________________
pub fn counters_read (
    C   : *const Type,
    gpu : *minirender.Gpu,
    S   : *const minirender.Sync,
  ) This.Counters {
  const frameID = (S.frameID + sync.frames_Len - 1) % sync.frames_Len;
  if (C.counters[frameID].size == 0) return .{};
  gpu.device.wait();

  var readback :cvk.Buffer= .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size            = @sizeOf(This.Counters),
    .usage           = .initOne(.transfer_dst),
    .memory          = .initMany(&.{ .host_visible, .host_coherent }),
  });
  defer readback.destroy(&gpu.device.logical, &gpu.instance.allocator);
  var memory :cvk.Memory= .create(.{
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size_alloc      = readback.memory.requirements.size,
    .size_data       = @sizeOf(This.Counters),
    .kind            = readback.memory.kind,
    .persistent      = true,
  });
  defer memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
  readback.bind(.{
    .device_logical  = &gpu.device.logical,
    .memory          = &memory,
  });

  const buffer = S.buffer_begin_onetime(gpu);
  buffer.buffer_copy(&C.counters[frameID].vram.data, &readback);
  S.buffer_end_onetime(&buffer, gpu);

  const src :*const This.Counters= @ptrCast(@alignCast(memory.data orelse return .{}));
  return src.*;
}
//__________________
pub fn buffer_read (
    C     : *const Type,
    gpu   : *minirender.Gpu,
    S     : *const minirender.Sync,
    which : enum { instances, commands },
    trg   : []u8,
  ) void {
  const frameID = (S.frameID + sync.frames_Len - 1) % sync.frames_Len;
  const src = switch (which) {
    .instances => &C.instances[frameID],
    .commands  => &C.commands[frameID],
  };
  if (src.size == 0 or trg.len == 0) return;
  gpu.device.wait();

  var readback :cvk.Buffer= .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size            = src.size,
    .usage           = .initOne(.transfer_dst),
    .memory          = .initMany(&.{ .host_visible, .host_coherent }),
  });
  defer readback.destroy(&gpu.device.logical, &gpu.instance.allocator);
  var memory :cvk.Memory= .create(.{
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size_alloc      = readback.memory.requirements.size,
    .size_data       = src.size,
    .kind            = readback.memory.kind,
    .persistent      = true,
  });
  defer memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
  readback.bind(.{ .device_logical = &gpu.device.logical, .memory = &memory });

  const buffer = S.buffer_begin_onetime(gpu);
  buffer.buffer_copy(&src.vram.data, &readback);
  S.buffer_end_onetime(&buffer, gpu);

  const mapped :[*]const u8 = @ptrCast(@alignCast(memory.data orelse return));
  const bytes_len = @min(trg.len, src.size);
  @memcpy(trg[0..bytes_len], mapped[0..bytes_len]);
}
//__________________
pub fn record (
    C             : *const Type,
    gpu           : *minirender.Gpu,
    S             : *const minirender.Sync,
    instances_src : *const minirender.Host,
    commands_src  : *const minirender.Buffer,
    push          : *const This.Push,
  ) void {
  const frameID = S.frameID;
  const info = [_]cvk.vk.DescriptorBufferInfo{
    .{ .buffer = instances_src.data.ct,           .offset = 0, .range = cvk.C.VK_WHOLE_SIZE },
    .{ .buffer = C.instances[frameID].vram.data.ct, .offset = 0, .range = cvk.C.VK_WHOLE_SIZE },
    .{ .buffer = commands_src.vram.data.ct,       .offset = 0, .range = cvk.C.VK_WHOLE_SIZE },
    .{ .buffer = C.commands[frameID].vram.data.ct,  .offset = 0, .range = cvk.C.VK_WHOLE_SIZE },
    .{ .buffer = C.counters[frameID].vram.data.ct,  .offset = 0, .range = cvk.C.VK_WHOLE_SIZE },
  };
  for (&info, 0..) |*entry, id| {
    const entry_binding = This.binding(@intCast(id), entry);
    C.set[frameID].update(.{
      .device_logical = &gpu.device.logical,
      .binding        = &entry_binding,
    });
  }

  S.buffer[frameID].buffer_fill(&C.counters[frameID].vram.data, 0);
  S.buffer[frameID].buffer_sync(&C.counters[frameID].vram.data, .{
    .access_src = .initOne(.transfer_write),
    .access_trg = .initMany(&.{ .shader_read, .shader_write }),
    .stage_src  = .initOne(.transfer),
    .stage_trg  = .initOne(.compute_shader),
  });

  S.buffer[frameID].compute_bind(&C.compute);
  S.buffer[frameID].constants_push(.{
    .pipeline_layout = &C.compute.layout,
    .stage           = .initOne(.compute),
    .size            = @sizeOf(This.Push),
    .data            = @constCast(@ptrCast(push)),
  });
  S.buffer[frameID].descriptor_set_bind(.{
    .sets            = C.set[frameID..frameID+1],
    .pipeline_layout = &C.compute.layout,
    .bindpoint       = .compute,
  });
  S.buffer[frameID].compute_dispatch((push.commands_len + This.group_size - 1) / This.group_size, 1, 1);

  S.buffer[frameID].buffer_sync(&C.commands[frameID].vram.data, .{
    .access_src = .initOne(.shader_write),
    .access_trg = .initOne(.indirect_command_read),
    .stage_src  = .initOne(.compute_shader),
    .stage_trg  = .initOne(.draw_indirect),
  });
  S.buffer[frameID].buffer_sync(&C.counters[frameID].vram.data, .{
    .access_src = .initOne(.shader_write),
    .access_trg = .initOne(.indirect_command_read),
    .stage_src  = .initOne(.compute_shader),
    .stage_trg  = .initOne(.draw_indirect),
  });
  S.buffer[frameID].buffer_sync(&C.instances[frameID].vram.data, .{
    .access_src = .initOne(.shader_write),
    .access_trg = .initOne(.shader_read),
    .stage_src  = .initOne(.compute_shader),
    .stage_trg  = .initOne(.vertex_shader),
  });
}
