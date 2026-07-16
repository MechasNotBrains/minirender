const std = @import("std");
const cvk = @import("cvulkan");
const mgpu = @import("mgpu");
const msys = @import("msys");

extern fn glfwGetTime() f64;

pub const MAX_INSTANCES: u32 = 100_000;
const FRAMES_IN_FLIGHT: u32 = 2;
const MAX_SWAPCHAIN_IMAGES: u32 = 8;
const RC_CASCADE0_DIMS: i32 = 2;
const RC_CASCADE0_RANGE: f32 = 1.0;
const RC_RANGE_FACTOR: f32 = 4.0;
const RC_MAX_LEVELS: u32 = 8;

pub const ShapeType = enum(u32) {
  circle           = 0,
  square           = 1,
  triangle         = 2,
  pentagon         = 3,
  hexagon          = 4,
  cube             = 5,
  rhomboid         = 6,
  rectangle        = 7,
  circle_outline   = 8,
  square_outline   = 9,
  triangle_outline = 10,
  pentagon_outline = 11,
  hexagon_outline  = 12,
  cube_outline     = 13,
  rhomboid_outline = 14,

  pub fn to_outline(self: ShapeType) ShapeType {
    return @enumFromInt(@intFromEnum(self) | 8);
  }

  pub fn facing_offset(self: ShapeType) f32 {
    const base = @intFromEnum(self) & 7;
    return switch (base) {
      0 => 0,
      1 => 0,
      2 => 0,
      3 => 0,
      4 => std.math.pi / 6.0,
      5 => std.math.pi / 6.0,
      6 => 0,
      else => 0,
    };
  }
};

pub const ShapeInstance = extern struct {
  position   : [2]f32,
  rotation   : f32,
  scale_x    : f32,
  scale_y    : f32,
  shape_type : u32,
  color      : [4]f32,
};

pub const Color = mgpu.data.Color;

fn srgb_to_linear(value: f32) f32 {
  if (value <= 0.04045) return value / 12.92;
  return std.math.pow(f32, (value + 0.055) / 1.055, 2.4);
}

pub fn color_from_hex(hex: u32) Color {
  return .{ .data = .{
    srgb_to_linear(@as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0),
    srgb_to_linear(@as(f32, @floatFromInt((hex >>  8) & 0xFF)) / 255.0),
    srgb_to_linear(@as(f32, @floatFromInt( hex        & 0xFF)) / 255.0),
    1.0,
  }};
}

pub fn color_rgba(red: f32, green: f32, blue: f32, alpha: f32) Color {
  return .{ .data = .{ red, green, blue, alpha } };
}

fn color_to_f32(color: Color) [4]f32 {
  return .{
    @floatCast(color.data[0]),
    @floatCast(color.data[1]),
    @floatCast(color.data[2]),
    @floatCast(color.data[3]),
  };
}

pub const dracula = struct {
  pub const background   = color_from_hex(0x200828);
  pub const current_line = color_from_hex(0x44475a);
  pub const foreground   = color_from_hex(0xf8f8f2);
  pub const comment      = color_from_hex(0x6272a4);
  pub const cyan         = color_from_hex(0x8be9fd);
  pub const green        = color_from_hex(0x50fa7b);
  pub const orange       = color_from_hex(0xffb86c);
  pub const pink         = color_from_hex(0xff79c6);
  pub const purple       = color_from_hex(0xbd93f9);
  pub const red          = color_rgba(1.0, 0.0, 0.0, 1.0);
  pub const yellow       = color_from_hex(0xf1fa8c);
  pub const player_body  = color_from_hex(0x55007e);
};

const Globals = extern struct {
  projection  : [16]f32,
  screen_size : [2]f32,
};

const JfaPushConstants = extern struct {
  step_size  : f32,
  _padding   : f32 = 0,
  texel_size : [2]f32,
};

const RcCascadePushConstants = extern struct {
  cascade_level:      i32,
  cascade0_dims:      i32,
  cascade0_range:     f32,
  _pad0:              f32 = 0,
  cascade_resolution: [2]f32,
  scene_resolution:   [2]f32,
};

const RcMergePushConstants = extern struct {
  current_cascade_level: i32,
  num_cascade_levels:    i32,
  cascade0_dims:         i32,
  cascade0_range:        f32,
  cascade_resolution:    [2]f32,
};

const RcGatherPushConstants = extern struct {
  cascade0_dims:      i32,
  _pad0:              f32 = 0,
  cascade_resolution: [2]f32,
};

const LightingUniforms = extern struct {
  camera_bounds  : [4]f32,
  light_position : [2]f32,
  light_radius   : f32,
  light_intensity: f32,
  light_color    : [4]f32,
  texel_size     : [2]f32,
  _padding       : [2]f32 = .{ 0, 0 },
};

