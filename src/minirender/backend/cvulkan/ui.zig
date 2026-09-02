//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const ui = @This();
pub const Ui = @This().Type;
const This = @This();
pub const View    = mui.View;
pub const Scene   = mui.Scene;
pub const Shape   = mui.Shape;
pub const Pixmap  = @import("../../ui/pixmap.zig").Pixmap;
pub const font5x7 = @import("../../ui/font5x7.zig");
pub const tree    = @import("../../ui/tree.zig");
pub const Tree    = tree.Type;
// @deps std
const std = @import("std");
// @deps minirender
const mui = @import("mui");
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu    = @import("./gpu.zig").Gpu;
  const Sync   = @import("./sync.zig").Sync;
  const sync   = @import("./sync.zig");
  const Buffer = @import("./buffer.zig").Buffer;
  const Host   = @import("./buffer.zig").buffer.Host;
  const Target = @import("./target.zig").Target;
  const Atlas  = @import("./atlas.zig").Atlas;
};
const frames_Len = minirender.sync.frames_Len;


//_______________________________________
// @section Constants
//_____________________________
pub const instances_id = 0;
pub const atlas_id     = 1;
pub const quad_indices = [6]u32{ 0, 1, 2, 0, 2, 3 };
pub const quad_vertices = [4][4]f32{
  .{ 0, 0,  0, 0 },
  .{ 1, 0,  1, 0 },
  .{ 1, 1,  1, 1 },
  .{ 0, 1,  0, 1 },
};


//_______________________________________
// @section Vertex Input
//_____________________________
pub const binding :cvk.vk.VertexInputBindingDescription = .{
  .binding   = 0,
  .stride    = 4 * @sizeOf(f32),
  .inputRate = @intFromEnum(cvk.vk.VertexInputRate.vertex),
};
//__________________
pub const attributes = [_]cvk.vk.VertexInputAttributeDescription{
  .{ .location = 0, .binding = 0, .format = @intFromEnum(cvk.vk.Format.r32g32_sfloat), .offset = 0 },
  .{ .location = 1, .binding = 0, .format = @intFromEnum(cvk.vk.Format.r32g32_sfloat), .offset = 2 * @sizeOf(f32) },
};


//_______________________________________
// @section Push Constants
//_____________________________
pub const Screen = extern struct {
  size :[2]f32 = .{ 0, 0 },
};


//_______________________________________
// @section Instances
//_____________________________
pub const Instance = extern struct {
  position :[2]f32 = .{ 0, 0 },
  scale    :[2]f32 = .{ 0, 0 },
  color    :[4]f32 = .{ 1, 1, 1, 1 },
  uv       :[4]f32 = .{ 0, 0, 0, 0 },
  kind     :u32    = 0,
  offset   :f32    = 0,
  padding0 :u32    = 0,
  padding1 :u32    = 0,

  pub fn upload (I :*@This(), shape :*const mui.Shape, screen :[2]f32) void {
    I.position = .{
      @floatCast(shape.transform.data[0] / 100.0 * screen[0]),
      @floatCast(shape.transform.data[1] / 100.0 * screen[1]),
    };
    I.scale    = .{
      @floatCast(shape.transform.data[2] / 100.0 * screen[0]),
      @floatCast(shape.transform.data[3] / 100.0 * screen[1]),
    };
    I.color    = .{
      @floatCast(shape.color.r()), @floatCast(shape.color.g()),
      @floatCast(shape.color.b()), @floatCast(shape.color.a()),
    };
    I.uv       = .{
      @floatCast(shape.uv.data[0]), @floatCast(shape.uv.data[1]),
      @floatCast(shape.uv.data[2]), @floatCast(shape.uv.data[3]),
    };
    I.kind     = @intFromEnum(shape.kind);
    I.offset   = @floatCast(shape.offset);
  }
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
  const array align(@alignOf(u32)) = @embedFile("./shaders/ui.vert.spv").*;
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
  const array align(@alignOf(u32)) = @embedFile("./shaders/ui.frag.spv").*;
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
  view          :mui.View,
  scene         :mui.Scene,
  shader        :This.Shader = .{},
  graphics      :cvk.pipeline.Graphics = .{},
  stages        :[2]cvk.pipeline.ShaderStage = std.mem.zeroes([2]cvk.pipeline.ShaderStage),
  vertex_buffer :minirender.Buffer = .{ .usage = .initOne(.vertex_buffer) },
  index_buffer  :minirender.Buffer = .{ .usage = .initOne(.index_buffer) },
  instances     :[This.frames_Len]minirender.Host = @splat(.{ .usage = .initOne(.storage_buffer) }),
  instance_len  :u32 = 0,
  pool          :cvk.descriptor.Pool   = std.mem.zeroes(cvk.descriptor.Pool),
  layout        :cvk.descriptor.Layout = std.mem.zeroes(cvk.descriptor.Layout),
  set           :[This.frames_Len]cvk.descriptor.Set = std.mem.zeroes([This.frames_Len]cvk.descriptor.Set),

  pub const Screen   = This.Screen;
  pub const Shape    = This.Shape;
  pub const Instance = This.Instance;
  pub const Shader   = This.Shader;
  pub const create   = This.create;
  pub const destroy  = This.destroy;
  pub const add      = This.add;
  pub const add_many = This.add_many;
  pub const clear    = This.clear;
  pub const sync     = This.sync;
  pub const draw     = This.draw;
};


