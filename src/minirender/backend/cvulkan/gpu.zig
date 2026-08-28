//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const gpu = @This();
pub const Gpu = @This().Type;
const This = @This();
// @deps std
const std = @import("std");
// @deps minirender
const glfw = @import("mglfw");
const msys = @import("msys");
const cvk  = @import("cvulkan");
const minirender = struct {
  const Instance = cvk.Instance;
  const Device   = @import("./device.zig").Device;
};


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  instance  :minirender.Instance,
  device    :minirender.Device,


  //_______________________________________
  // @section Create/Destroy
  //_____________________________
  pub fn destroy (G :*const @This()) void {
    var mutable :*@This()= @constCast(G); _= &mutable;
    mutable.device.destroy(&mutable.instance);
    mutable.instance.destroy();
  }
  //__________________
  pub fn create (
      system : *msys.System,
      A      : std.mem.Allocator,
      vsync  : bool,
      debug  : bool,
    ) !@This() {
    const validation_disabled :cvk.Validation.Options= .{};
    cvk.sanityCheck();
    const application = cvk.application.defaults();

    var system_extensions = try msys.vk.extensions(A);
    defer system_extensions.deinit(A);
    var instance_extensions :cvk.Instance.Extensions.Required= .{};
    instance_extensions.system = try cvk.Instance.Extensions.from(system_extensions.items, A);
    defer instance_extensions.system.destroy(A);

    var result :@This()= undefined;
    result.instance = .create(.{
      .application  = &application,
      .extensions   = instance_extensions,
      .validation   = if (debug) null else &validation_disabled,
    });
    result.device = try .create(system, &result.instance, vsync);
    return result;
  }


  //_______________________________________
  // @section Ergonomic Helpers
  //_____________________________
  pub inline fn width  (G :*const @This()) f32 { return @as(f32, @floatFromInt(G.device.swapchain.cfg.imageExtent.width )); }
  pub inline fn height (G :*const @This()) f32 { return @as(f32, @floatFromInt(G.device.swapchain.cfg.imageExtent.height)); }
  pub inline fn ratio  (G :*const @This()) f32 { return G.width() / G.height(); }
};