pub const VulkanState = struct {
  gpu                         : mgpu.system.Gpu = undefined,
  forward_target              : mgpu.Target = .{},
  pipeline                    : cvk.pipeline.Graphics = .{},
  sync                        : mgpu.Sync = undefined,
  vertex                      : mgpu.Buffer = .{},
  index                       : mgpu.Buffer = .{},
  instance_buffers            : [FRAMES_IN_FLIGHT]mgpu.Buffer = undefined,
  uniform_buffers             : [FRAMES_IN_FLIGHT]mgpu.Buffer = undefined,
  descriptor_set_layout       : cvk.C.VkDescriptorSetLayout = null,
  descriptor_pool             : cvk.C.VkDescriptorPool = null,
  descriptor_sets             : [FRAMES_IN_FLIGHT]cvk.C.VkDescriptorSet = undefined,

  // --- Deferred lighting resources ---
  gbuffer_images              : [FRAMES_IN_FLIGHT]cvk.image.Data = .{ .{}, .{} },
  gbuffer_views               : [FRAMES_IN_FLIGHT]cvk.image.View = .{ .{}, .{} },
  gbuffer_memory              : [FRAMES_IN_FLIGHT]cvk.Memory = .{ .{}, .{} },
  emission_images             : [FRAMES_IN_FLIGHT]cvk.image.Data = .{ .{}, .{} },
  emission_views              : [FRAMES_IN_FLIGHT]cvk.image.View = .{ .{}, .{} },
  emission_memory             : [FRAMES_IN_FLIGHT]cvk.Memory = .{ .{}, .{} },
  gbuffer_sampler             : cvk.image.Sampler = .{},
  gbuffer_pipeline            : cvk.pipeline.Graphics = .{},
  composite_pipeline          : cvk.pipeline.Graphics = .{},
  jfa_images                  : [FRAMES_IN_FLIGHT * 2]cvk.image.Data = .{ .{}, .{}, .{}, .{} },
  jfa_views                   : [FRAMES_IN_FLIGHT * 2]cvk.image.View = .{ .{}, .{}, .{}, .{} },
  jfa_image_memory            : [FRAMES_IN_FLIGHT * 2]cvk.Memory = .{ .{}, .{}, .{}, .{} },
  jfa_rendering               : cvk.Rendering = .{},
  jfa_seed_pipeline           : cvk.pipeline.Graphics = .{},
  jfa_step_pipeline           : cvk.pipeline.Graphics = .{},
  jfa_seed_descriptor_layout  : cvk.C.VkDescriptorSetLayout = null,
  jfa_step_descriptor_layout  : cvk.C.VkDescriptorSetLayout = null,
  jfa_descriptor_pool         : cvk.C.VkDescriptorPool = null,
  jfa_seed_descriptor_sets    : [FRAMES_IN_FLIGHT]cvk.C.VkDescriptorSet = undefined,
  jfa_step_descriptor_sets    : [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSet = undefined,
  lighting_images             : [FRAMES_IN_FLIGHT]cvk.image.Data = .{ .{}, .{} },
  lighting_views              : [FRAMES_IN_FLIGHT]cvk.image.View = .{ .{}, .{} },
  lighting_memory             : [FRAMES_IN_FLIGHT]cvk.Memory = .{ .{}, .{} },
  lighting_rendering          : cvk.Rendering = .{},
  lighting_pipeline           : cvk.pipeline.Graphics = .{},
  lighting_descriptor_layout  : cvk.C.VkDescriptorSetLayout = null,
  lighting_descriptor_pool    : cvk.C.VkDescriptorPool = null,
  lighting_descriptor_sets    : [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSet = undefined,
  lighting_uniform_buffers    : [FRAMES_IN_FLIGHT]mgpu.Buffer = undefined,
  composite_descriptor_layout : cvk.C.VkDescriptorSetLayout = null,
  composite_descriptor_pool   : cvk.C.VkDescriptorPool = null,
  composite_descriptor_sets   : [FRAMES_IN_FLIGHT]cvk.C.VkDescriptorSet = undefined,
  rc_compute_images           : [FRAMES_IN_FLIGHT]cvk.image.Data = .{ .{}, .{} },
  rc_compute_views            : [FRAMES_IN_FLIGHT]cvk.image.View = .{ .{}, .{} },
  rc_compute_memory           : [FRAMES_IN_FLIGHT]cvk.Memory = .{ .{}, .{} },
  rc_merge_images             : [FRAMES_IN_FLIGHT * 2]cvk.image.Data = .{ .{}, .{}, .{}, .{} },
  rc_merge_views              : [FRAMES_IN_FLIGHT * 2]cvk.image.View = .{ .{}, .{}, .{}, .{} },
  rc_merge_memory             : [FRAMES_IN_FLIGHT * 2]cvk.Memory = .{ .{}, .{}, .{}, .{} },
  rc_rendering                : cvk.Rendering = .{},
  rc_cascade_pipeline         : cvk.pipeline.Graphics = .{},
  rc_cascade_desc_layout      : cvk.C.VkDescriptorSetLayout = null,
  rc_cascade_desc_pool        : cvk.C.VkDescriptorPool = null,
  rc_cascade_desc_sets        : [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSet = undefined,
  rc_merge_pipeline           : cvk.pipeline.Graphics = .{},
  rc_merge_desc_layout        : cvk.C.VkDescriptorSetLayout = null,
  rc_merge_desc_pool          : cvk.C.VkDescriptorPool = null,
  rc_merge_desc_sets          : [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSet = undefined,
  rc_gather_pipeline          : cvk.pipeline.Graphics = .{},
  rc_gather_desc_layout       : cvk.C.VkDescriptorSetLayout = null,
  rc_gather_desc_pool         : cvk.C.VkDescriptorPool = null,
  rc_gather_desc_sets         : [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSet = undefined,
  rc_cascade_count            : u32 = 0,
};

pub const Renderer = struct {
  instances          : [MAX_INSTANCES]ShapeInstance = undefined,
  instance_count     : u32 = 0,
  frame_start        : f64 = 0,
  frame_ms           : f32 = 0,
  frame_fps          : f32 = 0,
  spent_ms           : f32 = 0,
  vulkan             : VulkanState = undefined,
  vulkan_initialized : bool = false,
  lighting_enabled   : bool = true,
  light_position     : [2]f32 = .{ 0, 0 },
  light_color        : [4]f32 = .{ 1, 1, 1, 1 },
  light_radius       : f32 = 15.0,
  light_intensity    : f32 = 1.5,

  pub fn init_vulkan(self: *Renderer, system: *msys.System, allocator: std.mem.Allocator) !void {
    self.vulkan             = try create_vulkan_state(system, allocator, &self.instances);
    self.vulkan_initialized = true;
  }

  pub fn deinit_vulkan(self: *Renderer) void {
    if (!self.vulkan_initialized) return;
    self.vulkan.gpu.device.wait();
    destroy_vulkan_state(&self.vulkan);
    self.vulkan_initialized = false;
  }

  pub fn set_light(
      self       : *Renderer,
      position_x : f32,
      position_y : f32,
      color      : Color,
      radius     : f32,
      intensity  : f32,
    ) void {
    self.light_position = .{ position_x, position_y };
    self.light_color    = color_to_f32(color);
    self.light_radius   = radius;
    self.light_intensity = intensity;
  }

  pub fn begin(self: *Renderer, current_time: f64) void {
    self.frame_ms       = self.spent_ms;
    self.frame_fps      = if (self.frame_ms > 0.001) 1000.0 / self.frame_ms else 0.0;
    self.frame_start    = current_time;
    self.instance_count = 0;
  }

  pub fn push_shape(
      self       : *Renderer,
      position_x : f32,
      position_y : f32,
      rotation   : f32,
      scale      : f32,
      shape_type : ShapeType,
      color      : Color,
    ) void {
    if (self.instance_count >= MAX_INSTANCES) return;
    self.instances[self.instance_count] = .{
      .position = .{ position_x, position_y },
      .rotation = rotation,
      .scale_x = scale,
      .scale_y = scale,
      .shape_type = @intFromEnum(shape_type),
      .color = color_to_f32(color),
    };
    self.instance_count += 1;
  }

  pub fn push_shape_no_shadow(
      self       : *Renderer,
      position_x : f32,
      position_y : f32,
      rotation   : f32,
      scale      : f32,
      shape_type : ShapeType,
      color      : Color,
    ) void {
    if (self.instance_count >= MAX_INSTANCES) return;
    self.instances[self.instance_count] = .{
      .position = .{ position_x, position_y },
      .rotation = rotation,
      .scale_x = scale,
      .scale_y = scale,
      .shape_type = @intFromEnum(shape_type) | 32,
      .color = color_to_f32(color),
    };
    self.instance_count += 1;
  }

  pub fn push_rect(
      self       : *Renderer,
      position_x : f32,
      position_y : f32,
      rotation   : f32,
      half_width : f32,
      half_height: f32,
      color      : Color,
    ) void {
    if (self.instance_count >= MAX_INSTANCES) return;
    self.instances[self.instance_count] = .{
      .position = .{ position_x, position_y },
      .rotation = rotation,
      .scale_x = half_width,
      .scale_y = half_height,
      .shape_type = @intFromEnum(ShapeType.rectangle),
      .color = color_to_f32(color),
    };
    self.instance_count += 1;
  }

  pub fn push_shape_outline(
      self       : *Renderer,
      position_x : f32,
      position_y : f32,
      rotation   : f32,
      scale      : f32,
      shape_type : ShapeType,
      color      : Color,
    ) void {
    if (self.instance_count >= MAX_INSTANCES) return;
    self.instances[self.instance_count] = .{
      .position = .{ position_x, position_y },
      .rotation = rotation,
      .scale_x = scale,
      .scale_y = scale,
      .shape_type = @intFromEnum(shape_type) | 8,
      .color = color_to_f32(color),
    };
    self.instance_count += 1;
  }

  pub fn push_shape_emissive(
      self       : *Renderer,
      position_x : f32,
      position_y : f32,
      rotation   : f32,
      scale      : f32,
      shape_type : ShapeType,
      color      : Color,
    ) void {
    if (self.instance_count >= MAX_INSTANCES) return;
    self.instances[self.instance_count] = .{
      .position   = .{ position_x, position_y },
      .rotation   = rotation,
      .scale_x    = scale,
      .scale_y    = scale,
      .shape_type = @intFromEnum(shape_type) | 16,
      .color      = color_to_f32(color),
    };
    self.instance_count += 1;
  }

  pub fn push_arc (
      self         : *Renderer,
      center_x     : f32,
      center_y     : f32,
      radius       : f32,
      start_angle  : f32,
      end_angle    : f32,
      thickness    : f32,
      color        : Color,
    ) void {
    const arc_span = end_angle - start_angle;
    const segment_count: u32 = @max(12, @as(u32, @intFromFloat(@abs(arc_span) * radius / thickness)));
    for (0..segment_count) |segment_index| {
      const fraction = @as(f32, @floatFromInt(segment_index)) / @as(f32, @floatFromInt(segment_count));
      const angle = start_angle + fraction * arc_span;
      self.push_shape_no_shadow(
        center_x + @cos(angle) * radius,
        center_y + @sin(angle) * radius,
        0,
        thickness,
        .circle,
        color,
      );
    }
  }

  pub fn push_text (
      self       : *Renderer,
      screen_x   : f32,
      screen_y   : f32,
      text       : []const u8,
      color      : Color,
      pixel_size : f32,
    ) void {
    var cursor_x: f32 = 0;
    for (text) |character| {
      if (character < 0x20 or character > 0x7E) {
        cursor_x += 6;
        continue;
      }
      for (0..5) |column_index| {
        const column: u3 = @intCast(column_index);
        for (0..7) |row_index| {
          const row: u3 = @intCast(row_index);
          if (!glyph_pixel(character, column, row)) continue;
          const pixel_x = screen_x + (cursor_x + @as(f32, @floatFromInt(column_index))) * pixel_size;
          const pixel_y = screen_y + @as(f32, @floatFromInt(row_index)) * pixel_size;
          self.push_shape(
            pixel_x, pixel_y,
            0,
            pixel_size * 0.55,
            .square,
            color,
          );
        }
      }
      cursor_x += 6;
    }
  }

  pub const ProfileData = struct {
    physics_ms   : f32 = 0,
    enemies_ms   : f32 = 0,
    flowfield_ms : f32 = 0,
    render_ms    : f32 = 0,
    enemy_count  : u32 = 0,
  };

  pub fn hud (self: *Renderer, view_width: f32, view_height: f32, profile: ProfileData) void {
    const text_size: f32 = view_width * 0.002;
    const char_width = 6.0 * text_size;
    const line_height = 8.0 * text_size;

    var buf_phys    : [48]u8 = undefined;
    var buf_enemy   : [48]u8 = undefined;
    var buf_flow    : [48]u8 = undefined;
    var buf_draw    : [48]u8 = undefined;
    var buf_total   : [48]u8 = undefined;
    var buf_enemies : [48]u8 = undefined;
    var buf_fps     : [48]u8 = undefined;

    const total_ms = profile.physics_ms + profile.enemies_ms + profile.flowfield_ms + profile.render_ms;
    const tick_fps = if (total_ms > 0.001) 1000.0 / total_ms else 0.0;

    const lines = [_][]const u8{
      std.fmt.bufPrint(&buf_enemies, "{d} enemies",      .{profile.enemy_count})  catch "?",
      std.fmt.bufPrint(&buf_total,   "total : {d:.3}ms", .{total_ms})             catch "?",
      "",
      std.fmt.bufPrint(&buf_draw,    "draw  : {d:.3}ms", .{profile.render_ms})    catch "?",
      std.fmt.bufPrint(&buf_phys,    "phys  : {d:.3}ms", .{profile.physics_ms})   catch "?",
      std.fmt.bufPrint(&buf_enemy,   "enemy : {d:.3}ms", .{profile.enemies_ms})   catch "?",
      std.fmt.bufPrint(&buf_flow,    "flow  : {d:.3}ms", .{profile.flowfield_ms}) catch "?",
      "",
      std.fmt.bufPrint(&buf_fps,     "{d:.0} fps",       .{tick_fps})             catch "?",
    };

    const right_edge  = view_width  / 2.0 - text_size * 2.0;
    const bottom_edge = view_height / 2.0 - text_size * 20.0;

    for (lines, 0..) |line, line_index| {
      if (line.len == 0) continue;
      const line_width = @as(f32, @floatFromInt(line.len)) * char_width;
      const line_x = right_edge - line_width;
      const line_y = bottom_edge - @as(f32, @floatFromInt(lines.len - 1 - line_index)) * line_height;
      self.push_text(line_x, line_y, line, dracula.foreground, text_size);
    }
  }

  pub fn push_hud_text (self: *Renderer, screen_x: f32, screen_y: f32, text: []const u8, view_width: f32) void {
    const text_size: f32 = view_width * 0.002;
    self.push_text(screen_x, screen_y, text, dracula.foreground, text_size);
  }

  pub fn draw_frame (self: *Renderer, camera_x: f32, camera_y: f32, view_width: f32, aspect_ratio: f32) void {
    if (!self.vulkan_initialized) return;
    const state = &self.vulkan;
    const frame = state.sync.frameID;

    state.sync.framesPending[frame].wait(&state.gpu.device.logical);

    var acquire_status: cvk.C.VkResult = 0;
    const image_index = state.gpu.device.swapchain.nextImageID(&.{
      .device_logical = &state.gpu.device.logical,
      .semaphore      = &state.sync.imageAvailable[frame],
      .status         = &acquire_status,
    });
    if (acquire_status == cvk.C.VK_ERROR_OUT_OF_DATE_KHR) return;

    state.sync.framesPending[frame].reset(&state.gpu.device.logical);
    const draw_start = glfwGetTime();

    const instance_byte_count = @as(usize, self.instance_count) * @sizeOf(ShapeInstance);
    if (instance_byte_count > 0) {
      const destination: [*]u8 = @ptrCast(@alignCast(state.instance_buffers[frame].mem.data));
      const source: [*]const u8 = @ptrCast(&self.instances);
      @memcpy(destination[0..instance_byte_count], source[0..instance_byte_count]);
    }

    const view_height = view_width / aspect_ratio;
    const globals = Globals{
      .projection = orthographic_projection(
        camera_x - view_width  / 2.0,
        camera_x + view_width  / 2.0,
        camera_y - view_height / 2.0,
        camera_y + view_height / 2.0,
      ),
      .screen_size = .{
        @as(f32, @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.width)),
        @as(f32, @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.height)),
      },
    };
    const uniform_destination: [*]u8 = @ptrCast(@alignCast(state.uniform_buffers[frame].mem.data));
    const uniform_source: [*]const u8 = @ptrCast(&globals);
    @memcpy(uniform_destination[0..@sizeOf(Globals)], uniform_source[0..@sizeOf(Globals)]);

    if (self.lighting_enabled) {
      const left    = camera_x - view_width  / 2.0;
      const right   = camera_x + view_width  / 2.0;
      const bottom  = camera_y - view_height / 2.0;
      const top     = camera_y + view_height / 2.0;
      const texel_w = 1.0 / @as(f32, @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.width));
      const texel_h = 1.0 / @as(f32, @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.height));
      const lighting_uniforms = LightingUniforms{
        .camera_bounds   = .{ left, right, bottom, top },
        .light_position  = self.light_position,
        .light_radius    = self.light_radius,
        .light_intensity = self.light_intensity,
        .light_color     = self.light_color,
        .texel_size      = .{ texel_w, texel_h },
      };
      const light_destination : [*]u8 = @ptrCast(@alignCast(state.lighting_uniform_buffers[frame].mem.data));
      const light_source      : [*]const u8 = @ptrCast(&lighting_uniforms);
      @memcpy(light_destination[0..@sizeOf(LightingUniforms)], light_source[0..@sizeOf(LightingUniforms)]);
    }

    const command_buffer = &state.sync.buffer[frame];
    command_buffer.reset(.{});
    command_buffer.begin();

    const swapchain_viewport = cvk.C.VkViewport{
      .x        = 0,
      .y        = 0,
      .width    = @as(f32, @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.width)),
      .height   = @as(f32, @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.height)),
      .minDepth = 0.0,
      .maxDepth = 1.0,
    };
    const swapchain_scissor = cvk.C.VkRect2D{
      .offset = .{ .x = 0, .y = 0 },
      .extent = state.gpu.device.swapchain.cfg.imageExtent,
    };

    if (self.lighting_enabled) {
      // --- Deferred path: shapes → gbuffer (MRT), then composite → swapchain ---

      // Pass 1: Draw shapes to gbuffer (albedo + emission) — MRT with 2 color attachments
      const bg = dracula.background;
      command_buffer.image_handle_transition(state.gbuffer_images[frame].ct, .{
        .layout_old = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
        .layout_new = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .access_src = 0,
        .access_trg = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .stage_src  = cvk.C.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        .stage_trg  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      });
      command_buffer.image_handle_transition(state.emission_images[frame].ct, .{
        .layout_old = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
        .layout_new = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .access_src = 0,
        .access_trg = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .stage_src  = cvk.C.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        .stage_trg  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      });
      const gbuffer_attachments = [2]cvk.C.VkRenderingAttachmentInfo{
        .{
          .sType       = cvk.C.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
          .imageView   = state.gbuffer_views[frame].ct,
          .imageLayout = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          .loadOp      = cvk.C.VK_ATTACHMENT_LOAD_OP_CLEAR,
          .storeOp     = cvk.C.VK_ATTACHMENT_STORE_OP_STORE,
          .clearValue  = .{ .color = .{ .float32 = .{ @floatCast(bg.r()), @floatCast(bg.g()), @floatCast(bg.b()), 0.0 } } },
        },
        .{
          .sType       = cvk.C.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
          .imageView   = state.emission_views[frame].ct,
          .imageLayout = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          .loadOp      = cvk.C.VK_ATTACHMENT_LOAD_OP_CLEAR,
          .storeOp     = cvk.C.VK_ATTACHMENT_STORE_OP_STORE,
          .clearValue  = .{ .color = .{ .float32 = .{ 0, 0, 0, 0 } } },
        },
      };
      cvk.C.vkCmdBeginRendering(command_buffer.ct, &cvk.C.VkRenderingInfo{
        .sType                = cvk.C.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea           = .{ .offset = .{}, .extent = state.gpu.device.swapchain.cfg.imageExtent },
        .layerCount           = 1,
        .colorAttachmentCount = 2,
        .pColorAttachments    = @ptrCast(&gbuffer_attachments),
      });

      command_buffer.graphics_bind(&state.gbuffer_pipeline);
      command_buffer.viewport_set(swapchain_viewport);
      command_buffer.scissor_set(swapchain_scissor);

      const vertex_buffers_raw = [_]cvk.C.VkBuffer{state.vertex.data.ct};
      const instance_buffers_raw = [_]cvk.C.VkBuffer{state.instance_buffers[frame].data.ct};
      const zero_offset = [_]cvk.C.VkDeviceSize{0};
      cvk.C.vkCmdBindVertexBuffers(command_buffer.ct, 0, 1, &vertex_buffers_raw, &zero_offset);
      cvk.C.vkCmdBindVertexBuffers(command_buffer.ct, 1, 1, &instance_buffers_raw, &zero_offset);
      cvk.C.vkCmdBindIndexBuffer(command_buffer.ct, state.index.data.ct, 0, cvk.C.VK_INDEX_TYPE_UINT16);
      cvk.C.vkCmdBindDescriptorSets(
        command_buffer.ct,
        cvk.C.VK_PIPELINE_BIND_POINT_GRAPHICS,
        state.gbuffer_pipeline.layout.ct,
        0, 1, &state.descriptor_sets[frame],
        0, null,
      );

      command_buffer.draw_indexed(.{
        .indices_len  = 6,
        .instance_len = self.instance_count,
      });

      command_buffer.rendering_end();

      // Barrier: gbuffer + emission writes → subsequent reads
      command_buffer.image_handle_transition(state.gbuffer_images[frame].ct, .{
        .layout_old = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .layout_new = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .access_src = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .access_trg = cvk.C.VK_ACCESS_SHADER_READ_BIT,
        .stage_src  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .stage_trg  = cvk.C.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      });
      command_buffer.image_handle_transition(state.emission_images[frame].ct, .{
        .layout_old = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .layout_new = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .access_src = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .access_trg = cvk.C.VK_ACCESS_SHADER_READ_BIT,
        .stage_src  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .stage_trg  = cvk.C.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      });

      // Pass 2: JFA — build screen-space distance field
      const jfa_base = frame * 2;
      var jfa_result_src: u32 = 0;
      {
        const jfa_texel_w = 1.0 / @as(f32, @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.width));
        const jfa_texel_h = 1.0 / @as(f32, @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.height));
        const max_dim = @max(state.gpu.device.swapchain.cfg.imageExtent.width, state.gpu.device.swapchain.cfg.imageExtent.height);

        // Seed pass: gbuffer occupancy → jfa[0]
        command_buffer.image_handle_transition(state.jfa_images[jfa_base + 0].ct, .{
          .layout_old = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
          .layout_new = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          .access_src = 0,
          .access_trg = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
          .stage_src  = cvk.C.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
          .stage_trg  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        });
        command_buffer.rendering_begin(.{
          .rendering  = &state.jfa_rendering,
          .image_view = state.jfa_views[jfa_base + 0].ct,
        });
        command_buffer.graphics_bind(&state.jfa_seed_pipeline);
        command_buffer.viewport_set(swapchain_viewport);
        command_buffer.scissor_set(swapchain_scissor);
        cvk.C.vkCmdBindDescriptorSets(
          command_buffer.ct, cvk.C.VK_PIPELINE_BIND_POINT_GRAPHICS,
          state.jfa_seed_pipeline.layout.ct,
          0, 1, &state.jfa_seed_descriptor_sets[frame], 0, null,
        );
        cvk.C.vkCmdDraw(command_buffer.ct, 3, 1, 0, 0);
        command_buffer.rendering_end();

        // Barrier: JFA seed writes → first step reads
        command_buffer.image_handle_transition(state.jfa_images[jfa_base + 0].ct, .{
          .layout_old = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          .layout_new = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
          .access_src = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
          .access_trg = cvk.C.VK_ACCESS_SHADER_READ_BIT,
          .stage_src  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
          .stage_trg  = cvk.C.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        });

        // Step passes: ping-pong
        var step_size: u32 = max_dim / 2;
        while (step_size >= 1) : (step_size /= 2) {
          const dst = 1 - jfa_result_src;
          const push = JfaPushConstants{
            .step_size  = @floatFromInt(step_size),
            .texel_size = .{ jfa_texel_w, jfa_texel_h },
          };

          command_buffer.image_handle_transition(state.jfa_images[jfa_base + dst].ct, .{
            .layout_old = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
            .layout_new = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .access_src = 0,
            .access_trg = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .stage_src  = cvk.C.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            .stage_trg  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
          });
          command_buffer.rendering_begin(.{
            .rendering  = &state.jfa_rendering,
            .image_view = state.jfa_views[jfa_base + dst].ct,
          });
          command_buffer.graphics_bind(&state.jfa_step_pipeline);
          command_buffer.viewport_set(swapchain_viewport);
          command_buffer.scissor_set(swapchain_scissor);
          cvk.C.vkCmdBindDescriptorSets(
            command_buffer.ct, cvk.C.VK_PIPELINE_BIND_POINT_GRAPHICS,
            state.jfa_step_pipeline.layout.ct,
            0, 1, &state.jfa_step_descriptor_sets[jfa_base + jfa_result_src], 0, null,
          );
          cvk.C.vkCmdPushConstants(
            command_buffer.ct, state.jfa_step_pipeline.layout.ct,
            cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(JfaPushConstants), @ptrCast(&push),
          );
          cvk.C.vkCmdDraw(command_buffer.ct, 3, 1, 0, 0);
          command_buffer.rendering_end();

          // Barrier: step writes → next step/lighting reads
          command_buffer.image_handle_transition(state.jfa_images[jfa_base + dst].ct, .{
            .layout_old = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .layout_new = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .access_src = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .access_trg = cvk.C.VK_ACCESS_SHADER_READ_BIT,
            .stage_src  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .stage_trg  = cvk.C.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
          });

          jfa_result_src = dst;
        }
      }

      // Pass 3: Radiance Cascades — compute + merge per level (coarsest → finest)
      const screen_w: f32 = @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.width);
      const screen_h: f32 = @floatFromInt(state.gpu.device.swapchain.cfg.imageExtent.height);
      var merge_src: u32 = 0;
      var cascade_level: u32 = state.rc_cascade_count;
      while (cascade_level > 0) {
        cascade_level -= 1;

        // 3a: Compute this cascade level → rc_compute_image[frame]
        const cascade_push = RcCascadePushConstants{
          .cascade_level      = @intCast(cascade_level),
          .cascade0_dims      = RC_CASCADE0_DIMS,
          .cascade0_range     = RC_CASCADE0_RANGE,
          .cascade_resolution = .{ screen_w, screen_h },
          .scene_resolution   = .{ screen_w, screen_h },
        };

        command_buffer.image_handle_transition(state.rc_compute_images[frame].ct, .{
          .layout_old = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
          .layout_new = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          .access_src = 0,
          .access_trg = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
          .stage_src  = cvk.C.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
          .stage_trg  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        });
        command_buffer.rendering_begin(.{
          .rendering  = &state.rc_rendering,
          .image_view = state.rc_compute_views[frame].ct,
        });
        command_buffer.graphics_bind(&state.rc_cascade_pipeline);
        command_buffer.viewport_set(swapchain_viewport);
        command_buffer.scissor_set(swapchain_scissor);
        cvk.C.vkCmdBindDescriptorSets(
          command_buffer.ct, cvk.C.VK_PIPELINE_BIND_POINT_GRAPHICS,
          state.rc_cascade_pipeline.layout.ct,
          0, 1, &state.rc_cascade_desc_sets[frame * 2 + jfa_result_src], 0, null,
        );
        cvk.C.vkCmdPushConstants(
          command_buffer.ct, state.rc_cascade_pipeline.layout.ct,
          cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(RcCascadePushConstants), @ptrCast(&cascade_push),
        );
        cvk.C.vkCmdDraw(command_buffer.ct, 3, 1, 0, 0);
        command_buffer.rendering_end();

        command_buffer.image_handle_transition(state.rc_compute_images[frame].ct, .{
          .layout_old = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          .layout_new = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
          .access_src = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
          .access_trg = cvk.C.VK_ACCESS_SHADER_READ_BIT,
          .stage_src  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
          .stage_trg  = cvk.C.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        });

        // 3b: Merge this level → rc_merge_image[frame*2 + merge_dst]
        const merge_dst: u32 = 1 - merge_src;
        const merge_push = RcMergePushConstants{
          .current_cascade_level = @intCast(cascade_level),
          .num_cascade_levels    = @intCast(state.rc_cascade_count),
          .cascade0_dims         = RC_CASCADE0_DIMS,
          .cascade0_range        = RC_CASCADE0_RANGE,
          .cascade_resolution    = .{ screen_w, screen_h },
        };

        command_buffer.image_handle_transition(state.rc_merge_images[frame * 2 + merge_dst].ct, .{
          .layout_old = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
          .layout_new = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          .access_src = 0,
          .access_trg = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
          .stage_src  = cvk.C.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
          .stage_trg  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        });
        command_buffer.rendering_begin(.{
          .rendering  = &state.rc_rendering,
          .image_view = state.rc_merge_views[frame * 2 + merge_dst].ct,
        });
        command_buffer.graphics_bind(&state.rc_merge_pipeline);
        command_buffer.viewport_set(swapchain_viewport);
        command_buffer.scissor_set(swapchain_scissor);
        cvk.C.vkCmdBindDescriptorSets(
          command_buffer.ct, cvk.C.VK_PIPELINE_BIND_POINT_GRAPHICS,
          state.rc_merge_pipeline.layout.ct,
          0, 1, &state.rc_merge_desc_sets[frame * 2 + merge_src], 0, null,
        );
        cvk.C.vkCmdPushConstants(
          command_buffer.ct, state.rc_merge_pipeline.layout.ct,
          cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(RcMergePushConstants), @ptrCast(&merge_push),
        );
        cvk.C.vkCmdDraw(command_buffer.ct, 3, 1, 0, 0);
        command_buffer.rendering_end();

        command_buffer.image_handle_transition(state.rc_merge_images[frame * 2 + merge_dst].ct, .{
          .layout_old = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          .layout_new = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
          .access_src = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
          .access_trg = cvk.C.VK_ACCESS_SHADER_READ_BIT,
          .stage_src  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
          .stage_trg  = cvk.C.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        });

        merge_src = merge_dst;
      }

      // Pass 3c: RC gather — read merged cascade 0, write to lighting texture
      const gather_push = RcGatherPushConstants{
        .cascade0_dims      = RC_CASCADE0_DIMS,
        .cascade_resolution = .{ screen_w, screen_h },
      };
      command_buffer.image_handle_transition(state.lighting_images[frame].ct, .{
        .layout_old = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
        .layout_new = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .access_src = 0,
        .access_trg = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .stage_src  = cvk.C.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        .stage_trg  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      });
      command_buffer.rendering_begin(.{
        .rendering  = &state.lighting_rendering,
        .image_view = state.lighting_views[frame].ct,
      });
      command_buffer.graphics_bind(&state.rc_gather_pipeline);
      command_buffer.viewport_set(swapchain_viewport);
      command_buffer.scissor_set(swapchain_scissor);
      cvk.C.vkCmdBindDescriptorSets(
        command_buffer.ct, cvk.C.VK_PIPELINE_BIND_POINT_GRAPHICS,
        state.rc_gather_pipeline.layout.ct,
        0, 1, &state.rc_gather_desc_sets[frame * 2 + merge_src], 0, null,
      );
      cvk.C.vkCmdPushConstants(
        command_buffer.ct, state.rc_gather_pipeline.layout.ct,
        cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(RcGatherPushConstants), @ptrCast(&gather_push),
      );
      cvk.C.vkCmdDraw(command_buffer.ct, 3, 1, 0, 0);
      command_buffer.rendering_end();

      // Barrier: lighting writes → composite reads
      command_buffer.image_handle_transition(state.lighting_images[frame].ct, .{
        .layout_old = cvk.C.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .layout_new = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .access_src = cvk.C.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .access_trg = cvk.C.VK_ACCESS_SHADER_READ_BIT,
        .stage_src  = cvk.C.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .stage_trg  = cvk.C.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      });

      // Pass 4: Composite gbuffer to swapchain (dynamic rendering)
      state.forward_target.begin(&state.gpu, &state.sync, image_index, true);

      command_buffer.graphics_bind(&state.composite_pipeline);
      command_buffer.viewport_set(swapchain_viewport);
      command_buffer.scissor_set(swapchain_scissor);

      cvk.C.vkCmdBindDescriptorSets(
        command_buffer.ct,
        cvk.C.VK_PIPELINE_BIND_POINT_GRAPHICS,
        state.composite_pipeline.layout.ct,
        0, 1, &state.composite_descriptor_sets[frame],
        0, null,
      );

      cvk.C.vkCmdDraw(command_buffer.ct, 3, 1, 0, 0);

      state.forward_target.end(&state.gpu, &state.sync, image_index, true);
    } else {
      // --- Forward path: shapes → swapchain (dynamic rendering) ---
      state.forward_target.begin(&state.gpu, &state.sync, image_index, true);

      command_buffer.graphics_bind(&state.pipeline);
      command_buffer.viewport_set(swapchain_viewport);
      command_buffer.scissor_set(swapchain_scissor);

      const vertex_buffers_raw = [_]cvk.C.VkBuffer{state.vertex.data.ct};
      const instance_buffers_raw = [_]cvk.C.VkBuffer{state.instance_buffers[frame].data.ct};
      const zero_offset = [_]cvk.C.VkDeviceSize{0};
      cvk.C.vkCmdBindVertexBuffers(command_buffer.ct, 0, 1, &vertex_buffers_raw, &zero_offset);
      cvk.C.vkCmdBindVertexBuffers(command_buffer.ct, 1, 1, &instance_buffers_raw, &zero_offset);
      cvk.C.vkCmdBindIndexBuffer(command_buffer.ct, state.index.data.ct, 0, cvk.C.VK_INDEX_TYPE_UINT16);
      cvk.C.vkCmdBindDescriptorSets(
        command_buffer.ct,
        cvk.C.VK_PIPELINE_BIND_POINT_GRAPHICS,
        state.pipeline.layout.ct,
        0, 1, &state.descriptor_sets[frame],
        0, null,
      );

      command_buffer.draw_indexed(.{
        .indices_len  = 6,
        .instance_len = self.instance_count,
      });

      state.forward_target.end(&state.gpu, &state.sync, image_index, true);
    }

    command_buffer.end();

    state.sync.submit(&state.gpu, image_index);

    state.gpu.device.swapchain.present(image_index, &state.gpu.device.queue);

    state.sync.nextFrame();

    self.spent_ms = @floatCast((glfwGetTime() - draw_start) * 1000.0);
  }
};

