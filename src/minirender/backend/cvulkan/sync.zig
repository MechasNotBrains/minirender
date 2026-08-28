//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const sync = @This();
pub const Sync = @This().Type;
const This = @This();
// @deps std
const std = @import("std");
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu = @import("./gpu.zig").Gpu;
};


//_______________________________________
// @section Constants
//_____________________________
pub const frames_Len = 2;


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  pool            :cvk.command.Pool,
  buffer          :[This.frames_Len]cvk.command.Buffer,
  imageAvailable  :[This.frames_Len]cvk.Semaphore,
  framesPending   :[This.frames_Len]cvk.Fence,
  frameNumber     :usize = 0,
  frameID         :u8    = 0,
  imageID         :usize = 0,

  pub const frames_Len = This.frames_Len;


  //_______________________________________
  // @section Create/Destroy
  //_____________________________
  pub fn destroy (
      S   : *const @This(),
      gpu : *minirender.Gpu,
    ) void {
    var mutable :*@This()= @constCast(S); _= &mutable;
    for (0..This.frames_Len) |id| {
      mutable.imageAvailable[id].destroy(&gpu.device.logical, &gpu.instance);
      mutable.framesPending[id].destroy(&gpu.device.logical, &gpu.instance);
    }
    mutable.pool.destroy(&gpu.device.logical, &gpu.instance);
    mutable.frameNumber = 0;
  }
  //__________________
  pub fn create (gpu :*minirender.Gpu) @This() {
    var result :@This()= std.mem.zeroes(@This());
    result.pool = .create(.{
      .device_logical = &gpu.device.logical,
      .queueID        = gpu.device.physical.queueFamilies.graphics,
      .flags          = .initOne(.reset_command_buffer),
      .allocator      = &gpu.instance.allocator,
    });
    for (0..This.frames_Len) |id| {
      result.buffer[id] = cvk.command.Buffer.allocate(.{
        .device_logical = &gpu.device.logical,
        .command_pool   = &result.pool,
      });
      result.imageAvailable[id] = cvk.Semaphore.create(&gpu.device.logical, &gpu.instance.allocator);
      result.framesPending[id]  = cvk.Fence.create(&gpu.device.logical, true, &gpu.instance.allocator);
    }
    return result;
  }


  //_______________________________________
  // @section Process
  //_____________________________
  pub fn nextFrame (S :*@This()) void {
    S.frameID     = (S.frameID +% 1) % This.frames_Len;
    S.frameNumber +%= 1;
  }
  //__________________
  pub fn submit (
      S       : *@This(),
      gpu     : *minirender.Gpu,
      imageID : usize,
    ) void {
    gpu.device.queue.submit(.{
      .command_buffer   = &S.buffer[S.frameID],
      .semaphore_wait   = &S.imageAvailable[S.frameID],
      .semaphore_signal = &gpu.device.swapchain.images.ptr[imageID].finished,
      .fence            = &S.framesPending[S.frameID],
    });
  }


  //_______________________________________
  // @section Onetime Requests
  //_____________________________
  pub fn buffer_begin_onetime (
      S   : *const @This(),
      gpu : *minirender.Gpu,
    ) cvk.command.Buffer {
    var result :cvk.command.Buffer= .allocate(.{
      .device_logical = &gpu.device.logical,
      .command_pool   = &S.pool,
    });
    result.begin2(.{ .flags = .initOne(.one_time_submit) });
    return result;
  }
  //__________________
  pub fn buffer_end_onetime (
      S   : *const @This(),
      B   : *const cvk.command.Buffer,
      gpu : *minirender.Gpu,
    ) void {
    B.end();
    gpu.device.queue.submit(.{ .command_buffer = B });
    gpu.device.queue.wait();
    B.free(.{
      .device_logical = &gpu.device.logical,
      .command_pool   = &S.pool,
    });
  }
};