//_______________________________________
// @section Bindings
//_____________________________
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
pub fn destroy (U :*const Type, gpu :*minirender.Gpu) void {
  var mutable :*Type= @constCast(U); _= &mutable;
  for (&mutable.instances) |*B| B.destroy(gpu);
  mutable.vertex_buffer.destroy(gpu);
  mutable.index_buffer.destroy(gpu);
  mutable.graphics.destroy(&gpu.device.logical, &gpu.instance);
  mutable.pool.destroy(&gpu.device.logical, &gpu.instance);
  mutable.layout.destroy(&gpu.device.logical, &gpu.instance);
  mutable.shader.destroy(gpu);
  mutable.scene.destroy();
  mutable.view.destroy();
  mutable.instance_len = 0;
}
//__________________
pub fn create (
    gpu : *minirender.Gpu,
    S   : *const minirender.Sync,
    trg : *const minirender.Target,
    A   : std.mem.Allocator,
  ) !Type {
  var result :Type= .{
    .view   = mui.View.create(.{}),
    .scene  = try mui.Scene.create(A, .{}),
    .shader = .create(gpu),
  };
  result.stages[0] = result.shader.vert.stage;
  result.stages[1] = result.shader.frag.stage;

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
    .max_sets       = This.frames_Len,
    .sizes          = &.{ .{
      .type            = @intFromEnum(cvk.vk.DescriptorType.storage_buffer),
      .descriptorCount = This.frames_Len,
    }, .{
      .type            = @intFromEnum(cvk.vk.DescriptorType.combined_image_sampler),
      .descriptorCount = This.frames_Len,
    } },
  });
  for (0..This.frames_Len) |id| result.set[id] = .allocate(.{
    .descriptor_pool = &result.pool,
    .device_logical  = &gpu.device.logical,
    .layouts         = &.{ result.layout },
  });

  result.vertex_buffer.upload(gpu, S, std.mem.sliceAsBytes(&This.quad_vertices));
  result.index_buffer.upload(gpu, S, std.mem.sliceAsBytes(&This.quad_indices));

  var state_vertexInput = cvk.pipeline.state.vertexInput.defaults();
  state_vertexInput.vertexBindingDescriptionCount   = 1;
  state_vertexInput.pVertexBindingDescriptions      = &This.binding;
  state_vertexInput.vertexAttributeDescriptionCount = This.attributes.len;
  state_vertexInput.pVertexAttributeDescriptions    = &This.attributes;

  var state_rasterization = cvk.pipeline.state.rasterization.defaults();
  state_rasterization.cullMode = cvk.vk.CullMode.Flags.initEmpty().bits.mask;

  var state_depthStencil = cvk.pipeline.state.depthStencil.defaults();
  state_depthStencil.depthTestEnable  = cvk.C.VK_FALSE;
  state_depthStencil.depthWriteEnable = cvk.C.VK_FALSE;

  const state_dynamic               = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });
  const state_inputAssembly         = cvk.pipeline.state.inputAssembly.defaults();
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
      .sets              = &.{ result.layout.ct },
      .pushConstants     = &.{ .{
        .stageFlags      = cvk.vk.ShaderStage.Flags.initOne(.vertex).bits.mask,
        .offset          = 0,
        .size            = @sizeOf(This.Screen),
      } },
    },
  });
  return result;
}