fn orthographic_projection (left: f32, right: f32, bottom: f32, top: f32) [16]f32 {
  const right_left = right - left;
  const top_bottom = top - bottom;
  return .{
                2.0 / right_left,                            0, 0, 0,
                               0,             2.0 / top_bottom, 0, 0,
                               0,                            0, 1, 0,
    -(right + left) / right_left, -(top + bottom) / top_bottom, 0, 1,
  };
}

const enable_validation = false;

fn create_vulkan_state(system: *msys.System, allocator: std.mem.Allocator, instances: *[MAX_INSTANCES]ShapeInstance) !VulkanState {
  var state: VulkanState = .{};

  state.gpu = try mgpu.system.Gpu.create(system, allocator);

  // --- Forward rendering target (dynamic rendering) ---
  state.forward_target = mgpu.Target.clear(&state.gpu, dracula.background);

  // --- Descriptor set layout (raw Vulkan) ---
  const ubo_binding = cvk.C.VkDescriptorSetLayoutBinding{
    .binding         = 0,
    .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    .descriptorCount = 1,
    .stageFlags      = cvk.C.VK_SHADER_STAGE_VERTEX_BIT | cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
  };
  const layout_info = cvk.C.VkDescriptorSetLayoutCreateInfo{
    .sType        = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    .bindingCount = 1,
    .pBindings    = &ubo_binding,
  };
  if (cvk.C.vkCreateDescriptorSetLayout(state.gpu.device.logical.ct, &layout_info, null, &state.descriptor_set_layout) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetLayoutCreationFailed;

  // --- Pipeline ---
  try create_pipeline(&state);

  // --- Sync (command pool + buffers + semaphores + fences) ---
  state.sync = mgpu.Sync.create(&state.gpu);

  // --- Vertex + index buffers ---
  const quad_vertices = [4][2]f32{
    .{ -1.0, -1.0 },
    .{  1.0, -1.0 },
    .{  1.0,  1.0 },
    .{ -1.0,  1.0 },
  };
  const quad_indices = [6]u16{ 0, 1, 2, 0, 2, 3 };

  state.vertex = mgpu.Buffer.create(&state.gpu, @sizeOf(@TypeOf(quad_vertices)), @ptrCast(@constCast(&quad_vertices)), .{ .usage = cvk.C.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT });
  state.index = mgpu.Buffer.create(&state.gpu, @sizeOf(@TypeOf(quad_indices)), @ptrCast(@constCast(&quad_indices)), .{ .usage = cvk.C.VK_BUFFER_USAGE_INDEX_BUFFER_BIT });

  // --- Instance buffers (per frame, persistently mapped) ---
  const instance_buffer_size: usize = @as(usize, MAX_INSTANCES) * @sizeOf(ShapeInstance);
  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    state.instance_buffers[frame_index] = mgpu.Buffer.create(&state.gpu, instance_buffer_size, @ptrCast(instances), .{ .usage = cvk.C.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, .persistent = true });
  }

  // --- Uniform buffers (per frame, persistently mapped) ---
  var initial_globals = std.mem.zeroes(Globals);
  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    state.uniform_buffers[frame_index] = mgpu.Buffer.create(&state.gpu, @sizeOf(Globals), @ptrCast(&initial_globals), .{ .usage = cvk.C.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .persistent = true });
  }

  // --- Descriptor pool + sets (raw Vulkan) ---
  const pool_size = cvk.C.VkDescriptorPoolSize{
    .@"type"         = cvk.C.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    .descriptorCount = FRAMES_IN_FLIGHT,
  };
  const descriptor_pool_info = cvk.C.VkDescriptorPoolCreateInfo{
    .sType         = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    .maxSets       = FRAMES_IN_FLIGHT,
    .poolSizeCount = 1,
    .pPoolSizes    = &pool_size,
  };
  if (cvk.C.vkCreateDescriptorPool(state.gpu.device.logical.ct, &descriptor_pool_info, null, &state.descriptor_pool) != cvk.C.VK_SUCCESS)
    return error.DescriptorPoolCreationFailed;

  const set_layouts = [FRAMES_IN_FLIGHT]cvk.C.VkDescriptorSetLayout{
    state.descriptor_set_layout,
    state.descriptor_set_layout,
  };
  const set_alloc_info = cvk.C.VkDescriptorSetAllocateInfo{
    .sType              = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    .descriptorPool     = state.descriptor_pool,
    .descriptorSetCount = FRAMES_IN_FLIGHT,
    .pSetLayouts        = &set_layouts,
  };
  if (cvk.C.vkAllocateDescriptorSets(state.gpu.device.logical.ct, &set_alloc_info, &state.descriptor_sets) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetAllocationFailed;

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    const buffer_info = cvk.C.VkDescriptorBufferInfo{
      .buffer = state.uniform_buffers[frame_index].data.ct,
      .offset = 0,
      .range  = @sizeOf(Globals),
    };
    const write = cvk.C.VkWriteDescriptorSet{
      .sType           = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      .dstSet          = state.descriptor_sets[frame_index],
      .dstBinding      = 0,
      .dstArrayElement = 0,
      .descriptorCount = 1,
      .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      .pBufferInfo     = &buffer_info,
    };
    cvk.C.vkUpdateDescriptorSets(state.gpu.device.logical.ct, 1, &write, 0, null);
  }

  // --- G-buffer: off-screen render targets (albedo + emission) ---
  const device_local: cvk.memory.Flags = @intCast(cvk.C.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  const gbuffer_format = state.gpu.device.swapchain.attachment_cfg.format;

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    // Albedo image
    state.gbuffer_images[frame_index] = cvk.image.Data.create(.{
      .device_physical = &state.gpu.device.physical,
      .device_logical  = &state.gpu.device.logical,
      .format          = gbuffer_format,
      .width           = state.gpu.device.swapchain.cfg.imageExtent.width,
      .height          = state.gpu.device.swapchain.cfg.imageExtent.height,
      .depth           = 1,
      .dimensions      = cvk.C.VK_IMAGE_TYPE_2D,
      .usage           = @intCast(cvk.C.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | cvk.C.VK_IMAGE_USAGE_SAMPLED_BIT),
      .memory_flags    = device_local,
      .samples         = cvk.C.VK_SAMPLE_COUNT_1_BIT,
      .tiling          = cvk.C.VK_IMAGE_TILING_OPTIMAL,
      .layout          = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
      .mip_len         = 1,
      .layers_len      = 1,
      .allocator       = @ptrCast(&state.gpu.instance.allocator),
    });
    state.gbuffer_memory[frame_index] = cvk.Memory.create(.{
      .device_logical = &state.gpu.device.logical,
      .data           = null,
      .size_alloc     = state.gbuffer_images[frame_index].memory.requirements.size,
      .size_data      = 0,
      .kind           = state.gbuffer_images[frame_index].memory.kind,
      .persistent     = 0,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
    });
    state.gbuffer_images[frame_index].bind(.{
      .device_logical = &state.gpu.device.logical,
      .memory         = &state.gbuffer_memory[frame_index],
    });
    state.gbuffer_views[frame_index] = cvk.image.View.create(.{
      .image_data     = &state.gbuffer_images[frame_index],
      .device_logical = &state.gpu.device.logical,
      .aspect         = cvk.C.VK_IMAGE_ASPECT_COLOR_BIT,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
    });

    // Emission image
    state.emission_images[frame_index] = cvk.image.Data.create(.{
      .device_physical = &state.gpu.device.physical,
      .device_logical  = &state.gpu.device.logical,
      .format          = gbuffer_format,
      .width           = state.gpu.device.swapchain.cfg.imageExtent.width,
      .height          = state.gpu.device.swapchain.cfg.imageExtent.height,
      .depth           = 1,
      .dimensions      = cvk.C.VK_IMAGE_TYPE_2D,
      .usage           = @intCast(cvk.C.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | cvk.C.VK_IMAGE_USAGE_SAMPLED_BIT),
      .memory_flags    = device_local,
      .samples         = cvk.C.VK_SAMPLE_COUNT_1_BIT,
      .tiling          = cvk.C.VK_IMAGE_TILING_OPTIMAL,
      .layout          = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
      .mip_len         = 1,
      .layers_len      = 1,
      .allocator       = @ptrCast(&state.gpu.instance.allocator),
    });
    state.emission_memory[frame_index] = cvk.Memory.create(.{
      .device_logical = &state.gpu.device.logical,
      .data           = null,
      .size_alloc     = state.emission_images[frame_index].memory.requirements.size,
      .size_data      = 0,
      .kind           = state.emission_images[frame_index].memory.kind,
      .persistent     = 0,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
    });
    state.emission_images[frame_index].bind(.{
      .device_logical = &state.gpu.device.logical,
      .memory         = &state.emission_memory[frame_index],
    });
    state.emission_views[frame_index] = cvk.image.View.create(.{
      .image_data     = &state.emission_images[frame_index],
      .device_logical = &state.gpu.device.logical,
      .aspect         = cvk.C.VK_IMAGE_ASPECT_COLOR_BIT,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
    });
  }

  // --- G-buffer sampler ---
  state.gbuffer_sampler = cvk.image.Sampler.create(.{
    .device_physical = &state.gpu.device.physical,
    .device_logical  = &state.gpu.device.logical,
    .filter_min      = cvk.C.VK_FILTER_NEAREST,
    .filter_mag      = cvk.C.VK_FILTER_NEAREST,
    .address_U       = cvk.C.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    .address_V       = cvk.C.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    .address_W       = cvk.C.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    .lod_max         = 1.0,
    .allocator       = @ptrCast(&state.gpu.instance.allocator),
  });


  // --- G-buffer shape pipeline (MRT: 2 blend attachments) ---
  try create_gbuffer_pipeline(&state);

  // --- JFA ping-pong textures (RG16F) ---
  const jfa_format = cvk.C.VK_FORMAT_R16G16_SFLOAT;
  for (0..FRAMES_IN_FLIGHT * 2) |jfa_index| {
    state.jfa_images[jfa_index] = cvk.image.Data.create(.{
      .device_physical = &state.gpu.device.physical,
      .device_logical  = &state.gpu.device.logical,
      .format          = jfa_format,
      .width           = state.gpu.device.swapchain.cfg.imageExtent.width,
      .height          = state.gpu.device.swapchain.cfg.imageExtent.height,
      .depth           = 1,
      .dimensions      = cvk.C.VK_IMAGE_TYPE_2D,
      .usage           = @intCast(cvk.C.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | cvk.C.VK_IMAGE_USAGE_SAMPLED_BIT),
      .memory_flags    = device_local,
      .samples         = cvk.C.VK_SAMPLE_COUNT_1_BIT,
      .tiling          = cvk.C.VK_IMAGE_TILING_OPTIMAL,
      .layout          = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
      .mip_len         = 1,
      .layers_len      = 1,
      .allocator       = @ptrCast(&state.gpu.instance.allocator),
    });
    state.jfa_image_memory[jfa_index] = cvk.Memory.create(.{
      .device_logical = &state.gpu.device.logical,
      .data           = null,
      .size_alloc     = state.jfa_images[jfa_index].memory.requirements.size,
      .size_data      = 0,
      .kind           = state.jfa_images[jfa_index].memory.kind,
      .persistent     = 0,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
    });
    state.jfa_images[jfa_index].bind(.{
      .device_logical = &state.gpu.device.logical,
      .memory         = &state.jfa_image_memory[jfa_index],
    });
    state.jfa_views[jfa_index] = cvk.image.View.create(.{
      .image_data     = &state.jfa_images[jfa_index],
      .device_logical = &state.gpu.device.logical,
      .aspect         = cvk.C.VK_IMAGE_ASPECT_COLOR_BIT,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
    });
  }

  // --- JFA dynamic rendering config (single RG16F attachment) ---
  state.jfa_rendering = cvk.Rendering.create(.{
    .color   = jfa_format,
    .extent  = state.gpu.device.swapchain.cfg.imageExtent,
    .load_op = cvk.C.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
  });

  // --- JFA descriptor layouts ---
  const jfa_sampler_binding = cvk.C.VkDescriptorSetLayoutBinding{
    .binding         = 0,
    .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    .descriptorCount = 1,
    .stageFlags      = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
  };
  const jfa_layout_info = cvk.C.VkDescriptorSetLayoutCreateInfo{
    .sType        = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    .bindingCount = 1,
    .pBindings    = &jfa_sampler_binding,
  };
  if (cvk.C.vkCreateDescriptorSetLayout(state.gpu.device.logical.ct, &jfa_layout_info, null, &state.jfa_seed_descriptor_layout) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetLayoutCreationFailed;
  if (cvk.C.vkCreateDescriptorSetLayout(state.gpu.device.logical.ct, &jfa_layout_info, null, &state.jfa_step_descriptor_layout) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetLayoutCreationFailed;

  // --- JFA descriptor pool + sets ---
  const jfa_pool_size = cvk.C.VkDescriptorPoolSize{
    .@"type"         = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    .descriptorCount = FRAMES_IN_FLIGHT + FRAMES_IN_FLIGHT * 2,
  };
  const jfa_pool_info = cvk.C.VkDescriptorPoolCreateInfo{
    .sType         = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    .maxSets       = FRAMES_IN_FLIGHT + FRAMES_IN_FLIGHT * 2,
    .poolSizeCount = 1,
    .pPoolSizes    = &jfa_pool_size,
  };
  if (cvk.C.vkCreateDescriptorPool(state.gpu.device.logical.ct, &jfa_pool_info, null, &state.jfa_descriptor_pool) != cvk.C.VK_SUCCESS)
    return error.DescriptorPoolCreationFailed;

  // Seed descriptor sets: bind gbuffer albedo per frame
  const jfa_seed_layouts = [FRAMES_IN_FLIGHT]cvk.C.VkDescriptorSetLayout{
    state.jfa_seed_descriptor_layout,
    state.jfa_seed_descriptor_layout,
  };
  const jfa_seed_alloc = cvk.C.VkDescriptorSetAllocateInfo{
    .sType              = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    .descriptorPool     = state.jfa_descriptor_pool,
    .descriptorSetCount = FRAMES_IN_FLIGHT,
    .pSetLayouts        = &jfa_seed_layouts,
  };
  if (cvk.C.vkAllocateDescriptorSets(state.gpu.device.logical.ct, &jfa_seed_alloc, &state.jfa_seed_descriptor_sets) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetAllocationFailed;

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    const image_info = cvk.C.VkDescriptorImageInfo{
      .sampler     = state.gbuffer_sampler.ct,
      .imageView   = state.gbuffer_views[frame_index].ct,
      .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    };
    const write = cvk.C.VkWriteDescriptorSet{
      .sType           = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      .dstSet          = state.jfa_seed_descriptor_sets[frame_index],
      .dstBinding      = 0,
      .descriptorCount = 1,
      .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      .pImageInfo      = &image_info,
    };
    cvk.C.vkUpdateDescriptorSets(state.gpu.device.logical.ct, 1, &write, 0, null);
  }

  // Step descriptor sets: bind each JFA texture
  const jfa_step_layouts = [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSetLayout{
    state.jfa_step_descriptor_layout,
    state.jfa_step_descriptor_layout,
    state.jfa_step_descriptor_layout,
    state.jfa_step_descriptor_layout,
  };
  const jfa_step_alloc = cvk.C.VkDescriptorSetAllocateInfo{
    .sType              = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    .descriptorPool     = state.jfa_descriptor_pool,
    .descriptorSetCount = FRAMES_IN_FLIGHT * 2,
    .pSetLayouts        = &jfa_step_layouts,
  };
  if (cvk.C.vkAllocateDescriptorSets(state.gpu.device.logical.ct, &jfa_step_alloc, &state.jfa_step_descriptor_sets) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetAllocationFailed;

  for (0..FRAMES_IN_FLIGHT * 2) |jfa_index| {
    const image_info = cvk.C.VkDescriptorImageInfo{
      .sampler     = state.gbuffer_sampler.ct,
      .imageView   = state.jfa_views[jfa_index].ct,
      .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    };
    const write = cvk.C.VkWriteDescriptorSet{
      .sType           = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      .dstSet          = state.jfa_step_descriptor_sets[jfa_index],
      .dstBinding      = 0,
      .descriptorCount = 1,
      .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      .pImageInfo      = &image_info,
    };
    cvk.C.vkUpdateDescriptorSets(state.gpu.device.logical.ct, 1, &write, 0, null);
  }

  // --- JFA pipelines ---
  try create_jfa_seed_pipeline(&state);
  try create_jfa_step_pipeline(&state);

  // --- Lighting accumulation texture ---
  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    state.lighting_images[frame_index] = cvk.image.Data.create(.{
      .device_physical = &state.gpu.device.physical,
      .device_logical  = &state.gpu.device.logical,
      .format          = gbuffer_format,
      .width           = state.gpu.device.swapchain.cfg.imageExtent.width,
      .height          = state.gpu.device.swapchain.cfg.imageExtent.height,
      .depth           = 1,
      .dimensions      = cvk.C.VK_IMAGE_TYPE_2D,
      .usage           = @intCast(cvk.C.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | cvk.C.VK_IMAGE_USAGE_SAMPLED_BIT),
      .memory_flags    = device_local,
      .samples         = cvk.C.VK_SAMPLE_COUNT_1_BIT,
      .tiling          = cvk.C.VK_IMAGE_TILING_OPTIMAL,
      .layout          = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
      .mip_len         = 1,
      .layers_len      = 1,
      .allocator       = @ptrCast(&state.gpu.instance.allocator),
    });
    state.lighting_memory[frame_index] = cvk.Memory.create(.{
      .device_logical = &state.gpu.device.logical,
      .data           = null,
      .size_alloc     = state.lighting_images[frame_index].memory.requirements.size,
      .size_data      = 0,
      .kind           = state.lighting_images[frame_index].memory.kind,
      .persistent     = 0,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
    });
    state.lighting_images[frame_index].bind(.{
      .device_logical = &state.gpu.device.logical,
      .memory         = &state.lighting_memory[frame_index],
    });
    state.lighting_views[frame_index] = cvk.image.View.create(.{
      .image_data     = &state.lighting_images[frame_index],
      .device_logical = &state.gpu.device.logical,
      .aspect         = cvk.C.VK_IMAGE_ASPECT_COLOR_BIT,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
    });
  }

  // --- Lighting dynamic rendering config (single color attachment) ---
  state.lighting_rendering = cvk.Rendering.create(.{
    .color   = gbuffer_format,
    .extent  = state.gpu.device.swapchain.cfg.imageExtent,
    .load_op = cvk.C.VK_ATTACHMENT_LOAD_OP_CLEAR,
    .clear   = &.{ .color = .{ .float32 = .{ 0, 0, 0, 0 } } },
  });

  // --- Lighting uniform buffers (per frame, persistently mapped) ---
  var initial_lighting = std.mem.zeroes(LightingUniforms);
  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    state.lighting_uniform_buffers[frame_index] = mgpu.Buffer.create(&state.gpu, @sizeOf(LightingUniforms), @ptrCast(&initial_lighting), .{ .usage = cvk.C.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .persistent = true });
  }

  // --- Lighting descriptor set layout (1 UBO + 1 JFA sampler) ---
  const lighting_bindings = [2]cvk.C.VkDescriptorSetLayoutBinding{
    .{
      .binding         = 0,
      .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      .descriptorCount = 1,
      .stageFlags      = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
    },
    .{
      .binding         = 1,
      .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      .descriptorCount = 1,
      .stageFlags      = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
    },
  };
  const lighting_layout_info = cvk.C.VkDescriptorSetLayoutCreateInfo{
    .sType        = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    .bindingCount = 2,
    .pBindings    = &lighting_bindings,
  };
  if (cvk.C.vkCreateDescriptorSetLayout(state.gpu.device.logical.ct, &lighting_layout_info, null, &state.lighting_descriptor_layout) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetLayoutCreationFailed;

  // --- Lighting descriptor pool + sets (2 per frame: one per JFA result texture) ---
  const lighting_pool_sizes = [2]cvk.C.VkDescriptorPoolSize{
    .{ .@"type" = cvk.C.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptorCount = FRAMES_IN_FLIGHT * 2 },
    .{ .@"type" = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = FRAMES_IN_FLIGHT * 2 },
  };
  const lighting_pool_info = cvk.C.VkDescriptorPoolCreateInfo{
    .sType         = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    .maxSets       = FRAMES_IN_FLIGHT * 2,
    .poolSizeCount = 2,
    .pPoolSizes    = &lighting_pool_sizes,
  };
  if (cvk.C.vkCreateDescriptorPool(state.gpu.device.logical.ct, &lighting_pool_info, null, &state.lighting_descriptor_pool) != cvk.C.VK_SUCCESS)
    return error.DescriptorPoolCreationFailed;

  const lighting_set_layouts = [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSetLayout{
    state.lighting_descriptor_layout,
    state.lighting_descriptor_layout,
    state.lighting_descriptor_layout,
    state.lighting_descriptor_layout,
  };
  const lighting_set_alloc_info = cvk.C.VkDescriptorSetAllocateInfo{
    .sType              = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    .descriptorPool     = state.lighting_descriptor_pool,
    .descriptorSetCount = FRAMES_IN_FLIGHT * 2,
    .pSetLayouts        = &lighting_set_layouts,
  };
  if (cvk.C.vkAllocateDescriptorSets(state.gpu.device.logical.ct, &lighting_set_alloc_info, &state.lighting_descriptor_sets) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetAllocationFailed;

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    for (0..2) |jfa_variant| {
      const set_index = frame_index * 2 + jfa_variant;
      const jfa_texture_index = frame_index * 2 + jfa_variant;
      const buffer_info = cvk.C.VkDescriptorBufferInfo{
        .buffer = state.lighting_uniform_buffers[frame_index].data.ct,
        .offset = 0,
        .range  = @sizeOf(LightingUniforms),
      };
      const jfa_image_info = cvk.C.VkDescriptorImageInfo{
        .sampler     = state.gbuffer_sampler.ct,
        .imageView   = state.jfa_views[jfa_texture_index].ct,
        .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      };
      const writes = [2]cvk.C.VkWriteDescriptorSet{
        .{
          .sType           = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          .dstSet          = state.lighting_descriptor_sets[set_index],
          .dstBinding      = 0,
          .descriptorCount = 1,
          .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
          .pBufferInfo     = &buffer_info,
        },
        .{
          .sType           = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
          .dstSet          = state.lighting_descriptor_sets[set_index],
          .dstBinding      = 1,
          .descriptorCount = 1,
          .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
          .pImageInfo      = &jfa_image_info,
        },
      };
      cvk.C.vkUpdateDescriptorSets(state.gpu.device.logical.ct, 2, &writes, 0, null);
    }
  }

  // --- Lighting pipeline ---
  try create_lighting_pipeline(&state);

  // --- Radiance Cascades ---
  const rc_format = cvk.C.VK_FORMAT_R16G16B16A16_SFLOAT;
  const rc_width = state.gpu.device.swapchain.cfg.imageExtent.width;
  const rc_height = state.gpu.device.swapchain.cfg.imageExtent.height;
  // Compute cascade level count from screen diagonal
  {
    const diag_sq = @as(f32, @floatFromInt(rc_width)) * @as(f32, @floatFromInt(rc_width)) +
                    @as(f32, @floatFromInt(rc_height)) * @as(f32, @floatFromInt(rc_height));
    const diagonal = @sqrt(diag_sq);
    var level: u32 = 0;
    while (level < RC_MAX_LEVELS) : (level += 1) {
      const fl: f32 = @floatFromInt(level);
      const range_end = RC_CASCADE0_RANGE * (1.0 - std.math.pow(f32, RC_RANGE_FACTOR, fl + 1.0)) / (1.0 - RC_RANGE_FACTOR);
      state.rc_cascade_count = level + 1;
      if (range_end > diagonal) break;
    }
  }

  // RC compute images (1 per frame — overwritten each cascade level)
  for (0..FRAMES_IN_FLIGHT) |fi| {
    state.rc_compute_images[fi] = cvk.image.Data.create(.{
      .device_physical = &state.gpu.device.physical, .device_logical = &state.gpu.device.logical,
      .format = rc_format, .width = rc_width, .height = rc_height, .depth = 1,
      .dimensions = cvk.C.VK_IMAGE_TYPE_2D,
      .usage = @intCast(cvk.C.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | cvk.C.VK_IMAGE_USAGE_SAMPLED_BIT),
      .memory_flags = device_local, .samples = cvk.C.VK_SAMPLE_COUNT_1_BIT,
      .tiling = cvk.C.VK_IMAGE_TILING_OPTIMAL, .layout = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
      .mip_len = 1, .layers_len = 1, .allocator = @ptrCast(&state.gpu.instance.allocator),
    });
    state.rc_compute_memory[fi] = cvk.Memory.create(.{
      .device_logical = &state.gpu.device.logical, .data = null,
      .size_alloc = state.rc_compute_images[fi].memory.requirements.size, .size_data = 0,
      .kind = state.rc_compute_images[fi].memory.kind, .persistent = 0,
      .allocator = @ptrCast(&state.gpu.instance.allocator),
    });
    state.rc_compute_images[fi].bind(.{ .device_logical = &state.gpu.device.logical, .memory = &state.rc_compute_memory[fi] });
    state.rc_compute_views[fi] = cvk.image.View.create(.{
      .image_data = &state.rc_compute_images[fi], .device_logical = &state.gpu.device.logical,
      .aspect = cvk.C.VK_IMAGE_ASPECT_COLOR_BIT, .allocator = @ptrCast(&state.gpu.instance.allocator),
    });
  }

  // RC merge images (2 per frame — ping-pong)
  for (0..FRAMES_IN_FLIGHT * 2) |mi| {
    state.rc_merge_images[mi] = cvk.image.Data.create(.{
      .device_physical = &state.gpu.device.physical, .device_logical = &state.gpu.device.logical,
      .format = rc_format, .width = rc_width, .height = rc_height, .depth = 1,
      .dimensions = cvk.C.VK_IMAGE_TYPE_2D,
      .usage = @intCast(cvk.C.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | cvk.C.VK_IMAGE_USAGE_SAMPLED_BIT),
      .memory_flags = device_local, .samples = cvk.C.VK_SAMPLE_COUNT_1_BIT,
      .tiling = cvk.C.VK_IMAGE_TILING_OPTIMAL, .layout = cvk.C.VK_IMAGE_LAYOUT_UNDEFINED,
      .mip_len = 1, .layers_len = 1, .allocator = @ptrCast(&state.gpu.instance.allocator),
    });
    state.rc_merge_memory[mi] = cvk.Memory.create(.{
      .device_logical = &state.gpu.device.logical, .data = null,
      .size_alloc = state.rc_merge_images[mi].memory.requirements.size, .size_data = 0,
      .kind = state.rc_merge_images[mi].memory.kind, .persistent = 0,
      .allocator = @ptrCast(&state.gpu.instance.allocator),
    });
    state.rc_merge_images[mi].bind(.{ .device_logical = &state.gpu.device.logical, .memory = &state.rc_merge_memory[mi] });
    state.rc_merge_views[mi] = cvk.image.View.create(.{
      .image_data = &state.rc_merge_images[mi], .device_logical = &state.gpu.device.logical,
      .aspect = cvk.C.VK_IMAGE_ASPECT_COLOR_BIT, .allocator = @ptrCast(&state.gpu.instance.allocator),
    });
  }

  // RC dynamic rendering config (shared for compute + merge, RGBA16F)
  state.rc_rendering = cvk.Rendering.create(.{
    .color   = rc_format,
    .extent  = state.gpu.device.swapchain.cfg.imageExtent,
    .load_op = cvk.C.VK_ATTACHMENT_LOAD_OP_CLEAR,
    .clear   = &.{ .color = .{ .float32 = .{ 0, 0, 0, 0 } } },
  });

  // --- RC cascade descriptor layout (2 samplers: emission + JFA) ---
  const rc_cascade_bindings = [2]cvk.C.VkDescriptorSetLayoutBinding{
    .{ .binding = 0, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1, .stageFlags = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT },
    .{ .binding = 1, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1, .stageFlags = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT },
  };
  const rc_cascade_layout_info = cvk.C.VkDescriptorSetLayoutCreateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 2, .pBindings = &rc_cascade_bindings,
  };
  if (cvk.C.vkCreateDescriptorSetLayout(state.gpu.device.logical.ct, &rc_cascade_layout_info, null, &state.rc_cascade_desc_layout) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetLayoutCreationFailed;

  // RC cascade descriptor pool + sets (4 sets: 2 frames × 2 JFA variants)
  const rc_cascade_pool_size = cvk.C.VkDescriptorPoolSize{
    .@"type" = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = FRAMES_IN_FLIGHT * 2 * 2,
  };
  const rc_cascade_pool_info = cvk.C.VkDescriptorPoolCreateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = FRAMES_IN_FLIGHT * 2, .poolSizeCount = 1, .pPoolSizes = &rc_cascade_pool_size,
  };
  if (cvk.C.vkCreateDescriptorPool(state.gpu.device.logical.ct, &rc_cascade_pool_info, null, &state.rc_cascade_desc_pool) != cvk.C.VK_SUCCESS)
    return error.DescriptorPoolCreationFailed;

  var rc_cascade_set_layouts: [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSetLayout = undefined;
  for (&rc_cascade_set_layouts) |*layout| layout.* = state.rc_cascade_desc_layout;
  const rc_cascade_alloc_info = cvk.C.VkDescriptorSetAllocateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    .descriptorPool = state.rc_cascade_desc_pool, .descriptorSetCount = FRAMES_IN_FLIGHT * 2, .pSetLayouts = &rc_cascade_set_layouts,
  };
  if (cvk.C.vkAllocateDescriptorSets(state.gpu.device.logical.ct, &rc_cascade_alloc_info, &state.rc_cascade_desc_sets) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetAllocationFailed;

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    for (0..2) |jfa_variant| {
      const set_index = frame_index * 2 + jfa_variant;
      const emission_info = cvk.C.VkDescriptorImageInfo{
        .sampler = state.gbuffer_sampler.ct, .imageView = state.emission_views[frame_index].ct,
        .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      };
      const jfa_info = cvk.C.VkDescriptorImageInfo{
        .sampler = state.gbuffer_sampler.ct, .imageView = state.jfa_views[frame_index * 2 + jfa_variant].ct,
        .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      };
      const writes = [2]cvk.C.VkWriteDescriptorSet{
        .{
          .sType = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = state.rc_cascade_desc_sets[set_index],
          .dstBinding = 0, .descriptorCount = 1, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &emission_info,
        },
        .{
          .sType = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = state.rc_cascade_desc_sets[set_index],
          .dstBinding = 1, .descriptorCount = 1, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &jfa_info,
        },
      };
      cvk.C.vkUpdateDescriptorSets(state.gpu.device.logical.ct, 2, &writes, 0, null);
    }
  }

  try create_rc_cascade_pipeline(&state);

  // --- RC merge descriptor layout (2 samplers: compute result + previous merge) ---
  const rc_merge_bindings = [2]cvk.C.VkDescriptorSetLayoutBinding{
    .{ .binding = 0, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1, .stageFlags = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT },
    .{ .binding = 1, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1, .stageFlags = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT },
  };
  const rc_merge_layout_info = cvk.C.VkDescriptorSetLayoutCreateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 2, .pBindings = &rc_merge_bindings,
  };
  if (cvk.C.vkCreateDescriptorSetLayout(state.gpu.device.logical.ct, &rc_merge_layout_info, null, &state.rc_merge_desc_layout) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetLayoutCreationFailed;

  // RC merge descriptor pool + sets (4 sets: 2 frames × 2 merge source variants)
  const rc_merge_pool_size = cvk.C.VkDescriptorPoolSize{
    .@"type" = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = FRAMES_IN_FLIGHT * 2 * 2,
  };
  const rc_merge_pool_info = cvk.C.VkDescriptorPoolCreateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = FRAMES_IN_FLIGHT * 2, .poolSizeCount = 1, .pPoolSizes = &rc_merge_pool_size,
  };
  if (cvk.C.vkCreateDescriptorPool(state.gpu.device.logical.ct, &rc_merge_pool_info, null, &state.rc_merge_desc_pool) != cvk.C.VK_SUCCESS)
    return error.DescriptorPoolCreationFailed;

  var rc_merge_set_layouts: [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSetLayout = undefined;
  for (&rc_merge_set_layouts) |*layout| layout.* = state.rc_merge_desc_layout;
  const rc_merge_alloc_info = cvk.C.VkDescriptorSetAllocateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    .descriptorPool = state.rc_merge_desc_pool, .descriptorSetCount = FRAMES_IN_FLIGHT * 2, .pSetLayouts = &rc_merge_set_layouts,
  };
  if (cvk.C.vkAllocateDescriptorSets(state.gpu.device.logical.ct, &rc_merge_alloc_info, &state.rc_merge_desc_sets) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetAllocationFailed;

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    for (0..2) |merge_variant| {
      const set_index = frame_index * 2 + merge_variant;
      const compute_info = cvk.C.VkDescriptorImageInfo{
        .sampler = state.gbuffer_sampler.ct, .imageView = state.rc_compute_views[frame_index].ct,
        .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      };
      const merge_info = cvk.C.VkDescriptorImageInfo{
        .sampler = state.gbuffer_sampler.ct, .imageView = state.rc_merge_views[frame_index * 2 + merge_variant].ct,
        .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      };
      const writes = [2]cvk.C.VkWriteDescriptorSet{
        .{
          .sType = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = state.rc_merge_desc_sets[set_index],
          .dstBinding = 0, .descriptorCount = 1, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &compute_info,
        },
        .{
          .sType = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = state.rc_merge_desc_sets[set_index],
          .dstBinding = 1, .descriptorCount = 1, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &merge_info,
        },
      };
      cvk.C.vkUpdateDescriptorSets(state.gpu.device.logical.ct, 2, &writes, 0, null);
    }
  }

  try create_rc_merge_pipeline(&state);

  // --- RC gather descriptor layout (1 sampler: merged cascade 0) ---
  const rc_gather_binding = cvk.C.VkDescriptorSetLayoutBinding{
    .binding = 0, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    .descriptorCount = 1, .stageFlags = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
  };
  const rc_gather_layout_info = cvk.C.VkDescriptorSetLayoutCreateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 1, .pBindings = &rc_gather_binding,
  };
  if (cvk.C.vkCreateDescriptorSetLayout(state.gpu.device.logical.ct, &rc_gather_layout_info, null, &state.rc_gather_desc_layout) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetLayoutCreationFailed;

  // RC gather descriptor pool + sets (4 sets: 2 frames × 2 merge result variants)
  const rc_gather_pool_size = cvk.C.VkDescriptorPoolSize{
    .@"type" = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = FRAMES_IN_FLIGHT * 2,
  };
  const rc_gather_pool_info = cvk.C.VkDescriptorPoolCreateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = FRAMES_IN_FLIGHT * 2, .poolSizeCount = 1, .pPoolSizes = &rc_gather_pool_size,
  };
  if (cvk.C.vkCreateDescriptorPool(state.gpu.device.logical.ct, &rc_gather_pool_info, null, &state.rc_gather_desc_pool) != cvk.C.VK_SUCCESS)
    return error.DescriptorPoolCreationFailed;

  var rc_gather_set_layouts: [FRAMES_IN_FLIGHT * 2]cvk.C.VkDescriptorSetLayout = undefined;
  for (&rc_gather_set_layouts) |*layout| layout.* = state.rc_gather_desc_layout;
  const rc_gather_alloc_info = cvk.C.VkDescriptorSetAllocateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    .descriptorPool = state.rc_gather_desc_pool, .descriptorSetCount = FRAMES_IN_FLIGHT * 2, .pSetLayouts = &rc_gather_set_layouts,
  };
  if (cvk.C.vkAllocateDescriptorSets(state.gpu.device.logical.ct, &rc_gather_alloc_info, &state.rc_gather_desc_sets) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetAllocationFailed;

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    for (0..2) |merge_variant| {
      const set_index = frame_index * 2 + merge_variant;
      const merged_info = cvk.C.VkDescriptorImageInfo{
        .sampler = state.gbuffer_sampler.ct, .imageView = state.rc_merge_views[frame_index * 2 + merge_variant].ct,
        .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      };
      const write = cvk.C.VkWriteDescriptorSet{
        .sType = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = state.rc_gather_desc_sets[set_index],
        .dstBinding = 0, .descriptorCount = 1, .descriptorType = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &merged_info,
      };
      cvk.C.vkUpdateDescriptorSets(state.gpu.device.logical.ct, 1, &write, 0, null);
    }
  }

  try create_rc_gather_pipeline(&state);

  // --- Composite descriptor set layout (3 samplers: albedo + emission + lighting) ---
  const composite_bindings = [3]cvk.C.VkDescriptorSetLayoutBinding{
    .{
      .binding         = 0,
      .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      .descriptorCount = 1,
      .stageFlags      = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
    },
    .{
      .binding         = 1,
      .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      .descriptorCount = 1,
      .stageFlags      = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
    },
    .{
      .binding         = 2,
      .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      .descriptorCount = 1,
      .stageFlags      = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
    },
  };
  const composite_layout_info = cvk.C.VkDescriptorSetLayoutCreateInfo{
    .sType        = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    .bindingCount = 3,
    .pBindings    = &composite_bindings,
  };
  if (cvk.C.vkCreateDescriptorSetLayout(state.gpu.device.logical.ct, &composite_layout_info, null, &state.composite_descriptor_layout) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetLayoutCreationFailed;

  // --- Composite descriptor pool + sets ---
  const composite_pool_size = cvk.C.VkDescriptorPoolSize{
    .@"type"         = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    .descriptorCount = FRAMES_IN_FLIGHT * 3,
  };
  const composite_pool_info = cvk.C.VkDescriptorPoolCreateInfo{
    .sType         = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
    .maxSets       = FRAMES_IN_FLIGHT,
    .poolSizeCount = 1,
    .pPoolSizes    = &composite_pool_size,
  };
  if (cvk.C.vkCreateDescriptorPool(state.gpu.device.logical.ct, &composite_pool_info, null, &state.composite_descriptor_pool) != cvk.C.VK_SUCCESS)
    return error.DescriptorPoolCreationFailed;

  const composite_set_layouts = [FRAMES_IN_FLIGHT]cvk.C.VkDescriptorSetLayout{
    state.composite_descriptor_layout,
    state.composite_descriptor_layout,
  };
  const composite_set_alloc_info = cvk.C.VkDescriptorSetAllocateInfo{
    .sType              = cvk.C.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
    .descriptorPool     = state.composite_descriptor_pool,
    .descriptorSetCount = FRAMES_IN_FLIGHT,
    .pSetLayouts        = &composite_set_layouts,
  };
  if (cvk.C.vkAllocateDescriptorSets(state.gpu.device.logical.ct, &composite_set_alloc_info, &state.composite_descriptor_sets) != cvk.C.VK_SUCCESS)
    return error.DescriptorSetAllocationFailed;

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    const image_infos = [3]cvk.C.VkDescriptorImageInfo{
      .{
        .sampler     = state.gbuffer_sampler.ct,
        .imageView   = state.gbuffer_views[frame_index].ct,
        .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      },
      .{
        .sampler     = state.gbuffer_sampler.ct,
        .imageView   = state.emission_views[frame_index].ct,
        .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      },
      .{
        .sampler     = state.gbuffer_sampler.ct,
        .imageView   = state.lighting_views[frame_index].ct,
        .imageLayout = cvk.C.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      },
    };
    const writes = [3]cvk.C.VkWriteDescriptorSet{
      .{
        .sType           = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet          = state.composite_descriptor_sets[frame_index],
        .dstBinding      = 0,
        .descriptorCount = 1,
        .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo      = &image_infos[0],
      },
      .{
        .sType           = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet          = state.composite_descriptor_sets[frame_index],
        .dstBinding      = 1,
        .descriptorCount = 1,
        .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo      = &image_infos[1],
      },
      .{
        .sType           = cvk.C.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet          = state.composite_descriptor_sets[frame_index],
        .dstBinding      = 2,
        .descriptorCount = 1,
        .descriptorType  = cvk.C.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo      = &image_infos[2],
      },
    };
    cvk.C.vkUpdateDescriptorSets(state.gpu.device.logical.ct, 3, &writes, 0, null);
  }

  // --- Composite pipeline ---
  try create_composite_pipeline(&state);

  return state;
}

