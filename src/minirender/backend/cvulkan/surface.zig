//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const surface = @This();
pub const Surface = @This().Type;
const This = @This();
// @deps minirender
const msys = @import("msys");
const cvk  = @import("cvulkan");


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  ct :cvk.device.Surface,


  //_______________________________________
  // @section Create/Destroy
  //_____________________________
  pub fn destroy (
      S        : *const @This(),
      instance : *cvk.Instance,
    ) void {
    var mutable :*@This()= @constCast(S); _= &mutable;
    cvk.device.surface.destroy(instance.ct, mutable.ct, instance.allocator.gpu);
  }
  //__________________
  pub fn create (
      system   : *msys.System,
      instance : *cvk.Instance,
    ) !@This() {
    var result :@This()= undefined;
    try msys.vk.surface_create(system.window, @ptrCast(instance.ct), @ptrCast(instance.allocator.gpu), @ptrCast(&result.ct));
    return result;
  }
};
