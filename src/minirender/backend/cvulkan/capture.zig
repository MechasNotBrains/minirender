//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const capture = @This();
const This = @This();
// @deps std
const std = @import("std");
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu  = @import("./gpu.zig").Gpu;
  const Sync = @import("./sync.zig").Sync;
};


//_______________________________________
// @section Process
//_____________________________
pub fn frame (
    gpu     : *minirender.Gpu,
    S       : *const minirender.Sync,
    imageID : usize,
    trg     : []u8,
  ) void {
  gpu.device.wait();
  const extent = gpu.device.swapchain.cfg.imageExtent;
  const needed = @as(usize, extent.width) * @as(usize, extent.height) * 4;
  if (trg.len < needed) return;
  const image = gpu.device.swapchain.images.ptr[imageID].ct;

  var readback :cvk.Buffer= .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size            = needed,
    .usage           = .initOne(.transfer_dst),
    .memory_flags    = .initMany(&.{ .host_visible, .host_coherent }),
  });
  defer readback.destroy(&gpu.device.logical, &gpu.instance.allocator);
  var memory :cvk.Memory= .create(.{
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size_alloc      = readback.memory.requirements.size,
    .size_data       = needed,
    .kind            = readback.memory.kind,
    .persistent      = true,
  });
  defer memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
  readback.bind(.{ .device_logical = &gpu.device.logical, .memory = &memory });

  const command = S.buffer_begin_onetime(gpu);
  command.image_handle_transition(image, .{
    .layout_old = .present_src,
    .layout_new = .transfer_src_optimal,
    .access_trg = .initOne(.transfer_read),
    .stage_src  = .initOne(.top_of_pipe),
    .stage_trg  = .initOne(.transfer),
    .aspect     = .initOne(.color),
  });
  cvk.C.vkCmdCopyImageToBuffer(command.ct, image,
    @intFromEnum(cvk.vk.ImageLayout.transfer_src_optimal), readback.ct, 1, &.{
      .bufferOffset      = 0,
      .bufferRowLength   = 0,
      .bufferImageHeight = 0,
      .imageSubresource  = .{
        .aspectMask     = cvk.C.VK_IMAGE_ASPECT_COLOR_BIT,
        .mipLevel       = 0,
        .baseArrayLayer = 0,
        .layerCount     = 1,
      },
      .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
      .imageExtent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
    });
  command.image_handle_transition(image, .{
    .layout_old = .transfer_src_optimal,
    .layout_new = .present_src,
    .access_src = .initOne(.transfer_read),
    .stage_src  = .initOne(.transfer),
    .stage_trg  = .initOne(.bottom_of_pipe),
    .aspect     = .initOne(.color),
  });
  S.buffer_end_onetime(&command, gpu);

  const mapped :[*]const u8 = @ptrCast(@alignCast(memory.data orelse return));
  @memcpy(trg[0..needed], mapped[0..needed]);
}