fn create_pipeline(state: *VulkanState) !void {
  const vert_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/shape.vert.spv").*;
  const frag_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/shape.frag.spv").*;

  const vert_spirv = cvk.shader.SpirV{
    .ptr = @constCast(@ptrCast(@alignCast(&vert_array))),
    .len = vert_array.len / @sizeOf(u32),
  };
  const frag_spirv = cvk.shader.SpirV{
    .ptr = @constCast(@ptrCast(@alignCast(&frag_array))),
    .len = frag_array.len / @sizeOf(u32),
  };

  var vert_shader = cvk.Shader.create(.{
    .device_logical = &state.gpu.device.logical,
    .code           = &vert_spirv,
    .stage          = cvk.Shader.stages(&.{.vertex}),
    .allocator      = @ptrCast(&state.gpu.instance.allocator),
  });
  var frag_shader = cvk.Shader.create(.{
    .device_logical = &state.gpu.device.logical,
    .code           = &frag_spirv,
    .stage          = cvk.Shader.stages(&.{.fragment}),
    .allocator      = @ptrCast(&state.gpu.instance.allocator),
  });

  const stages_array = [_]cvk.C.VkPipelineShaderStageCreateInfo{ vert_shader.stage, frag_shader.stage };
  const stages = cvk.pipeline.shaderStage.List{
    .ptr = @constCast(&stages_array),
    .len = 2,
  };

  const binding_descriptions = [2]cvk.C.VkVertexInputBindingDescription{
    .{ .binding = 0, .stride = @sizeOf([2]f32), .inputRate = cvk.C.VK_VERTEX_INPUT_RATE_VERTEX },
    .{ .binding = 1, .stride = @sizeOf(ShapeInstance), .inputRate = cvk.C.VK_VERTEX_INPUT_RATE_INSTANCE },
  };

  const attribute_descriptions = [7]cvk.C.VkVertexInputAttributeDescription{
    .{ .location = 0, .binding = 0, .format = cvk.C.VK_FORMAT_R32G32_SFLOAT, .offset = 0 },
    .{ .location = 1, .binding = 1, .format = cvk.C.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(ShapeInstance, "position") },
    .{ .location = 2, .binding = 1, .format = cvk.C.VK_FORMAT_R32_SFLOAT, .offset = @offsetOf(ShapeInstance, "rotation") },
    .{ .location = 3, .binding = 1, .format = cvk.C.VK_FORMAT_R32_SFLOAT, .offset = @offsetOf(ShapeInstance, "scale_x") },
    .{ .location = 4, .binding = 1, .format = cvk.C.VK_FORMAT_R32_SFLOAT, .offset = @offsetOf(ShapeInstance, "scale_y") },
    .{ .location = 5, .binding = 1, .format = cvk.C.VK_FORMAT_R32_UINT, .offset = @offsetOf(ShapeInstance, "shape_type") },
    .{ .location = 6, .binding = 1, .format = cvk.C.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(ShapeInstance, "color") },
  };

  const vertex_input_info = cvk.C.VkPipelineVertexInputStateCreateInfo{
    .sType                           = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    .vertexBindingDescriptionCount   = 2,
    .pVertexBindingDescriptions      = &binding_descriptions,
    .vertexAttributeDescriptionCount = 7,
    .pVertexAttributeDescriptions    = &attribute_descriptions,
  };

  const input_assembly = cvk.C.VkPipelineInputAssemblyStateCreateInfo{
    .sType    = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    .topology = cvk.C.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
  };

  const viewport_state = cvk.C.VkPipelineViewportStateCreateInfo{
    .sType         = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    .viewportCount = 1,
    .scissorCount  = 1,
  };

  const rasterizer = cvk.C.VkPipelineRasterizationStateCreateInfo{
    .sType       = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    .polygonMode = cvk.C.VK_POLYGON_MODE_FILL,
    .cullMode    = cvk.C.VK_CULL_MODE_NONE,
    .frontFace   = cvk.C.VK_FRONT_FACE_COUNTER_CLOCKWISE,
    .lineWidth   = 1.0,
  };

  const multisampling = cvk.C.VkPipelineMultisampleStateCreateInfo{
    .sType                = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    .rasterizationSamples = cvk.C.VK_SAMPLE_COUNT_1_BIT,
  };

  const color_blend_attachment = cvk.C.VkPipelineColorBlendAttachmentState{
    .blendEnable         = 1,
    .srcColorBlendFactor = cvk.C.VK_BLEND_FACTOR_SRC_ALPHA,
    .dstColorBlendFactor = cvk.C.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
    .colorBlendOp        = cvk.C.VK_BLEND_OP_ADD,
    .srcAlphaBlendFactor = cvk.C.VK_BLEND_FACTOR_ONE,
    .dstAlphaBlendFactor = cvk.C.VK_BLEND_FACTOR_ZERO,
    .alphaBlendOp        = cvk.C.VK_BLEND_OP_ADD,
    .colorWriteMask      = @intCast(cvk.C.VK_COLOR_COMPONENT_R_BIT | cvk.C.VK_COLOR_COMPONENT_G_BIT | cvk.C.VK_COLOR_COMPONENT_B_BIT | cvk.C.VK_COLOR_COMPONENT_A_BIT),
  };

  const color_blending = cvk.C.VkPipelineColorBlendStateCreateInfo{
    .sType           = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    .attachmentCount = 1,
    .pAttachments    = &color_blend_attachment,
  };

  const dynamic_state_cfg = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });

  state.pipeline = cvk.pipeline.Graphics.create(.{
    .device_logical      = &state.gpu.device.logical,
    .allocator           = @ptrCast(&state.gpu.instance.allocator),
    .stages              = &stages,
    .state_vertexInput   = &vertex_input_info,
    .state_inputAssembly = &input_assembly,
    .state_viewport      = &viewport_state,
    .state_rasterization = &rasterizer,
    .state_multisample   = &multisampling,
    .state_colorBlend    = &color_blending,
    .state_dynamic       = &dynamic_state_cfg,
    .rendering           = &state.forward_target.ct,
    .layout              = &.{
      .device_logical    = &state.gpu.device.logical,
      .allocator         = @ptrCast(&state.gpu.instance.allocator),
      .sets_ptr          = &state.descriptor_set_layout,
      .sets_len          = 1,
    },
  });

  vert_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
  frag_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
}

