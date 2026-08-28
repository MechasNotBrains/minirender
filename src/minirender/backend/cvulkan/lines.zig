//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const lines = @This();
pub const Lines = @This().Type;
const This = @This();
// @deps std
const std = @import("std");
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu    = @import("./gpu.zig").Gpu;
  const Sync   = @import("./sync.zig").Sync;
  const Buffer = @import("./buffer.zig").Buffer;
  const Target = @import("./target.zig").Target;
};


//_______________________________________
// @section Constants
//_____________________________
pub const width = 2.0;


//_______________________________________
// @section Vertex Input
//_____________________________
pub const binding :cvk.vk.VertexInputBindingDescription = .{
  .binding   = 0,
  .stride    = @sizeOf([3]f32),
  .inputRate = @intFromEnum(cvk.vk.VertexInputRate.vertex),
};
//__________________
pub const attributes = [_]cvk.vk.VertexInputAttributeDescription{
  .{ .location = 0, .binding = 0, .format = @intFromEnum(cvk.vk.Format.r32g32b32_sfloat), .offset = 0 },
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
  color :[4]f32 = .{ 1, 1, 1, 1 },
};


//_______________________________________
// @section Shader
//_____________________________
pub const Shader = struct {
  vert :cvk.Shader = .{},
  frag :cvk.Shader = .{},

  //__________________
  pub fn destroy (S :*const @This(), gpu :*minirender.Gpu) void {
    var mutable :*@This()= @constCast(S); _= &mutable;
    mutable.vert.destroy(&gpu.device.logical, &gpu.instance);
    mutable.frag.destroy(&gpu.device.logical, &gpu.instance);
  }
  //__________________
  pub fn create (gpu :*minirender.Gpu) @This() {
    return .{
      .vert = This.vertex.module(gpu),
      .frag = This.fragment.module(gpu),
    };
  }
};
//__________________
const vertex = struct {
  const array align(@alignOf(u32)) = @embedFile("./shaders/line.vert.spv").*;
  const code :[]const u32 = @ptrCast(@alignCast(&array));
  pub fn module (gpu :*minirender.Gpu) cvk.Shader {
    return .create(.{
      .device_logical = &gpu.device.logical,
      .allocator      = &gpu.instance.allocator,
      .stage          = .initOne(.vertex),
      .code           = code,
    });
  }
};
//__________________
const fragment = struct {
  const array align(@alignOf(u32)) = @embedFile("./shaders/line.frag.spv").*;
  const code :[]const u32 = @ptrCast(@alignCast(&array));
  pub fn module (gpu :*minirender.Gpu) cvk.Shader {
    return .create(.{
      .device_logical = &gpu.device.logical,
      .allocator      = &gpu.instance.allocator,
      .stage          = .initOne(.fragment),
      .code           = code,
    });
  }
};


//_______________________________________
// @section Object Fields
//_____________________________
pub const Type = struct {
  shader        :This.Shader = .{},
  graphics      :cvk.pipeline.Graphics = .{},
  stages        :[2]cvk.pipeline.ShaderStage = std.mem.zeroes([2]cvk.pipeline.ShaderStage),
  vertex_buffer :minirender.Buffer = .{ .usage = .initOne(.vertex_buffer) },
  vertex_len    :u32 = 0,
  color         :[4]f32 = .{ 1, 1, 1, 1 },

  pub const Push    = This.Push;
  pub const create  = This.create;
  pub const destroy = This.destroy;
  pub const set     = This.set;
  pub const clear   = This.clear;
  pub const draw    = This.draw;
};


