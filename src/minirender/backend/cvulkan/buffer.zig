//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const buffer = @This();
pub const Buffer = @This().Type;
const This = @This();
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu  = @import("./gpu.zig").Gpu;
  const Sync = @import("./sync.zig").Sync;
};


//_______________________________________
// @section Object Fields: Standard
//_____________________________
pub const Standard = struct {
  data   :cvk.Buffer = .{},
  memory :cvk.Memory = .{},

  pub fn destroy (B :*const @This(), gpu :*minirender.Gpu) void {
    var mutable :*@This()= @constCast(B); _= &mutable;
    mutable.data.destroy(&gpu.device.logical, &gpu.instance.allocator);
    mutable.memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
  }
};


//_______________________________________
// @section Object Fields: Host
//_____________________________
pub const Host = struct {
  data   :cvk.Buffer = .{},
  memory :cvk.Memory = .{},
  size   :usize                   = 0,
  usage  :cvk.vk.BufferUsage.Flags = .initEmpty(),


  //_______________________________________
  // @section Create/Destroy
  //_____________________________
  pub fn destroy (B :*const @This(), gpu :*minirender.Gpu) void {
    var mutable :*@This()= @constCast(B); _= &mutable;
    if (mutable.size == 0) return;
    mutable.data.destroy(&gpu.device.logical, &gpu.instance.allocator);
    mutable.memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
    mutable.size = 0;
  }
  //__________________
  pub fn fit (B :*@This(), gpu :*minirender.Gpu, bytes :usize) void {
    if (bytes == 0) return;
    if (B.size >= bytes) return;
    const usage = B.usage;
    B.destroy(gpu);
    B.* = .{ .size = bytes, .usage = usage };
    B.data   = .create(.{
      .device_physical = &gpu.device.physical,
      .device_logical  = &gpu.device.logical,
      .allocator       = &gpu.instance.allocator,
      .size            = bytes,
      .usage           = usage,
      .memory          = .initMany(&.{ .host_visible, .host_coherent }),
    });
    B.memory = .create(.{
      .device_logical  = &gpu.device.logical,
      .allocator       = &gpu.instance.allocator,
      .size_alloc      = B.data.memory.requirements.size,
      .size_data       = bytes,
      .kind            = B.data.memory.kind,
      .persistent      = true,
    });
    B.data.bind(.{
      .device_logical  = &gpu.device.logical,
      .memory          = &B.memory,
    });
  }


  //_______________________________________
  // @section Process
  //_____________________________
  pub fn write (B :*@This(), offset :usize, bytes :[]const u8) void {
    if (offset + bytes.len > B.size) return;
    const trg :[*]u8 = @ptrCast(B.memory.data orelse return);
    @memcpy(trg[offset..offset + bytes.len], bytes);
  }
};


//_______________________________________
// @section Object Fields: Local
//_____________________________
pub const Local = struct {
  data   :cvk.Buffer = .{},
  memory :cvk.Memory = .{},
  size   :usize                    = 0,
  usage  :cvk.vk.BufferUsage.Flags = .initEmpty(),

  pub fn destroy (B :*const @This(), gpu :*minirender.Gpu) void {
    var mutable :*@This()= @constCast(B); _= &mutable;
    if (mutable.size == 0) return;
    mutable.data.destroy(&gpu.device.logical, &gpu.instance.allocator);
    mutable.memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
    mutable.size = 0;
  }
  //__________________
  pub fn fit (B :*@This(), gpu :*minirender.Gpu, bytes :usize) void {
    if (bytes == 0) return;
    if (B.size >= bytes) return;
    const usage = B.usage;
    gpu.device.wait();
    B.destroy(gpu);
    B.* = .{ .size = bytes, .usage = usage };
    B.data   = .create(.{
      .device_physical = &gpu.device.physical,
      .device_logical  = &gpu.device.logical,
      .allocator       = &gpu.instance.allocator,
      .size            = bytes,
      .usage           = usage.unionWith(.initOne(.transfer_dst)),
      .memory          = .initOne(.device_local),
    });
    B.memory = .create(.{
      .device_logical  = &gpu.device.logical,
      .allocator       = &gpu.instance.allocator,
      .size_alloc      = B.data.memory.requirements.size,
      .size_data       = bytes,
      .kind            = B.data.memory.kind,
    });
    B.data.bind(.{
      .device_logical  = &gpu.device.logical,
      .memory          = &B.memory,
    });
  }
};