// G-buffer pipeline: same shape shaders but with 2 color blend attachments for MRT
fn create_gbuffer_pipeline(state: *VulkanState) !void {
  const vert_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/shape.vert.spv").*;
  const frag_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/shape.frag.spv").*;

  const vert_spirv = cvk.shader.SpirV{
    .ptr = @constCast(@ptrCast(@alignCast(&vert_array))),
    .len = vert_array.len / @sizeOf(u32),
  };
  const frag_spirv = cvk.shader.SpirV{
    .ptr = @constCast(@ptrCast(@alignCast(&frag_array))),
    .len = frag_array.len / @sizeOf(u32),
  };

  var vert_shader = cvk.Shader.create(.{
    .device_logical = &state.gpu.device.logical,
    .code           = &vert_spirv,
    .stage          = cvk.Shader.stages(&.{.vertex}),
    .allocator      = @ptrCast(&state.gpu.instance.allocator),
  });
  var frag_shader = cvk.Shader.create(.{
    .device_logical = &state.gpu.device.logical,
    .code           = &frag_spirv,
    .stage          = cvk.Shader.stages(&.{.fragment}),
    .allocator      = @ptrCast(&state.gpu.instance.allocator),
  });

  const stages_array = [_]cvk.C.VkPipelineShaderStageCreateInfo{ vert_shader.stage, frag_shader.stage };

  const binding_descriptions = [2]cvk.C.VkVertexInputBindingDescription{
    .{ .binding = 0, .stride = @sizeOf([2]f32), .inputRate = cvk.C.VK_VERTEX_INPUT_RATE_VERTEX },
    .{ .binding = 1, .stride = @sizeOf(ShapeInstance), .inputRate = cvk.C.VK_VERTEX_INPUT_RATE_INSTANCE },
  };
  const attribute_descriptions = [7]cvk.C.VkVertexInputAttributeDescription{
    .{ .location = 0, .binding = 0, .format = cvk.C.VK_FORMAT_R32G32_SFLOAT, .offset = 0 },
    .{ .location = 1, .binding = 1, .format = cvk.C.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(ShapeInstance, "position") },
    .{ .location = 2, .binding = 1, .format = cvk.C.VK_FORMAT_R32_SFLOAT, .offset = @offsetOf(ShapeInstance, "rotation") },
    .{ .location = 3, .binding = 1, .format = cvk.C.VK_FORMAT_R32_SFLOAT, .offset = @offsetOf(ShapeInstance, "scale_x") },
    .{ .location = 4, .binding = 1, .format = cvk.C.VK_FORMAT_R32_SFLOAT, .offset = @offsetOf(ShapeInstance, "scale_y") },
    .{ .location = 5, .binding = 1, .format = cvk.C.VK_FORMAT_R32_UINT, .offset = @offsetOf(ShapeInstance, "shape_type") },
    .{ .location = 6, .binding = 1, .format = cvk.C.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(ShapeInstance, "color") },
  };
  const vertex_input_info = cvk.C.VkPipelineVertexInputStateCreateInfo{
    .sType                           = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    .vertexBindingDescriptionCount   = 2,
    .pVertexBindingDescriptions      = &binding_descriptions,
    .vertexAttributeDescriptionCount = 7,
    .pVertexAttributeDescriptions    = &attribute_descriptions,
  };

  const input_assembly = cvk.C.VkPipelineInputAssemblyStateCreateInfo{
    .sType    = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    .topology = cvk.C.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
  };
  const viewport_state = cvk.C.VkPipelineViewportStateCreateInfo{
    .sType         = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    .viewportCount = 1,
    .scissorCount  = 1,
  };
  const rasterizer = cvk.C.VkPipelineRasterizationStateCreateInfo{
    .sType       = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    .polygonMode = cvk.C.VK_POLYGON_MODE_FILL,
    .cullMode    = cvk.C.VK_CULL_MODE_NONE,
    .frontFace   = cvk.C.VK_FRONT_FACE_COUNTER_CLOCKWISE,
    .lineWidth   = 1.0,
  };
  const multisampling = cvk.C.VkPipelineMultisampleStateCreateInfo{
    .sType                = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    .rasterizationSamples = cvk.C.VK_SAMPLE_COUNT_1_BIT,
  };

  const all_components: u32 = @intCast(cvk.C.VK_COLOR_COMPONENT_R_BIT | cvk.C.VK_COLOR_COMPONENT_G_BIT | cvk.C.VK_COLOR_COMPONENT_B_BIT | cvk.C.VK_COLOR_COMPONENT_A_BIT);
  const color_blend_attachments = [2]cvk.C.VkPipelineColorBlendAttachmentState{
    .{
      .blendEnable         = 1,
      .srcColorBlendFactor = cvk.C.VK_BLEND_FACTOR_SRC_ALPHA,
      .dstColorBlendFactor = cvk.C.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      .colorBlendOp        = cvk.C.VK_BLEND_OP_ADD,
      .srcAlphaBlendFactor = cvk.C.VK_BLEND_FACTOR_ONE,
      .dstAlphaBlendFactor = cvk.C.VK_BLEND_FACTOR_ZERO,
      .alphaBlendOp        = cvk.C.VK_BLEND_OP_ADD,
      .colorWriteMask      = all_components,
    },
    .{
      .blendEnable         = 1,
      .srcColorBlendFactor = cvk.C.VK_BLEND_FACTOR_SRC_ALPHA,
      .dstColorBlendFactor = cvk.C.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      .colorBlendOp        = cvk.C.VK_BLEND_OP_ADD,
      .srcAlphaBlendFactor = cvk.C.VK_BLEND_FACTOR_ONE,
      .dstAlphaBlendFactor = cvk.C.VK_BLEND_FACTOR_ZERO,
      .alphaBlendOp        = cvk.C.VK_BLEND_OP_ADD,
      .colorWriteMask      = all_components,
    },
  };
  const color_blending = cvk.C.VkPipelineColorBlendStateCreateInfo{
    .sType           = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    .attachmentCount = 2,
    .pAttachments    = &color_blend_attachments,
  };

  const dynamic_state_cfg = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });

  const gbuffer_format = state.gpu.device.swapchain.cfg.imageFormat;
  const gbuffer_color_formats = [2]cvk.C.VkFormat{ gbuffer_format, gbuffer_format };
  state.gbuffer_pipeline.rendering = .{
    .sType                   = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
    .colorAttachmentCount    = 2,
    .pColorAttachmentFormats = &gbuffer_color_formats,
  };
  const layout_args = cvk.pipeline.Layout.create_args{
    .device_logical = &state.gpu.device.logical,
    .allocator      = @ptrCast(&state.gpu.instance.allocator),
    .sets_ptr       = &state.descriptor_set_layout,
    .sets_len       = 1,
  };
  state.gbuffer_pipeline.layout = @bitCast(cvk.C.cvk_pipeline_layout_create(@ptrCast(&layout_args)));
  state.gbuffer_pipeline.cfg = .{
    .sType               = cvk.C.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    .pNext               = &state.gbuffer_pipeline.rendering,
    .stageCount          = 2,
    .pStages             = &stages_array,
    .pVertexInputState   = &vertex_input_info,
    .pInputAssemblyState = &input_assembly,
    .pViewportState      = &viewport_state,
    .pRasterizationState = &rasterizer,
    .pMultisampleState   = &multisampling,
    .pColorBlendState    = &color_blending,
    .pDynamicState       = &dynamic_state_cfg,
    .layout              = state.gbuffer_pipeline.layout.ct,
    .basePipelineIndex   = -1,
  };
  const gbuffer_result = cvk.C.vkCreateGraphicsPipelines(
    state.gpu.device.logical.ct,
    null,
    1,
    &state.gbuffer_pipeline.cfg,
    state.gpu.instance.allocator.gpu,
    &state.gbuffer_pipeline.ct,
  );
  if (gbuffer_result != cvk.C.VK_SUCCESS) return error.PipelineCreationFailed;

  vert_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
  frag_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
}