//_______________________________________
// @section Create/Destroy
//_____________________________
pub fn destroy (L :*const Type, gpu :*minirender.Gpu) void {
  var mutable :*Type= @constCast(L); _= &mutable;
  mutable.vertex_buffer.destroy(gpu);
  mutable.graphics.destroy(&gpu.device.logical, &gpu.instance);
  mutable.shader.destroy(gpu);
  mutable.vertex_len = 0;
}
//__________________
pub fn create (gpu :*minirender.Gpu, trg :*const minirender.Target) Type {
  var result :Type= .{ .shader = .create(gpu) };
  result.stages[0] = result.shader.vert.stage;
  result.stages[1] = result.shader.frag.stage;

  var state_vertexInput = cvk.pipeline.state.vertexInput.defaults();
  state_vertexInput.vertexBindingDescriptionCount   = 1;
  state_vertexInput.pVertexBindingDescriptions      = &This.binding;
  state_vertexInput.vertexAttributeDescriptionCount = This.attributes.len;
  state_vertexInput.pVertexAttributeDescriptions    = &This.attributes;

  var state_inputAssembly = cvk.pipeline.state.inputAssembly.defaults();
  state_inputAssembly.topology = @intFromEnum(cvk.vk.PrimitiveTopology.line_list);

  var state_rasterization = cvk.pipeline.state.rasterization.defaults();
  state_rasterization.cullMode  = cvk.vk.CullMode.Flags.initEmpty().bits.mask;
  state_rasterization.lineWidth = This.width;

  var state_depthStencil = cvk.pipeline.state.depthStencil.defaults();
  state_depthStencil.depthTestEnable  = cvk.C.VK_FALSE;
  state_depthStencil.depthWriteEnable = cvk.C.VK_FALSE;

  const state_dynamic               = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });
  const state_viewport              = cvk.pipeline.state.viewport.defaults();
  const state_multisample           = cvk.pipeline.state.multisample.defaults();
  const state_colorBlend_attachment = cvk.pipeline.state.colorBlend.attachment.defaults();
  const state_colorBlend            = cvk.pipeline.state.colorBlend.setup(&.{ .attachments_ptr = &state_colorBlend_attachment });

  result.graphics = .create(.{
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
      .pushConstants     = &.{ .{
        .stageFlags      = cvk.vk.ShaderStage.Flags.initMany(&.{ .vertex, .fragment }).bits.mask,
        .offset          = 0,
        .size            = @sizeOf(This.Push),
      } },
    },
  });
  return result;
}


//_______________________________________
// @section Process
//_____________________________
pub fn clear (L :*Type) void { L.vertex_len = 0; }
//__________________
pub fn set (
    L         : *Type,
    gpu       : *minirender.Gpu,
    S         : *const minirender.Sync,
    positions : []const [3]f32,
    C         : [4]f32,
  ) void {
  L.color      = C;
  L.vertex_len = @intCast(positions.len);
  if (positions.len == 0) return;
  L.vertex_buffer.upload(gpu, S, std.mem.sliceAsBytes(positions));
}
//__________________
pub fn draw (
    L              : *const Type,
    gpu            : *minirender.Gpu,
    S              : *const minirender.Sync,
    viewProjection : [16]f32,
  ) void {
  if (L.vertex_len == 0) return;
  const frameID = S.frameID;
  const push :This.Push= .{ .viewProjection = viewProjection, .color = L.color };
  S.buffer[frameID].graphics_bind(&L.graphics);
  S.buffer[frameID].constants_push(.{
    .pipeline_layout = &L.graphics.layout,
    .stage           = .initMany(&.{ .vertex, .fragment }),
    .size            = @sizeOf(This.Push),
    .data            = @constCast(@ptrCast(&push)),
  });
  S.buffer[frameID].viewport_set(.{
    .width    = gpu.width(),
    .height   = gpu.height(),
    .maxDepth = 1.0,
  });
  S.buffer[frameID].scissor_set(.{
    .offset = .{ .x = 0, .y = 0 },
    .extent = gpu.device.swapchain.cfg.imageExtent,
  });
  S.buffer[frameID].buffer_vertex_bind(&L.vertex_buffer.vram.data);
  S.buffer[frameID].draw(.{
    .elements_len = L.vertex_len,
    .instance_len = 1,
  });
}