//_______________________________________
// @section Scene
//_____________________________
pub fn add      (U :*Type, shape :mui.Shape)         !void { try U.scene.add(shape); }
pub fn add_many (U :*Type, shapes :[]const mui.Shape) !void { try U.scene.add_many(shapes); }
pub fn clear    (U :*Type) void { U.instance_len = 0; }


//_______________________________________
// @section Process
//_____________________________
pub fn sync (
    U   : *Type,
    gpu : *minirender.Gpu,
    S   : *const minirender.Sync,
  ) void {
  const shapes = U.scene.shapes.data();
  U.instance_len = @intCast(shapes.len);
  if (shapes.len == 0) return;
  const screen = [2]f32{ gpu.width(), gpu.height() };
  U.instances[S.frameID].fit(gpu, shapes.len * @sizeOf(This.Instance));
  for (shapes, 0..) |*shape, id| {
    var entry :This.Instance= .{};
    entry.upload(shape, screen);
    U.instances[S.frameID].write(id * @sizeOf(This.Instance), std.mem.asBytes(&entry));
  }
}
//__________________
pub fn draw (
    U   : *const Type,
    gpu : *minirender.Gpu,
    S   : *const minirender.Sync,
    A   : *const minirender.Atlas,
  ) void {
  if (U.instance_len == 0) return;
  const frameID = S.frameID;

  const buffer_info :cvk.vk.DescriptorBufferInfo= .{
    .buffer = U.instances[frameID].data.ct,
    .offset = 0,
    .range  = cvk.C.VK_WHOLE_SIZE,
  };
  const instances = This.instances_binding(&buffer_info);
  U.set[frameID].update(.{ .device_logical = &gpu.device.logical, .binding = &instances });

  const image_info :cvk.vk.DescriptorImageInfo= .{
    .sampler     = A.sampler.ct,
    .imageView   = A.view.ct,
    .imageLayout = @intFromEnum(cvk.vk.ImageLayout.shader_read_only_optimal),
  };
  const atlas = This.atlas_binding(&image_info);
  U.set[frameID].update(.{ .device_logical = &gpu.device.logical, .binding = &atlas });

  const push :This.Screen= .{ .size = .{ gpu.width(), gpu.height() } };
  S.buffer[frameID].graphics_bind(&U.graphics);
  S.buffer[frameID].constants_push(.{
    .pipeline_layout = &U.graphics.layout,
    .stage           = .initOne(.vertex),
    .size            = @sizeOf(This.Screen),
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
  S.buffer[frameID].descriptor_set_bind(.{
    .sets            = U.set[frameID..frameID+1],
    .pipeline_layout = &U.graphics.layout,
    .bindpoint       = .graphics,
  });
  S.buffer[frameID].buffer_vertex_bind(&U.vertex_buffer.vram.data, 0, 0);
  S.buffer[frameID].buffer_index_bind(&U.index_buffer.vram.data, .{ .kind = .uint32 });
  S.buffer[frameID].draw(.{
    .indexed      = true,
    .elements_len = This.quad_indices.len,
    .instance_len = U.instance_len,
  });
}