fn create_jfa_seed_pipeline(state: *VulkanState) !void {
  const vert_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/fullscreen.vert.spv").*;
  const frag_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/jfa_seed.frag.spv").*;

  const vert_spirv = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&vert_array))), .len = vert_array.len / @sizeOf(u32) };
  const frag_spirv = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&frag_array))), .len = frag_array.len / @sizeOf(u32) };

  var vert_shader = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &vert_spirv, .stage = cvk.Shader.stages(&.{.vertex}), .allocator = @ptrCast(&state.gpu.instance.allocator) });
  var frag_shader = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &frag_spirv, .stage = cvk.Shader.stages(&.{.fragment}), .allocator = @ptrCast(&state.gpu.instance.allocator) });

  const stages_array = [_]cvk.C.VkPipelineShaderStageCreateInfo{ vert_shader.stage, frag_shader.stage };
  const stages = cvk.pipeline.shaderStage.List{ .ptr = @constCast(&stages_array), .len = 2 };

  const vertex_input_info = cvk.C.VkPipelineVertexInputStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
  const input_assembly = cvk.C.VkPipelineInputAssemblyStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = cvk.C.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
  const viewport_state = cvk.C.VkPipelineViewportStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .viewportCount = 1, .scissorCount = 1 };
  const rasterizer = cvk.C.VkPipelineRasterizationStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .polygonMode = cvk.C.VK_POLYGON_MODE_FILL, .cullMode = cvk.C.VK_CULL_MODE_NONE, .frontFace = cvk.C.VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0 };
  const multisampling = cvk.C.VkPipelineMultisampleStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = cvk.C.VK_SAMPLE_COUNT_1_BIT };
  const color_blend_attachment = cvk.C.VkPipelineColorBlendAttachmentState{ .colorWriteMask = @intCast(cvk.C.VK_COLOR_COMPONENT_R_BIT | cvk.C.VK_COLOR_COMPONENT_G_BIT | cvk.C.VK_COLOR_COMPONENT_B_BIT | cvk.C.VK_COLOR_COMPONENT_A_BIT) };
  const color_blending = cvk.C.VkPipelineColorBlendStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &color_blend_attachment };
  const dynamic_state_cfg = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });

  state.jfa_seed_pipeline = cvk.pipeline.Graphics.create(.{
    .device_logical      = &state.gpu.device.logical,
    .allocator           = @ptrCast(&state.gpu.instance.allocator),
    .stages              = &stages,
    .state_vertexInput   = &vertex_input_info,
    .state_inputAssembly = &input_assembly,
    .state_viewport      = &viewport_state,
    .state_rasterization = &rasterizer,
    .state_multisample   = &multisampling,
    .state_colorBlend    = &color_blending,
    .state_dynamic       = &dynamic_state_cfg,
    .rendering           = &state.jfa_rendering,
    .layout              = &.{
      .device_logical = &state.gpu.device.logical,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
      .sets_ptr       = &state.jfa_seed_descriptor_layout,
      .sets_len       = 1,
    },
  });

  vert_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
  frag_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
}

fn create_jfa_step_pipeline(state: *VulkanState) !void {
  const vert_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/fullscreen.vert.spv").*;
  const frag_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/jfa_step.frag.spv").*;

  const vert_spirv = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&vert_array))), .len = vert_array.len / @sizeOf(u32) };
  const frag_spirv = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&frag_array))), .len = frag_array.len / @sizeOf(u32) };

  var vert_shader = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &vert_spirv, .stage = cvk.Shader.stages(&.{.vertex}), .allocator = @ptrCast(&state.gpu.instance.allocator) });
  var frag_shader = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &frag_spirv, .stage = cvk.Shader.stages(&.{.fragment}), .allocator = @ptrCast(&state.gpu.instance.allocator) });

  const stages_array = [_]cvk.C.VkPipelineShaderStageCreateInfo{ vert_shader.stage, frag_shader.stage };
  const stages = cvk.pipeline.shaderStage.List{ .ptr = @constCast(&stages_array), .len = 2 };

  const vertex_input_info = cvk.C.VkPipelineVertexInputStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
  const input_assembly = cvk.C.VkPipelineInputAssemblyStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = cvk.C.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
  const viewport_state = cvk.C.VkPipelineViewportStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .viewportCount = 1, .scissorCount = 1 };
  const rasterizer = cvk.C.VkPipelineRasterizationStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .polygonMode = cvk.C.VK_POLYGON_MODE_FILL, .cullMode = cvk.C.VK_CULL_MODE_NONE, .frontFace = cvk.C.VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0 };
  const multisampling = cvk.C.VkPipelineMultisampleStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = cvk.C.VK_SAMPLE_COUNT_1_BIT };
  const color_blend_attachment = cvk.C.VkPipelineColorBlendAttachmentState{ .colorWriteMask = @intCast(cvk.C.VK_COLOR_COMPONENT_R_BIT | cvk.C.VK_COLOR_COMPONENT_G_BIT | cvk.C.VK_COLOR_COMPONENT_B_BIT | cvk.C.VK_COLOR_COMPONENT_A_BIT) };
  const color_blending = cvk.C.VkPipelineColorBlendStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &color_blend_attachment };
  const dynamic_state_cfg = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });

  const push_constant_range = cvk.C.VkPushConstantRange{
    .stageFlags = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
    .offset     = 0,
    .size       = @sizeOf(JfaPushConstants),
  };

  state.jfa_step_pipeline = cvk.pipeline.Graphics.create(.{
    .device_logical      = &state.gpu.device.logical,
    .allocator           = @ptrCast(&state.gpu.instance.allocator),
    .stages              = &stages,
    .state_vertexInput   = &vertex_input_info,
    .state_inputAssembly = &input_assembly,
    .state_viewport      = &viewport_state,
    .state_rasterization = &rasterizer,
    .state_multisample   = &multisampling,
    .state_colorBlend    = &color_blending,
    .state_dynamic       = &dynamic_state_cfg,
    .rendering           = &state.jfa_rendering,
    .layout              = &.{
      .device_logical    = &state.gpu.device.logical,
      .allocator         = @ptrCast(&state.gpu.instance.allocator),
      .sets_ptr          = &state.jfa_step_descriptor_layout,
      .sets_len          = 1,
      .pushConstants_ptr = &push_constant_range,
      .pushConstants_len = 1,
    },
  });

  vert_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
  frag_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
}

