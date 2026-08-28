//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const render = @This();
pub const Render = @This().Type;
// @deps std
const std        = @import("std");
// @deps minirender
const msys       = @import("msys");
const mcam       = @import("mcam");
const minirender = struct {
  const Store    = @import("../store.zig").Store;
  const Command  = @import("../store.zig").Command;
  const Render   = @import("../core.zig").Render;
  const Mat4     = @import("../math.zig").Mat4;
  const Color    = @import("../math.zig").Color;
  const mat4_to_f32 = @import("../math.zig").mat4_to_f32;
  const vec4_to_f32 = @import("../math.zig").vec4_to_f32;
  const Instance = @import("../geometry.zig").Instance;
  const Gpu         = @import("./cvulkan/gpu.zig").Gpu;
  const Sync        = @import("./cvulkan/sync.zig").Sync;
  const Geometry    = @import("./cvulkan/geometry.zig").Geometry;
  const Lines       = @import("./cvulkan/lines.zig").Lines;
  const atlas       = @import("./cvulkan/atlas.zig");
  const Atlas       = @import("./cvulkan/atlas.zig").Atlas;
  const cull        = @import("./cvulkan/cull.zig");
  const Cull        = @import("./cvulkan/cull.zig").Cull;
  const ui          = @import("./cvulkan/ui.zig");
  const Ui          = @import("./cvulkan/ui.zig").Ui;
  const font        = @import("./cvulkan/font.zig");
  const capture     = @import("./cvulkan/capture.zig");
  const Target      = @import("./cvulkan/target.zig").Target;
  const Depth       = @import("./cvulkan/depth.zig").Depth;
  const Descriptors = @import("./cvulkan/descriptors.zig").Descriptors;
  const Pipeline    = @import("./cvulkan/pipeline.zig").Pipeline;
};
const cvk = @import("cvulkan");

//______________________________________
// @section Color Space
//____________________________
pub fn srgb_to_linear (color :[4]f32) [4]f32 {
  var result :[4]f32= .{ 0, 0, 0, color[3] };
  for (color[0..3], 0..) |channel, id| {
    result[id] = if (channel <= 0.04045) channel / 12.92
      else std.math.pow(f32, (channel + 0.055) / 1.055, 2.4);
  }
  return result;
}


