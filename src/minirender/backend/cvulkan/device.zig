//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const device = @This();
pub const Device = @This().Type;
const This = @This();
// @deps minirender
const msys = @import("msys");
const cvk  = @import("cvulkan");
const minirender = struct {
  const device = struct {
    const Surface = @import("./surface.zig").Surface;
  };
};


//_______________________________________
// @section Features
//_____________________________
pub fn features_gpuDriven () cvk.device.Features {
  var result = cvk.device.Features.empty();
  result.v1_0.multiDrawIndirect         = cvk.true;
  result.v1_0.drawIndirectFirstInstance = cvk.true;
  result.v1_0.wideLines                 = cvk.true;
  result.list.features                  = result.v1_0;
  result.v1_1.shaderDrawParameters      = cvk.true;
  result.v1_2.drawIndirectCount         = cvk.true;
  return result;
}


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  surface    :minirender.device.Surface,
  physical   :cvk.device.Physical,
  logical    :cvk.device.Logical,
  swapchain  :cvk.device.Swapchain,
  queue      :cvk.device.Queue,


  //_______________________________________
  // @section Create/Destroy
  //_____________________________
  pub fn destroy (
      D        : *const @This(),
      instance : *cvk.Instance,
    ) void {
    var mutable :*@This()= @constCast(D); _= &mutable;
    mutable.swapchain.destroy(&mutable.logical, instance);
    mutable.queue.destroy(instance);
    mutable.logical.destroy(instance);
    mutable.physical.destroy(instance);
    mutable.surface.destroy(instance);
  }
  //__________________
  pub fn create (
      system   : *msys.System,
      instance : *cvk.Instance,
    ) !@This() {
    var result :@This()= undefined;
    const features :cvk.device.features.Required= .{ .user = device.features_gpuDriven() };
    result.surface    = try .create(system, instance);
    result.physical   = .create(.{
      .instance       = instance,
      .surface        = result.surface.ct,
      .features       = &features,
      .forceFirst     = true,
    });
    result.queue      = cvk.device.Queue.create.noContext(.{
      .instance       = instance,
      .device         = &result.physical,
      .id             = result.physical.queueFamilies.graphics,
      .priority       = 1.0,
    });
    result.logical    = .create(.{
      .physical       = &result.physical,
      .queue          = &result.queue,
      .features       = &features,
      .allocator      = &instance.allocator,
    });
    cvk.device.Queue.create.context(&result.queue, &result.logical);
    result.swapchain  = .create(.{
      .device_physical = &result.physical,
      .device_logical  = &result.logical,
      .surface         = result.surface.ct,
      .size            = .{ .width = system.window.W, .height = system.window.H },
      .allocator       = &instance.allocator,
    });
    return result;
  }


  //_______________________________________
  // @section Process
  //_____________________________
  pub fn wait (D :*const @This()) void { D.logical.wait(); }
};