fn create_lighting_pipeline(state: *VulkanState) !void {
  const vert_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/fullscreen.vert.spv").*;
  const frag_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/lighting.frag.spv").*;

  const vert_spirv = cvk.shader.SpirV{
    .ptr = @constCast(@ptrCast(@alignCast(&vert_array))),
    .len = vert_array.len / @sizeOf(u32),
  };
  const frag_spirv = cvk.shader.SpirV{
    .ptr = @constCast(@ptrCast(@alignCast(&frag_array))),
    .len = frag_array.len / @sizeOf(u32),
  };

  var vert_shader = cvk.Shader.create(.{
    .device_logical = &state.gpu.device.logical,
    .code           = &vert_spirv,
    .stage          = cvk.Shader.stages(&.{.vertex}),
    .allocator      = @ptrCast(&state.gpu.instance.allocator),
  });
  var frag_shader = cvk.Shader.create(.{
    .device_logical = &state.gpu.device.logical,
    .code           = &frag_spirv,
    .stage          = cvk.Shader.stages(&.{.fragment}),
    .allocator      = @ptrCast(&state.gpu.instance.allocator),
  });

  const stages_array = [_]cvk.C.VkPipelineShaderStageCreateInfo{ vert_shader.stage, frag_shader.stage };
  const stages = cvk.pipeline.shaderStage.List{
    .ptr = @constCast(&stages_array),
    .len = 2,
  };

  const vertex_input_info = cvk.C.VkPipelineVertexInputStateCreateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
  };
  const input_assembly = cvk.C.VkPipelineInputAssemblyStateCreateInfo{
    .sType    = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    .topology = cvk.C.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
  };
  const viewport_state = cvk.C.VkPipelineViewportStateCreateInfo{
    .sType         = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    .viewportCount = 1,
    .scissorCount  = 1,
  };
  const rasterizer = cvk.C.VkPipelineRasterizationStateCreateInfo{
    .sType       = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    .polygonMode = cvk.C.VK_POLYGON_MODE_FILL,
    .cullMode    = cvk.C.VK_CULL_MODE_NONE,
    .frontFace   = cvk.C.VK_FRONT_FACE_COUNTER_CLOCKWISE,
    .lineWidth   = 1.0,
  };
  const multisampling = cvk.C.VkPipelineMultisampleStateCreateInfo{
    .sType                = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    .rasterizationSamples = cvk.C.VK_SAMPLE_COUNT_1_BIT,
  };
  const color_blend_attachment = cvk.C.VkPipelineColorBlendAttachmentState{
    .colorWriteMask = @intCast(cvk.C.VK_COLOR_COMPONENT_R_BIT | cvk.C.VK_COLOR_COMPONENT_G_BIT | cvk.C.VK_COLOR_COMPONENT_B_BIT | cvk.C.VK_COLOR_COMPONENT_A_BIT),
  };
  const color_blending = cvk.C.VkPipelineColorBlendStateCreateInfo{
    .sType           = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    .attachmentCount = 1,
    .pAttachments    = &color_blend_attachment,
  };

  const dynamic_state_cfg = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });

  state.lighting_pipeline = cvk.pipeline.Graphics.create(.{
    .device_logical      = &state.gpu.device.logical,
    .allocator           = @ptrCast(&state.gpu.instance.allocator),
    .stages              = &stages,
    .state_vertexInput   = &vertex_input_info,
    .state_inputAssembly = &input_assembly,
    .state_viewport      = &viewport_state,
    .state_rasterization = &rasterizer,
    .state_multisample   = &multisampling,
    .state_colorBlend    = &color_blending,
    .state_dynamic       = &dynamic_state_cfg,
    .rendering           = &state.lighting_rendering,
    .layout              = &.{
      .device_logical = &state.gpu.device.logical,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
      .sets_ptr       = &state.lighting_descriptor_layout,
      .sets_len       = 1,
    },
  });

  vert_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
  frag_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
}

fn create_composite_pipeline(state: *VulkanState) !void {
  const vert_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/fullscreen.vert.spv").*;
  const frag_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/composite.frag.spv").*;

  const vert_spirv = cvk.shader.SpirV{
    .ptr = @constCast(@ptrCast(@alignCast(&vert_array))),
    .len = vert_array.len / @sizeOf(u32),
  };
  const frag_spirv = cvk.shader.SpirV{
    .ptr = @constCast(@ptrCast(@alignCast(&frag_array))),
    .len = frag_array.len / @sizeOf(u32),
  };

  var vert_shader = cvk.Shader.create(.{
    .device_logical = &state.gpu.device.logical,
    .code           = &vert_spirv,
    .stage          = cvk.Shader.stages(&.{.vertex}),
    .allocator      = @ptrCast(&state.gpu.instance.allocator),
  });
  var frag_shader = cvk.Shader.create(.{
    .device_logical = &state.gpu.device.logical,
    .code           = &frag_spirv,
    .stage          = cvk.Shader.stages(&.{.fragment}),
    .allocator      = @ptrCast(&state.gpu.instance.allocator),
  });

  const stages_array = [_]cvk.C.VkPipelineShaderStageCreateInfo{ vert_shader.stage, frag_shader.stage };
  const stages = cvk.pipeline.shaderStage.List{
    .ptr = @constCast(&stages_array),
    .len = 2,
  };

  const vertex_input_info = cvk.C.VkPipelineVertexInputStateCreateInfo{
    .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
  };
  const input_assembly = cvk.C.VkPipelineInputAssemblyStateCreateInfo{
    .sType    = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    .topology = cvk.C.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
  };
  const viewport_state = cvk.C.VkPipelineViewportStateCreateInfo{
    .sType         = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    .viewportCount = 1,
    .scissorCount  = 1,
  };
  const rasterizer = cvk.C.VkPipelineRasterizationStateCreateInfo{
    .sType       = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    .polygonMode = cvk.C.VK_POLYGON_MODE_FILL,
    .cullMode    = cvk.C.VK_CULL_MODE_NONE,
    .frontFace   = cvk.C.VK_FRONT_FACE_COUNTER_CLOCKWISE,
    .lineWidth   = 1.0,
  };
  const multisampling = cvk.C.VkPipelineMultisampleStateCreateInfo{
    .sType                = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    .rasterizationSamples = cvk.C.VK_SAMPLE_COUNT_1_BIT,
  };
  const color_blend_attachment = cvk.C.VkPipelineColorBlendAttachmentState{
    .colorWriteMask = @intCast(cvk.C.VK_COLOR_COMPONENT_R_BIT | cvk.C.VK_COLOR_COMPONENT_G_BIT | cvk.C.VK_COLOR_COMPONENT_B_BIT | cvk.C.VK_COLOR_COMPONENT_A_BIT),
  };
  const color_blending = cvk.C.VkPipelineColorBlendStateCreateInfo{
    .sType           = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    .attachmentCount = 1,
    .pAttachments    = &color_blend_attachment,
  };

  const dynamic_state_cfg = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });

  // TODO(dynamic_rendering): Pipeline needs VK_KHR_dynamic_rendering flag + VkPipelineRenderingCreateInfo
  state.composite_pipeline = cvk.pipeline.Graphics.create(.{
    .device_logical      = &state.gpu.device.logical,
    .allocator           = @ptrCast(&state.gpu.instance.allocator),
    .stages              = &stages,
    .state_vertexInput   = &vertex_input_info,
    .state_inputAssembly = &input_assembly,
    .state_viewport      = &viewport_state,
    .state_rasterization = &rasterizer,
    .state_multisample   = &multisampling,
    .state_colorBlend    = &color_blending,
    .state_dynamic       = &dynamic_state_cfg,
    .rendering           = &state.forward_target.ct,
    .layout              = &.{
      .device_logical = &state.gpu.device.logical,
      .allocator      = @ptrCast(&state.gpu.instance.allocator),
      .sets_ptr       = &state.composite_descriptor_layout,
      .sets_len       = 1,
    },
  });

  vert_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
  frag_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
}

fn create_rc_cascade_pipeline(state: *VulkanState) !void {
  const vert_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/fullscreen.vert.spv").*;
  const frag_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/rc_cascade.frag.spv").*;
  const vert_spirv = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&vert_array))), .len = vert_array.len / @sizeOf(u32) };
  const frag_spirv = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&frag_array))), .len = frag_array.len / @sizeOf(u32) };
  var vert_shader = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &vert_spirv, .stage = cvk.Shader.stages(&.{.vertex}), .allocator = @ptrCast(&state.gpu.instance.allocator) });
  var frag_shader = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &frag_spirv, .stage = cvk.Shader.stages(&.{.fragment}), .allocator = @ptrCast(&state.gpu.instance.allocator) });
  const stages_array = [_]cvk.C.VkPipelineShaderStageCreateInfo{ vert_shader.stage, frag_shader.stage };
  const stages = cvk.pipeline.shaderStage.List{ .ptr = @constCast(&stages_array), .len = 2 };
  const vertex_input_info = cvk.C.VkPipelineVertexInputStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
  const input_assembly = cvk.C.VkPipelineInputAssemblyStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = cvk.C.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
  const viewport_state = cvk.C.VkPipelineViewportStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .viewportCount = 1, .scissorCount = 1 };
  const rasterizer = cvk.C.VkPipelineRasterizationStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .polygonMode = cvk.C.VK_POLYGON_MODE_FILL, .cullMode = cvk.C.VK_CULL_MODE_NONE, .frontFace = cvk.C.VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0 };
  const multisampling = cvk.C.VkPipelineMultisampleStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = cvk.C.VK_SAMPLE_COUNT_1_BIT };
  const color_blend_attachment = cvk.C.VkPipelineColorBlendAttachmentState{ .colorWriteMask = @intCast(cvk.C.VK_COLOR_COMPONENT_R_BIT | cvk.C.VK_COLOR_COMPONENT_G_BIT | cvk.C.VK_COLOR_COMPONENT_B_BIT | cvk.C.VK_COLOR_COMPONENT_A_BIT) };
  const color_blending = cvk.C.VkPipelineColorBlendStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &color_blend_attachment };
  const dynamic_state_cfg = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });
  const push_constant_range = cvk.C.VkPushConstantRange{
    .stageFlags = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
    .offset     = 0,
    .size       = @sizeOf(RcCascadePushConstants),
  };
  state.rc_cascade_pipeline = cvk.pipeline.Graphics.create(.{
    .device_logical      = &state.gpu.device.logical,
    .allocator           = @ptrCast(&state.gpu.instance.allocator),
    .stages              = &stages,
    .state_vertexInput   = &vertex_input_info,
    .state_inputAssembly = &input_assembly,
    .state_viewport      = &viewport_state,
    .state_rasterization = &rasterizer,
    .state_multisample   = &multisampling,
    .state_colorBlend    = &color_blending,
    .state_dynamic       = &dynamic_state_cfg,
    .rendering           = &state.rc_rendering,
    .layout              = &.{
      .device_logical    = &state.gpu.device.logical,
      .allocator         = @ptrCast(&state.gpu.instance.allocator),
      .sets_ptr          = &state.rc_cascade_desc_layout,
      .sets_len          = 1,
      .pushConstants_ptr = &push_constant_range,
      .pushConstants_len = 1,
    },
  });
  vert_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
  frag_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
}

fn create_rc_merge_pipeline(state: *VulkanState) !void {
  const vert_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/fullscreen.vert.spv").*;
  const frag_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/rc_merge.frag.spv").*;
  const vert_spirv = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&vert_array))), .len = vert_array.len / @sizeOf(u32) };
  const frag_spirv = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&frag_array))), .len = frag_array.len / @sizeOf(u32) };
  var vert_shader = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &vert_spirv, .stage = cvk.Shader.stages(&.{.vertex}), .allocator = @ptrCast(&state.gpu.instance.allocator) });
  var frag_shader = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &frag_spirv, .stage = cvk.Shader.stages(&.{.fragment}), .allocator = @ptrCast(&state.gpu.instance.allocator) });
  const stages_array = [_]cvk.C.VkPipelineShaderStageCreateInfo{ vert_shader.stage, frag_shader.stage };
  const stages = cvk.pipeline.shaderStage.List{ .ptr = @constCast(&stages_array), .len = 2 };
  const vertex_input_info = cvk.C.VkPipelineVertexInputStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
  const input_assembly = cvk.C.VkPipelineInputAssemblyStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = cvk.C.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
  const viewport_state = cvk.C.VkPipelineViewportStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .viewportCount = 1, .scissorCount = 1 };
  const rasterizer = cvk.C.VkPipelineRasterizationStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .polygonMode = cvk.C.VK_POLYGON_MODE_FILL, .cullMode = cvk.C.VK_CULL_MODE_NONE, .frontFace = cvk.C.VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0 };
  const multisampling = cvk.C.VkPipelineMultisampleStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = cvk.C.VK_SAMPLE_COUNT_1_BIT };
  const color_blend_attachment = cvk.C.VkPipelineColorBlendAttachmentState{ .colorWriteMask = @intCast(cvk.C.VK_COLOR_COMPONENT_R_BIT | cvk.C.VK_COLOR_COMPONENT_G_BIT | cvk.C.VK_COLOR_COMPONENT_B_BIT | cvk.C.VK_COLOR_COMPONENT_A_BIT) };
  const color_blending = cvk.C.VkPipelineColorBlendStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &color_blend_attachment };
  const dynamic_state_cfg = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });
  const push_constant_range = cvk.C.VkPushConstantRange{
    .stageFlags = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
    .offset     = 0,
    .size       = @sizeOf(RcMergePushConstants),
  };
  state.rc_merge_pipeline = cvk.pipeline.Graphics.create(.{
    .device_logical      = &state.gpu.device.logical,
    .allocator           = @ptrCast(&state.gpu.instance.allocator),
    .stages              = &stages,
    .state_vertexInput   = &vertex_input_info,
    .state_inputAssembly = &input_assembly,
    .state_viewport      = &viewport_state,
    .state_rasterization = &rasterizer,
    .state_multisample   = &multisampling,
    .state_colorBlend    = &color_blending,
    .state_dynamic       = &dynamic_state_cfg,
    .rendering           = &state.rc_rendering,
    .layout              = &.{
      .device_logical    = &state.gpu.device.logical,
      .allocator         = @ptrCast(&state.gpu.instance.allocator),
      .sets_ptr          = &state.rc_merge_desc_layout,
      .sets_len          = 1,
      .pushConstants_ptr = &push_constant_range,
      .pushConstants_len = 1,
    },
  });
  vert_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
  frag_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
}