//______________________________________
// @section Object Fields
//____________________________
pub const Type = struct {
  A                :std.mem.Allocator,
  store            :minirender.Store,
  gpu              :minirender.Gpu,
  sync             :minirender.Sync,
  depth            :minirender.Depth,
  target_clear     :minirender.Target,
  target_draw      :minirender.Target,
  descriptors      :minirender.Descriptors,
  pipeline         :minirender.Pipeline,
  geometry         :minirender.Geometry,
  lines            :minirender.Lines,
  atlas            :minirender.Atlas,
  cull             :minirender.Cull,
  ui               :minirender.Ui,
  textured         :u32 = 0,
  capture_target   :?[]u8 = null,
  color_clear      :[4]f32 = .{ 0.1, 0.1, 0.15, 1.0 },

  //______________________________________
  // @section Create/Destroy
  //____________________________
  pub const create_args = struct {
    system :*msys.System,
    atlas  :minirender.atlas.Args,
    debug  :bool = false,
    vsync  :bool = true,
  };
  //__________________
  pub fn create (A :std.mem.Allocator, arg :create_args) !@This() {
    var result :@This()= .{
      .A            = A,
      .store        = .create(A),
      .gpu          = try .create(arg.system, A, arg.vsync, arg.debug),
      .sync         = undefined,
      .depth        = undefined,
      .target_clear = undefined,
      .target_draw  = undefined,
      .descriptors  = undefined,
      .pipeline     = undefined,
      .geometry     = undefined,
      .lines        = undefined,
      .atlas        = undefined,
      .cull         = undefined,
      .ui           = undefined,
    };
    result.sync         = .create(&result.gpu);
    result.geometry     = .create(&result.gpu, A);
    result.target_clear = .clear(&result.gpu, render.srgb_to_linear(result.color_clear));
    result.target_draw  = .draw(&result.gpu);
    result.depth        = .create(&result.gpu, &result.sync, result.target_draw.ct.depth_stencil.format);
    result.target_clear.depth_bind(&result.depth);
    result.target_draw.depth_bind(&result.depth);
    result.descriptors  = .create(&result.gpu);
    result.pipeline     = .create(&result.gpu, &result.geometry.shader, &result.target_draw, &result.descriptors);
    result.lines        = .create(&result.gpu, &result.target_draw, A);
    const atlas_grid    = minirender.atlas.grid(arg.atlas.cells_len + minirender.font.glyphs_len);
    result.atlas        = try .create(&result.gpu, &result.sync,
      arg.atlas.cell_width, arg.atlas.cell_height,
      atlas_grid.columns, atlas_grid.rows, A);
    result.cull         = .create(&result.gpu);
    result.ui           = try .create(&result.gpu, &result.sync, &result.target_draw, A);
    minirender.font.upload(&result.atlas, &result.gpu, &result.sync);
    return result;
  }
  //__________________
  pub fn destroy (R :*@This()) void {
    R.gpu.device.wait();
    R.sync.destroy(&R.gpu);
    R.store.destroy();
    R.ui.destroy(&R.gpu);
    R.cull.destroy(&R.gpu);
    R.atlas.destroy(&R.gpu);
    R.lines.destroy(&R.gpu);
    R.pipeline.destroy(&R.gpu);
    R.descriptors.destroy(&R.gpu);
    R.depth.destroy(&R.gpu);
    R.target_draw.destroy();
    R.target_clear.destroy();
    R.geometry.destroy(&R.gpu);
    R.gpu.destroy();
  }

  //______________________________________
  // @section Process
  //____________________________
  pub const swapchain_retries_max = 4;
  //__________________
  pub fn resize (R :*@This(), extent_width :u32, extent_height :u32) void {
    R.gpu.device.swapchain.cfg.imageExtent = .{ .width = extent_width, .height = extent_height };
    R.swapchain_recreate();
  }
  //__________________
  fn swapchain_recreate (R :*@This()) void {
    R.gpu.device.wait();
    R.gpu.device.swapchain.recreate(.{
      .device_physical = &R.gpu.device.physical,
      .device_logical  = &R.gpu.device.logical,
      .allocator       = &R.gpu.instance.allocator,
    });
    R.target_clear.destroy();
    R.target_draw.destroy();
    R.target_clear = .clear(&R.gpu, render.srgb_to_linear(R.color_clear));
    R.target_draw  = .draw(&R.gpu);
    R.depth.destroy(&R.gpu);
    R.depth        = .create(&R.gpu, &R.sync, R.target_draw.ct.depth_stencil.format);
    R.target_clear.depth_bind(&R.depth);
    R.target_draw.depth_bind(&R.depth);
  }
  //__________________
  pub fn update (R :*@This()) void {
    const frameID = R.sync.frameID;
    R.sync.framesPending[frameID].wait(&R.gpu.device.logical);
    for (0..@This().swapchain_retries_max) |_| {
      var status :cvk.vk.Result= .success;
      R.sync.imageID = R.gpu.device.swapchain.nextImageID(.{
        .device_logical = &R.gpu.device.logical,
        .semaphore      = &R.sync.imageAvailable[frameID],
        .status         = &status,
        .log_disable    = true,
      });
      if (status != .error_out_of_date) break;
      R.swapchain_recreate();
    }
    R.sync.framesPending[frameID].reset(&R.gpu.device.logical);
    R.sync.buffer[frameID].reset(.{});
    R.sync.buffer[frameID].begin();
  }
  //__________________
  pub fn clear (R :*@This()) void {
    R.target_clear.begin(&R.gpu, &R.sync, R.sync.imageID, true);
    R.target_clear.end(&R.gpu, &R.sync, R.sync.imageID, false);
  }
  //__________________
  pub fn draw (R :*@This(), C :*const mcam.Camera) void {
    R.geometry.upload(&R.store, &R.gpu, &R.sync);
    const vp = C.view_projection();
    const viewProjection = minirender.mat4_to_f32(&vp);
    R.cull_record(viewProjection);
    R.ui.sync(&R.gpu, &R.sync);
    R.target_draw.begin(&R.gpu, &R.sync, R.sync.imageID, false);
    defer R.target_draw.end(&R.gpu, &R.sync, R.sync.imageID, true);
    R.geometry_draw(viewProjection);
    R.lines.draw(&R.gpu, &R.sync, viewProjection);
    R.ui.draw(&R.gpu, &R.sync, &R.atlas);
  }
  //__________________
  fn cull_record (R :*@This(), viewProjection :[16]f32) void {
    if (R.geometry.indirect_len == 0) return;
    R.cull.resize(&R.gpu, &R.sync, R.geometry.instance_len, R.geometry.indirect_len);
    const push :minirender.Cull.Push= .{
      .planes       = minirender.cull.planes(&viewProjection),
      .commands_len = R.geometry.indirect_len,
      .opaque_len   = R.geometry.opaque_len,
    };
    R.cull.record(&R.gpu, &R.sync,
      &R.geometry.instance_local[R.sync.frameID],
      &R.geometry.indirect_buffer[R.sync.frameID],
      &push);
  }
  //__________________
  fn geometry_draw (R :*@This(), viewProjection :[16]f32) void {
    if (R.geometry.indirect_len == 0) return;
    const push :minirender.Pipeline.Push= .{ .viewProjection = viewProjection, .textured = R.textured };
    R.descriptors.instances_bind(&R.gpu, R.sync.frameID, &R.cull.instances[R.sync.frameID]);
    R.descriptors.atlas_bind(&R.gpu, R.sync.frameID, &R.atlas);
    R.sync.buffer[R.sync.frameID].buffer_vertex_bind(&R.geometry.vertex_buffer.vram.data);
    R.sync.buffer[R.sync.frameID].buffer_index_bind(&R.geometry.index_buffer.vram.data, .{ .kind = .uint32 });
    R.pass_draw(&R.pipeline.graphics_opaque, &push, 0, R.geometry.opaque_len, 0);
    R.pass_draw(&R.pipeline.graphics_alpha, &push, R.geometry.opaque_len, R.geometry.indirect_len - R.geometry.opaque_len, @sizeOf(u32));
  }
  //__________________
  fn pass_draw (
      R        : *@This(),
      pipeline : *const cvk.pipeline.Graphics,
      push     : *const minirender.Pipeline.Push,
      first    : u32,
      len      : u32,
      counter  : u32,
    ) void {
    if (len == 0) return;
    const frameID = R.sync.frameID;
    R.sync.buffer[frameID].graphics_bind(pipeline);
    R.sync.buffer[frameID].constants_push(.{
      .pipeline_layout = &pipeline.layout,
      .stage           = .initMany(&.{ .vertex, .fragment }),
      .size            = @sizeOf(minirender.Pipeline.Push),
      .data            = @constCast(@ptrCast(push)),
    });
    R.sync.buffer[frameID].viewport_set(.{
      .width    = R.gpu.width(),
      .height   = R.gpu.height(),
      .maxDepth = 1.0,
    });
    R.sync.buffer[frameID].scissor_set(.{
      .offset = .{ .x = 0, .y = 0 },
      .extent = R.gpu.device.swapchain.cfg.imageExtent,
    });
    R.sync.buffer[frameID].descriptor_set_bind(.{
      .sets            = R.descriptors.set[frameID..frameID+1],
      .pipeline_layout = &pipeline.layout,
      .bindpoint       = .graphics,
    });
    R.sync.buffer[frameID].draw(.{
      .indexed         = true,
      .elements_len    = len,
      .indirect_buffer = &R.cull.commands[R.sync.frameID].vram.data,
      .indirect_offset = first * @sizeOf(minirender.Command),
      .count_buffer    = &R.cull.counters[R.sync.frameID].vram.data,
      .count_offset    = counter,
    });
  }
  //__________________
  pub fn present (R :*@This()) void {
    defer R.sync.nextFrame();
    R.sync.buffer[R.sync.frameID].end();
    R.sync.submit(&R.gpu, R.sync.imageID);
    if (R.capture_target) |trg| {
      minirender.capture.frame(&R.gpu, &R.sync, R.sync.imageID, trg);
      R.capture_target = null;
    }
    const status = R.gpu.device.swapchain.present(R.sync.imageID, &R.gpu.device.queue);
    if (status == .error_out_of_date or status == .suboptimal) R.swapchain_recreate();
  }
  //__________________
  pub fn reassign_instance (
      R     : *@This(),
      id    : minirender.Instance.Id,
      S     : @import("../geometry.zig").Shape.Id,
      world : minirender.Mat4,
      C     : minirender.Color,
    ) void {
    const slot   = R.store.instance_reassign(id, S, world, C) orelse return;
    const bounds = R.store.instance_bounds(id);
    R.geometry.patch_add(slot, .{
      .world  = minirender.mat4_to_f32(&world),
      .color  = minirender.vec4_to_f32(&C),
      .center = .{ bounds.center[0], bounds.center[1], bounds.center[2], 1 },
      .extent = .{ bounds.extent[0], bounds.extent[1], bounds.extent[2], 0 },
    });
  }
  //__________________
  pub fn update_instance (
      R     : *@This(),
      id    : minirender.Instance.Id,
      world : minirender.Mat4,
      C     : minirender.Color,
    ) void {
    const slot   = R.store.instance_update(id, world, C) orelse return;
    const bounds = R.store.instance_bounds(id);
    R.geometry.patch_add(slot, .{
      .world  = minirender.mat4_to_f32(&world),
      .color  = minirender.vec4_to_f32(&C),
      .center = .{ bounds.center[0], bounds.center[1], bounds.center[2], 1 },
      .extent = .{ bounds.extent[0], bounds.extent[1], bounds.extent[2], 0 },
    });
  }
  //__________________
  pub fn set_selection_lines (
      R         : *@This(),
      positions : []const [3]f32,
      C         : [4]f32,
    ) void { R.lines.set(&R.gpu, &R.sync, positions, C); }
  //__________________
  pub fn clear_selection_lines (R :*@This()) void { R.lines.clear(); }
  //__________________
  pub fn atlas_load (
      R      : *@This(),
      pixels : []const u8,
      size   : minirender.atlas.Size,
    ) ?minirender.atlas.Handle {
    return R.atlas.load(&R.gpu, &R.sync, pixels, size);
  }
  //__________________
  pub fn atlas_resize (R :*@This(), arg :minirender.atlas.Args) !void {
    const atlas_grid = minirender.atlas.grid(arg.cells_len + minirender.font.glyphs_len);
    R.gpu.device.wait();
    R.atlas.destroy(&R.gpu);
    R.atlas = try .create(&R.gpu, &R.sync,
      arg.cell_width, arg.cell_height,
      atlas_grid.columns, atlas_grid.rows, R.A);
    minirender.font.reset();
    minirender.font.upload(&R.atlas, &R.gpu, &R.sync);
  }
  //__________________
  pub fn cull_counters (R :*@This()) minirender.cull.Counters { return R.cull.counters_read(&R.gpu, &R.sync); }
  //__________________
  pub fn capture_frame (R :*@This(), trg :[]u8) void { R.capture_target = trg; }
  pub fn width  (R :*const @This()) u32 { return R.gpu.device.swapchain.cfg.imageExtent.width; }
  pub fn height (R :*const @This()) u32 { return R.gpu.device.swapchain.cfg.imageExtent.height; }
  //__________________
  pub fn cull_instances_read (R :*@This(), trg :[]minirender.Instance.Gpu) void {
    R.cull.buffer_read(&R.gpu, &R.sync, .instances, std.mem.sliceAsBytes(trg));
  }
  //__________________
  pub fn cull_commands_read (R :*@This(), trg :[]minirender.Command) void {
    R.cull.buffer_read(&R.gpu, &R.sync, .commands, std.mem.sliceAsBytes(trg));
  }
  //__________________
  pub fn instances_read (R :*@This(), frameID :usize) []const minirender.Instance.Gpu {
    const B = &R.geometry.instance_buffer[frameID];
    if (B.size == 0 or R.geometry.instance_len == 0) return &.{};
    const src :[*]const minirender.Instance.Gpu = @ptrCast(@alignCast(B.memory.data orelse return &.{}));
    return src[0..R.geometry.instance_len];
  }
  //__________________
  pub fn ui_add      (R :*@This(), shape :minirender.ui.Shape)         !void { try R.ui.add(shape); }
  pub fn ui_add_many (R :*@This(), shapes :[]const minirender.ui.Shape) !void { try R.ui.add_many(shapes); }
  pub fn ui_view     (R :*@This()) *minirender.ui.View { return &R.ui.view; }
  pub fn ui_scene    (R :*@This()) *minirender.ui.Scene { return &R.ui.scene; }
  //__________________
  pub fn atlas_scale  (R :*const @This(), handle :minirender.atlas.Handle) [2]f32 { return R.atlas.image_scale(handle); }
  pub fn atlas_offset (R :*const @This(), handle :minirender.atlas.Handle) [2]f32 { return R.atlas.cell_offset(handle); }
  pub fn atlas_size   (R :*const @This(), handle :minirender.atlas.Handle) minirender.atlas.Size { return R.atlas.image_size(handle); }
  pub fn atlas_len (R :*const @This()) u32 {
    if (R.atlas.next_slot < minirender.font.glyphs_len) return 0;
    return R.atlas.next_slot - minirender.font.glyphs_len;
  }
  //__________________
  pub fn textured_set (R :*@This(), value :bool) void { R.textured = @intFromBool(value); }
};


//______________________________________
// @section Callbacks
//____________________________
pub fn resize (R :*minirender.Render, width :u32, height :u32) void {
  if (width == 0 or height == 0) return;
  R.camera.aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
  R.backend.resize(width, height);
}

