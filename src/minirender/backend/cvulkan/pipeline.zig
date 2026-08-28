//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const pipeline = @This();
pub const Pipeline = @This().Type;
const This = @This();
// @deps std
const std = @import("std");
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu         = @import("./gpu.zig").Gpu;
  const Target      = @import("./target.zig").Target;
  const Descriptors = @import("./descriptors.zig").Descriptors;
  const geometry    = @import("./geometry.zig");
};


//_______________________________________
// @section Push Constants
//_____________________________
pub const Push = extern struct {
  viewProjection :[16]f32 = .{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  },
  textured :u32 = 0,
};


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  graphics_opaque :cvk.pipeline.Graphics = .{},
  graphics_alpha  :cvk.pipeline.Graphics = .{},
  stages          :[2]cvk.pipeline.ShaderStage = std.mem.zeroes([2]cvk.pipeline.ShaderStage),

  pub const Push    = This.Push;
  pub const create  = This.create;
  pub const destroy = This.destroy;
};


//_______________________________________
// @section Create/Destroy
//_____________________________
pub fn destroy (P :*const Type, gpu :*minirender.Gpu) void {
  var mutable :*Type= @constCast(P); _= &mutable;
  mutable.graphics_opaque.destroy(&gpu.device.logical, &gpu.instance);
  mutable.graphics_alpha.destroy(&gpu.device.logical, &gpu.instance);
}
//__________________
pub fn create (
    gpu  : *minirender.Gpu,
    shd  : *const minirender.geometry.Shader,
    trg  : *const minirender.Target,
    sets : *const minirender.Descriptors,
  ) Type {
  var result :Type= .{};
  result.stages[0] = shd.vert.stage;
  result.stages[1] = shd.frag.stage;

  var state_vertexInput = cvk.pipeline.state.vertexInput.defaults();
  state_vertexInput.vertexBindingDescriptionCount   = 1;
  state_vertexInput.pVertexBindingDescriptions      = &minirender.geometry.binding;
  state_vertexInput.vertexAttributeDescriptionCount = minirender.geometry.attributes.len;
  state_vertexInput.pVertexAttributeDescriptions    = &minirender.geometry.attributes;

  var state_rasterization = cvk.pipeline.state.rasterization.defaults();
  state_rasterization.cullMode = cvk.vk.CullMode.Flags.initEmpty().bits.mask;

  const state_dynamic               = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });
  const state_inputAssembly         = cvk.pipeline.state.inputAssembly.defaults();
  const state_viewport              = cvk.pipeline.state.viewport.defaults();
  const state_multisample           = cvk.pipeline.state.multisample.defaults();
  const state_colorBlend_attachment = cvk.pipeline.state.colorBlend.attachment.defaults();
  const state_colorBlend            = cvk.pipeline.state.colorBlend.setup(&.{ .attachments_ptr = &state_colorBlend_attachment });

  var state_depthStencil = cvk.pipeline.state.depthStencil.defaults();
  const create_args :cvk.pipeline.Graphics.create_args= .{
    .device_logical      = &gpu.device.logical,
    .allocator           = &gpu.instance.allocator,
    .rendering           = &trg.ct,
    .stages              = &.{ .ptr = &result.stages, .len = result.stages.len },
    .state_vertexInput   = &state_vertexInput,
    .state_inputAssembly = &state_inputAssembly,
    .state_viewport      = &state_viewport,
    .state_rasterization = &state_rasterization,
    .state_multisample   = &state_multisample,
    .state_depthStencil  = &state_depthStencil,
    .state_colorBlend    = &state_colorBlend,
    .state_dynamic       = &state_dynamic,
    .layout              = .{
      .device_logical    = &gpu.device.logical,
      .allocator         = &gpu.instance.allocator,
      .sets              = &.{ sets.layout.ct },
      .pushConstants     = &.{ .{
        .stageFlags      = cvk.vk.ShaderStage.Flags.initMany(&.{ .vertex, .fragment }).bits.mask,
        .offset          = 0,
        .size            = @sizeOf(This.Push),
      } },
    },
  };

  state_depthStencil.depthWriteEnable = cvk.C.VK_TRUE;
  result.graphics_opaque = .create(create_args);
  state_depthStencil.depthWriteEnable = cvk.C.VK_FALSE;
  result.graphics_alpha  = .create(create_args);
  return result;
}