fn create_rc_gather_pipeline(state: *VulkanState) !void {
  const vert_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/fullscreen.vert.spv").*;
  const frag_array align(@alignOf(u32)) = @embedFile("../survivor/shaders/rc_gather.frag.spv").*;
  const vert_spirv             = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&vert_array))), .len = vert_array.len / @sizeOf(u32) };
  const frag_spirv             = cvk.shader.SpirV{ .ptr = @constCast(@ptrCast(@alignCast(&frag_array))), .len = frag_array.len / @sizeOf(u32) };
  var   vert_shader            = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &vert_spirv, .stage = cvk.Shader.stages(&.{.vertex}), .allocator = @ptrCast(&state.gpu.instance.allocator) });
  var   frag_shader            = cvk.Shader.create(.{ .device_logical = &state.gpu.device.logical, .code = &frag_spirv, .stage = cvk.Shader.stages(&.{.fragment}), .allocator = @ptrCast(&state.gpu.instance.allocator) });
  const stages_array           = [_]cvk.C.VkPipelineShaderStageCreateInfo{ vert_shader.stage, frag_shader.stage };
  const stages                 = cvk.pipeline.shaderStage.List{ .ptr = @constCast(&stages_array), .len = 2 };
  const vertex_input_info      = cvk.C.VkPipelineVertexInputStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
  const input_assembly         = cvk.C.VkPipelineInputAssemblyStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = cvk.C.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
  const viewport_state         = cvk.C.VkPipelineViewportStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .viewportCount = 1, .scissorCount = 1 };
  const rasterizer             = cvk.C.VkPipelineRasterizationStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .polygonMode = cvk.C.VK_POLYGON_MODE_FILL, .cullMode = cvk.C.VK_CULL_MODE_NONE, .frontFace = cvk.C.VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0 };
  const multisampling          = cvk.C.VkPipelineMultisampleStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = cvk.C.VK_SAMPLE_COUNT_1_BIT };
  const color_blend_attachment = cvk.C.VkPipelineColorBlendAttachmentState{ .colorWriteMask = @intCast(cvk.C.VK_COLOR_COMPONENT_R_BIT | cvk.C.VK_COLOR_COMPONENT_G_BIT | cvk.C.VK_COLOR_COMPONENT_B_BIT | cvk.C.VK_COLOR_COMPONENT_A_BIT) };
  const color_blending         = cvk.C.VkPipelineColorBlendStateCreateInfo{ .sType = cvk.C.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &color_blend_attachment };
  const dynamic_state_cfg      = cvk.pipeline.state.Dynamic.setup(&.{ .viewport, .scissor });
  const push_constant_range    = cvk.C.VkPushConstantRange{
    .stageFlags = cvk.C.VK_SHADER_STAGE_FRAGMENT_BIT,
    .offset     = 0,
    .size       = @sizeOf(RcGatherPushConstants),
  };
  state.rc_gather_pipeline = cvk.pipeline.Graphics.create(.{
    .device_logical      = &state.gpu.device.logical,
    .allocator           = @ptrCast(&state.gpu.instance.allocator),
    .stages              = &stages,
    .state_vertexInput   = &vertex_input_info,
    .state_inputAssembly = &input_assembly,
    .state_viewport      = &viewport_state,
    .state_rasterization = &rasterizer,
    .state_multisample   = &multisampling,
    .state_colorBlend    = &color_blending,
    .state_dynamic       = &dynamic_state_cfg,
    .rendering           = &state.lighting_rendering,
    .layout              = &.{
      .device_logical    = &state.gpu.device.logical,
      .allocator         = @ptrCast(&state.gpu.instance.allocator),
      .sets_ptr          = &state.rc_gather_desc_layout,
      .sets_len          = 1,
      .pushConstants_ptr = &push_constant_range,
      .pushConstants_len = 1,
    },
  });
  vert_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
  frag_shader.destroy(&state.gpu.device.logical, &state.gpu.instance);
}

fn destroy_vulkan_state(state: *VulkanState) void {
  state.sync.destroy(&state.gpu);

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    state.instance_buffers[frame_index].destroy(&state.gpu);
    state.uniform_buffers[frame_index].destroy(&state.gpu);
  }

  state.vertex.destroy(&state.gpu);
  state.index.destroy(&state.gpu);

  cvk.C.vkDestroyDescriptorPool(state.gpu.device.logical.ct, state.descriptor_pool, null);
  state.pipeline.destroy(&state.gpu.device.logical, &state.gpu.instance);
  cvk.C.vkDestroyDescriptorSetLayout(state.gpu.device.logical.ct, state.descriptor_set_layout, null);

  // --- Deferred lighting cleanup ---
  state.composite_pipeline.destroy(&state.gpu.device.logical, &state.gpu.instance);
  state.rc_gather_pipeline.destroy(&state.gpu.device.logical, &state.gpu.instance);
  state.rc_merge_pipeline.destroy(&state.gpu.device.logical, &state.gpu.instance);
  state.rc_cascade_pipeline.destroy(&state.gpu.device.logical, &state.gpu.instance);
  state.lighting_pipeline.destroy(&state.gpu.device.logical, &state.gpu.instance);
  state.jfa_step_pipeline.destroy(&state.gpu.device.logical, &state.gpu.instance);
  state.jfa_seed_pipeline.destroy(&state.gpu.device.logical, &state.gpu.instance);
  state.gbuffer_pipeline.destroy(&state.gpu.device.logical, &state.gpu.instance);
  cvk.C.vkDestroyDescriptorPool(state.gpu.device.logical.ct, state.composite_descriptor_pool, null);
  cvk.C.vkDestroyDescriptorSetLayout(state.gpu.device.logical.ct, state.composite_descriptor_layout, null);
  cvk.C.vkDestroyDescriptorPool(state.gpu.device.logical.ct, state.rc_gather_desc_pool, null);
  cvk.C.vkDestroyDescriptorSetLayout(state.gpu.device.logical.ct, state.rc_gather_desc_layout, null);
  cvk.C.vkDestroyDescriptorPool(state.gpu.device.logical.ct, state.rc_merge_desc_pool, null);
  cvk.C.vkDestroyDescriptorSetLayout(state.gpu.device.logical.ct, state.rc_merge_desc_layout, null);
  cvk.C.vkDestroyDescriptorPool(state.gpu.device.logical.ct, state.rc_cascade_desc_pool, null);
  cvk.C.vkDestroyDescriptorSetLayout(state.gpu.device.logical.ct, state.rc_cascade_desc_layout, null);
  cvk.C.vkDestroyDescriptorPool(state.gpu.device.logical.ct, state.lighting_descriptor_pool, null);
  cvk.C.vkDestroyDescriptorSetLayout(state.gpu.device.logical.ct, state.lighting_descriptor_layout, null);
  cvk.C.vkDestroyDescriptorPool(state.gpu.device.logical.ct, state.jfa_descriptor_pool, null);
  cvk.C.vkDestroyDescriptorSetLayout(state.gpu.device.logical.ct, state.jfa_step_descriptor_layout, null);
  cvk.C.vkDestroyDescriptorSetLayout(state.gpu.device.logical.ct, state.jfa_seed_descriptor_layout, null);

  for (0..FRAMES_IN_FLIGHT * 2) |mi| {
    state.rc_merge_views[mi].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.rc_merge_memory[mi].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.rc_merge_images[mi].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
  }
  for (0..FRAMES_IN_FLIGHT) |fi| {
    state.rc_compute_views[fi].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.rc_compute_memory[fi].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.rc_compute_images[fi].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
  }

  for (0..FRAMES_IN_FLIGHT * 2) |jfa_index| {
    state.jfa_views[jfa_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.jfa_image_memory[jfa_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.jfa_images[jfa_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
  }

  for (0..FRAMES_IN_FLIGHT) |frame_index| {
    state.lighting_uniform_buffers[frame_index].destroy(&state.gpu);
    state.lighting_views[frame_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.lighting_memory[frame_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.lighting_images[frame_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.emission_views[frame_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.emission_memory[frame_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.emission_images[frame_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.gbuffer_views[frame_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.gbuffer_memory[frame_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
    state.gbuffer_images[frame_index].destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));
  }
  state.gbuffer_sampler.destroy(&state.gpu.device.logical, @ptrCast(&state.gpu.instance.allocator));

  state.forward_target.destroy();
  state.gpu.destroy();
}

const font_data = init_font();

fn init_font() [95][5]u8 {
  @setEvalBranchQuota(20000);
  const raw = [95][7]u8{
    .{ 0,       0,       0,       0,       0,       0, 0 },
    .{ 0,       0,       0b10111, 0,       0,       0, 0 },
    .{ 0,       0b11,    0,       0b11,    0,       0, 0 },
    .{ 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0, 0 },
    .{ 0b00100, 0b01011, 0b11111, 0b01101, 0b00010, 0, 0 },
    .{ 0b10011, 0b01011, 0b00100, 0b11010, 0b11001, 0, 0 },
    .{ 0b01010, 0b10101, 0b10110, 0b01000, 0b10100, 0, 0 },
    .{ 0,       0,       0b11,    0,       0,       0, 0 },
    .{ 0,       0b01110, 0b10001, 0,       0,       0, 0 },
    .{ 0,       0b10001, 0b01110, 0,       0,       0, 0 },
    .{ 0b00100, 0b10101, 0b01110, 0b10101, 0b00100, 0, 0 },
    .{ 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0, 0 },
    .{ 0,       0b10000, 0b01000, 0,       0,       0, 0 },
    .{ 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0, 0 },
    .{ 0,       0b10000, 0,       0,       0,       0, 0 },
    .{ 0b10000, 0b01000, 0b00100, 0b00010, 0b00001, 0, 0 },
    .{ 0b01110, 0b11001, 0b10101, 0b10011, 0b01110, 0, 0 },
    .{ 0,       0b10010, 0b11111, 0b10000, 0,       0, 0 },
    .{ 0b11001, 0b10101, 0b10101, 0b10101, 0b10010, 0, 0 },
    .{ 0b10001, 0b10101, 0b10101, 0b10101, 0b01010, 0, 0 },
    .{ 0b00111, 0b00100, 0b00100, 0b11111, 0b00100, 0, 0 },
    .{ 0b10111, 0b10101, 0b10101, 0b10101, 0b01001, 0, 0 },
    .{ 0b01110, 0b10101, 0b10101, 0b10101, 0b01000, 0, 0 },
    .{ 0b00001, 0b11001, 0b00101, 0b00011, 0b00001, 0, 0 },
    .{ 0b01010, 0b10101, 0b10101, 0b10101, 0b01010, 0, 0 },
    .{ 0b00010, 0b10101, 0b10101, 0b10101, 0b01110, 0, 0 },
    .{ 0,       0b01010, 0,       0,       0,       0, 0 },
    .{ 0,       0b10000, 0b01010, 0,       0,       0, 0 },
    .{ 0b00100, 0b01010, 0b10001, 0,       0,       0, 0 },
    .{ 0b01010, 0b01010, 0b01010, 0b01010, 0b01010, 0, 0 },
    .{ 0b10001, 0b01010, 0b00100, 0,       0,       0, 0 },
    .{ 0b00010, 0b00001, 0b10101, 0b00101, 0b00010, 0, 0 },
    .{ 0b01110, 0b10001, 0b10101, 0b10101, 0b01110, 0, 0 },
    .{ 0b11110, 0b00101, 0b00101, 0b00101, 0b11110, 0, 0 },
    .{ 0b11111, 0b10101, 0b10101, 0b10101, 0b01010, 0, 0 },
    .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0, 0 },
    .{ 0b11111, 0b10001, 0b10001, 0b10001, 0b01110, 0, 0 },
    .{ 0b11111, 0b10101, 0b10101, 0b10101, 0b10001, 0, 0 },
    .{ 0b11111, 0b00101, 0b00101, 0b00101, 0b00001, 0, 0 },
    .{ 0b01110, 0b10001, 0b10101, 0b10101, 0b11101, 0, 0 },
    .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b11111, 0, 0 },
    .{ 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0, 0 },
    .{ 0b01000, 0b10000, 0b10001, 0b01111, 0b00001, 0, 0 },
    .{ 0b11111, 0b00100, 0b00100, 0b01010, 0b10001, 0, 0 },
    .{ 0b11111, 0b10000, 0b10000, 0b10000, 0b10000, 0, 0 },
    .{ 0b11111, 0b00010, 0b00100, 0b00010, 0b11111, 0, 0 },
    .{ 0b11111, 0b00010, 0b00100, 0b01000, 0b11111, 0, 0 },
    .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b01110, 0, 0 },
    .{ 0b11111, 0b00101, 0b00101, 0b00101, 0b00010, 0, 0 },
    .{ 0b01110, 0b10001, 0b10001, 0b01001, 0b10110, 0, 0 },
    .{ 0b11111, 0b00101, 0b00101, 0b01101, 0b10010, 0, 0 },
    .{ 0b10010, 0b10101, 0b10101, 0b10101, 0b01001, 0, 0 },
    .{ 0b00001, 0b00001, 0b11111, 0b00001, 0b00001, 0, 0 },
    .{ 0b01111, 0b10000, 0b10000, 0b10000, 0b01111, 0, 0 },
    .{ 0b00011, 0b01100, 0b10000, 0b01100, 0b00011, 0, 0 },
    .{ 0b01111, 0b10000, 0b01100, 0b10000, 0b01111, 0, 0 },
    .{ 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0, 0 },
    .{ 0b00001, 0b00010, 0b11100, 0b00010, 0b00001, 0, 0 },
    .{ 0b11001, 0b10101, 0b10101, 0b10101, 0b10011, 0, 0 },
    .{ 0b11111, 0b10001, 0,       0,       0,       0, 0 },
    .{ 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0, 0 },
    .{ 0b10001, 0b11111, 0,       0,       0,       0, 0 },
    .{ 0b00010, 0b00001, 0b00010, 0,       0,       0, 0 },
    .{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0, 0 },
    .{ 0b00001, 0b00010, 0,       0,       0,       0, 0 },
    .{ 0b01000, 0b10100, 0b10100, 0b10100, 0b11110, 0, 0 },
    .{ 0b11111, 0b10100, 0b10100, 0b10100, 0b01000, 0, 0 },
    .{ 0b01100, 0b10010, 0b10010, 0b10010, 0,       0, 0 },
    .{ 0b01000, 0b10100, 0b10100, 0b10100, 0b11111, 0, 0 },
    .{ 0b01100, 0b10110, 0b10110, 0b10110, 0b00100, 0, 0 },
    .{ 0b00100, 0b11110, 0b00101, 0b00001, 0,       0, 0 },
    .{ 0b00010, 0b10101, 0b10101, 0b10101, 0b01111, 0, 0 },
    .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b11000, 0, 0 },
    .{ 0,       0b11101, 0,       0,       0,       0, 0 },
    .{ 0b10000, 0b10000, 0b01101, 0,       0,       0, 0 },
    .{ 0b11111, 0b01000, 0b10100, 0,       0,       0, 0 },
    .{ 0,       0b11111, 0b10000, 0,       0,       0, 0 },
    .{ 0b11110, 0b00010, 0b11100, 0b00010, 0b11100, 0, 0 },
    .{ 0b11110, 0b00010, 0b00010, 0b00010, 0b11100, 0, 0 },
    .{ 0b01100, 0b10010, 0b10010, 0b10010, 0b01100, 0, 0 },
    .{ 0b11110, 0b01010, 0b01010, 0b01010, 0b00100, 0, 0 },
    .{ 0b00100, 0b01010, 0b01010, 0b01010, 0b11110, 0, 0 },
    .{ 0b11110, 0b00010, 0b00010, 0b00010, 0,       0, 0 },
    .{ 0b10100, 0b10110, 0b10110, 0b01010, 0,       0, 0 },
    .{ 0b00010, 0b01111, 0b10010, 0b10000, 0,       0, 0 },
    .{ 0b01110, 0b10000, 0b10000, 0b10000, 0b11110, 0, 0 },
    .{ 0b00110, 0b01000, 0b10000, 0b01000, 0b00110, 0, 0 },
    .{ 0b01110, 0b10000, 0b01000, 0b10000, 0b01110, 0, 0 },
    .{ 0b10010, 0b01100, 0b01100, 0b10010, 0,       0, 0 },
    .{ 0b00010, 0b10100, 0b01000, 0b00100, 0b00010, 0, 0 },
    .{ 0b10010, 0b11010, 0b10110, 0b10010, 0,       0, 0 },
    .{ 0b00100, 0b01110, 0b10001, 0,       0,       0, 0 },
    .{ 0,       0b11111, 0,       0,       0,       0, 0 },
    .{ 0b10001, 0b01110, 0b00100, 0,       0,       0, 0 },
    .{ 0b00100, 0b00010, 0b00100, 0b01000, 0b00100, 0, 0 },
  };
  var result: [95][5]u8 = undefined;
  for (0..95) |glyph| {
    for (0..5) |column| {
      result[glyph][column] = raw[glyph][column];
    }
  }
  return result;
}

pub fn glyph_pixel (character_code: u8, column: u3, row: u3) bool {
  if (character_code < 0x20 or character_code > 0x7E) return false;
  const index = character_code - 0x20;
  return (font_data[index][column] & (@as(u8, 1) << row)) != 0;
}