//_______________________________________
// @section Object Fields: Shared
//_____________________________
pub const Type = struct {
  ram   :This.Standard = .{},
  vram  :This.Standard = .{},
  size  :usize                  = 0,
  usage :cvk.vk.BufferUsage.Flags = .initEmpty(),


  //_______________________________________
  // @section Create/Destroy
  //_____________________________
  pub fn destroy (B :*const @This(), gpu :*minirender.Gpu) void {
    var mutable :*@This()= @constCast(B); _= &mutable;
    if (mutable.size == 0) return;
    mutable.ram.destroy(gpu);
    mutable.vram.destroy(gpu);
    mutable.size = 0;
  }
  //__________________
  pub fn create (
      gpu   : *minirender.Gpu,
      size  : usize,
      usage : cvk.vk.BufferUsage.Flags,
      data  : cvk.pointer,
    ) @This() {
    var result :@This()= .{ .size = size, .usage = usage };
    result.ram.data    = .create(.{
      .device_physical = &gpu.device.physical,
      .device_logical  = &gpu.device.logical,
      .allocator       = &gpu.instance.allocator,
      .size            = size,
      .usage           = .initOne(.transfer_src),
      .memory          = .initMany(&.{ .host_visible, .host_coherent }),
    });
    result.vram.data   = .create(.{
      .device_physical = &gpu.device.physical,
      .device_logical  = &gpu.device.logical,
      .allocator       = &gpu.instance.allocator,
      .size            = size,
      .usage           = usage.unionWith(.initOne(.transfer_dst)),
      .memory          = .initOne(.device_local),
    });
    result.ram.memory  = .create(.{
      .device_logical  = &gpu.device.logical,
      .allocator       = &gpu.instance.allocator,
      .size_alloc      = result.ram.data.memory.requirements.size,
      .size_data       = size,
      .kind            = result.ram.data.memory.kind,
      .data            = data,
      .persistent      = true,
    });
    result.vram.memory = .create(.{
      .device_logical  = &gpu.device.logical,
      .allocator       = &gpu.instance.allocator,
      .size_alloc      = result.vram.data.memory.requirements.size,
      .size_data       = size,
      .kind            = result.vram.data.memory.kind,
    });
    result.ram.data.bind(.{
      .device_logical  = &gpu.device.logical,
      .memory          = &result.ram.memory,
    });
    result.vram.data.bind(.{
      .device_logical  = &gpu.device.logical,
      .memory          = &result.vram.memory,
    });
    return result;
  }


  //_______________________________________
  // @section Process
  //_____________________________
  pub fn sync (
      B   : *const @This(),
      gpu : *minirender.Gpu,
      S   : *const minirender.Sync,
    ) void {
    const command_buffer = S.buffer_begin_onetime(gpu);
    defer S.buffer_end_onetime(&command_buffer, gpu);
    command_buffer.buffer_copy(&B.ram.data, &B.vram.data);
  }
  //__________________
  pub fn sync_record (B :*const @This(), S :*const minirender.Sync) void {
    S.buffer[S.frameID].buffer_copy(&B.ram.data, &B.vram.data);
    S.buffer[S.frameID].buffer_sync(&B.vram.data, .{
      .access_src = .initOne(.transfer_write),
      .access_trg = .initMany(&.{ .vertex_attribute_read, .index_read, .indirect_command_read, .shader_read }),
      .stage_src  = .initOne(.transfer),
      .stage_trg  = .initMany(&.{ .vertex_input, .draw_indirect, .compute_shader, .vertex_shader }),
    });
  }
  //__________________
  pub fn upload_record (
      B     : *@This(),
      gpu   : *minirender.Gpu,
      S     : *const minirender.Sync,
      bytes : []const u8,
    ) void {
    if (B.size < bytes.len) {
      const usage = B.usage;
      gpu.device.wait();
      B.destroy(gpu);
      B.* = .create(gpu, bytes.len, usage, @constCast(@ptrCast(bytes.ptr)));
      B.sync_record(S);
      return;
    }
    const trg :[*]u8 = @ptrCast(B.ram.memory.data orelse return);
    @memcpy(trg[0..bytes.len], bytes);
    B.sync_record(S);
  }
  //__________________
  pub fn upload (
      B     : *@This(),
      gpu   : *minirender.Gpu,
      S     : *const minirender.Sync,
      bytes : []const u8,
    ) void {
    if (B.size < bytes.len) {
      const usage = B.usage;
      gpu.device.wait();
      B.destroy(gpu);
      B.* = .create(gpu, bytes.len, usage, @constCast(@ptrCast(bytes.ptr)));
      B.sync(gpu, S);
      return;
    }
    const trg :[*]u8 = @ptrCast(B.ram.memory.data orelse return);
    @memcpy(trg[0..bytes.len], bytes);
    B.sync(gpu, S);
  }
};
