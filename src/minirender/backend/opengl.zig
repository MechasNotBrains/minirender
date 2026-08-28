//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const render = @This();
pub const Render = @This().Type;
// @deps std
const std = @import("std");
// @deps minirender
const gl         = @import("mgl").v4;
const msys       = @import("msys");
const mcam       = @import("mcam");
const minirender = struct {
  const Mat4            = @import("../math.zig").Mat4;
  const mat4_to_f32     = @import("../math.zig").mat4_to_f32;
  const vec4_to_f32     = @import("../math.zig").vec4_to_f32;
  const Color           = @import("../math.zig").Color;
  const Vertex          = @import("../geometry.zig").Vertex;
  const GpuInstanceData = @import("../geometry.zig").GpuInstanceData;
  const Shape           = @import("../geometry.zig").Shape;
  const Instance        = @import("../geometry.zig").Instance;
  const Store           = @import("../store.zig").Store;
  const Render          = @import("../core.gl.zig").Render;
  const Command         = @import("../store.zig").Command;
  const shaders         = @import("./opengl/shaders.zig");
};

const VERTEX_STRIDE   :u32 = @sizeOf(minirender.Vertex);
const INSTANCE_STRIDE :u32 = @sizeOf(minirender.GpuInstanceData);


//______________________________________
// @section Renderer
//____________________________

pub const Type = struct {
  A  :std.mem.Allocator,

  // Config
  color_clear :gl.Color= .{ .r= 0.1, .g= 0.1, .b= 0.15 },

  // CPU data
  store :minirender.Store,

  // GPU resources
  program                  :gl.Shader      = undefined,
  vao                      :gl.VertexArray = .{},
  geometry_vbo             :gl.Buffer      = .{},
  geometry_ebo             :gl.Buffer      = .{},
  instance_vbo             :gl.Buffer      = .{},
  indirect_buffer          :gl.Buffer      = .{ .target = .draw_indirect },
  view_projection_location :gl.Uniform     = .{},
  atlas_location           :gl.Uniform     = .{},
  textured_location        :gl.Uniform     = .{},

  // Line rendering
  line_program          :gl.Shader      = undefined,
  line_vao              :gl.VertexArray  = .{},
  line_vbo              :gl.Buffer       = .{},
  line_vp_location      :gl.Uniform      = .{},
  line_color_location   :gl.Uniform      = .{},
  line_vertex_count     :u32             = 0,
  line_color            :[4]f32          = .{1, 0.8, 0, 1},

  // Texture
  textured           :bool = false,

  // Draw state
  live_command_count   :u32 = 0,
  opaque_command_count :u32 = 0,


  //______________________________________
  // @section Create/Destroy
  //____________________________
  pub fn destroy (R :*Type) void {
    R.store.destroy();
    R.program.delete();
    R.line_program.delete();
    R.vao.delete();
    R.line_vao.delete();
    if (R.line_vbo.id != 0) R.line_vbo.delete();
    if (R.geometry_vbo.id    != 0) R.geometry_vbo.delete();
    if (R.geometry_ebo.id    != 0) R.geometry_ebo.delete();
    if (R.instance_vbo.id    != 0) R.instance_vbo.delete();
    if (R.indirect_buffer.id != 0) R.indirect_buffer.delete();
  }
  //__________________
  pub const create_args = struct {
    debug :bool = false,
  };
  //__________________
  pub fn create (A :std.mem.Allocator, args :create_args) !Type {
    var result = Type{
      .A     = A,
      .store = .create(A),
    };

    if (args.debug) gl.debug.enable(.{});

    result.program = try .create(
      try gl.Shader.vertex(minirender.shaders.vert_src),
      try gl.Shader.fragment(minirender.shaders.frag_src),
    );
    result.view_projection_location = result.program.uniform("uViewProjection");
    result.atlas_location           = result.program.uniform("uAtlas");
    result.textured_location        = result.program.uniform("uTextured");

    result.line_program = try .create(
      try gl.Shader.vertex(minirender.shaders.line_vert_src),
      try gl.Shader.fragment(minirender.shaders.line_frag_src),
    );
    result.line_vp_location    = result.line_program.uniform("uViewProjection");
    result.line_color_location = result.line_program.uniform("uLineColor");
    result.line_vao = gl.VertexArray.create();
    result.line_vao.attribute(0, 3, .float, 0, 0);

    result.vao = gl.VertexArray.create();
    // Binding 0: per-vertex geometry (divisor 0)
    result.vao.attribute(0, 3, .float, 0, 0);                    // position
    result.vao.attribute(1, 3, .float, 0, 3  * @sizeOf(f32));    // normal
    result.vao.attribute(2, 2, .float, 0, 6  * @sizeOf(f32));    // uv
    result.vao.attribute(3, 2, .float, 0, 8  * @sizeOf(f32));    // atlas_offset
    result.vao.attribute(4, 2, .float, 0, 10 * @sizeOf(f32));    // atlas_scale
    result.vao.attribute(10, 4, .float, 0, 12 * @sizeOf(f32));   // color
    // Binding 1: per-instance data (divisor 1)
    result.vao.attribute(5, 4, .float, 1, 0);                    // world row 0
    result.vao.attribute(6, 4, .float, 1, 16);                   // world row 1
    result.vao.attribute(7, 4, .float, 1, 32);                   // world row 2
    result.vao.attribute(8, 4, .float, 1, 48);                   // world row 3
    result.vao.attribute(9, 4, .float, 1, 64);                   // color
    result.vao.divisor(1, 1);

    return result;
  }

  //______________________________________
  // @section Draw
  //____________________________
  pub fn clear (R :*const Type) void {
    gl.fb.clear.color.set(R.color_clear);
    gl.fb.clear.screen(.{ .color = true, .depth = true });
  }


  //______________________________________
  // @section Geometry
  //____________________________
  pub fn set_selection_lines (R :*Type, positions :[]const [3]f32, color :[4]f32) void {
    const byte_size = positions.len * @sizeOf([3]f32);
    ensure_buffer(&R.line_vbo, byte_size);
    R.line_vbo.upload(positions, 0);
    R.line_vao.buffer(0, R.line_vbo, @sizeOf([3]f32));
    R.line_vertex_count = @intCast(positions.len);
    R.line_color = color;
  }
  //__________________
  pub fn clear_selection_lines (R :*Type) void {
    R.line_vertex_count = 0;
  }
  //__________________
  pub fn update_instance (
      R     : *Type,
      id    : minirender.Instance.Id,
      world : minirender.Mat4,
      color : minirender.Color,
    ) void {
    const gpu_index = R.store.instance_update(id, world, color) orelse return;
    const gpu_entry = [1]minirender.GpuInstanceData{.{
      .world = minirender.mat4_to_f32(&world),
      .color = minirender.vec4_to_f32(&color),
    }};
    const byte_offset = gpu_index * @sizeOf(minirender.GpuInstanceData);
    R.instance_vbo.upload(&gpu_entry, byte_offset);
  }


  //______________________________________
  // @section Sync
  //____________________________
  pub fn draw (
      R      : *Type,
      camera : *const mcam.Camera,
    ) void {
    if (R.store.geometry_dirty) {
      R.upload_geometry();
      R.store.geometry_dirty  = false;
      R.store.instances_dirty = true;
    }

    if (R.store.instances_dirty) {
      R.upload_instances();
      R.store.instances_dirty = false;
    }

    R.program.enable();
    R.vao.enable();

    const view       = camera.view();
    const projection = minirender.Mat4.perspective_Dno(camera.fov, camera.aspect, camera.near, camera.far);
    const vp         = view.mul(projection);
    const view_projection_floats = minirender.mat4_to_f32(&vp);
    R.view_projection_location.set(view_projection_floats);

    R.atlas_location.set(@as(i32, 0));
    R.textured_location.set(R.textured);

    gl.state.enable(.depth_test);
    gl.state.enable(.blend);
    gl.state.blend.set(.src_alpha, .one_minus_src_alpha);
    gl.state.enable(.polygon_offset_fill);
    gl.state.polygon_offset.set(1.0, 1.0);

    if (R.live_command_count > 0) {
      R.indirect_buffer.enable();
      if (R.opaque_command_count > 0) {
        gl.draw.multi_elements_indirect(.triangles, .unsigned_int, R.opaque_command_count, 0, 0);
      }
      const alpha_command_count = R.live_command_count - R.opaque_command_count;
      if (alpha_command_count > 0) {
        gl.state.depth.set(false);
        gl.draw.multi_elements_indirect(.triangles, .unsigned_int, alpha_command_count,
          R.opaque_command_count * @sizeOf(minirender.Command), 0);
        gl.state.depth.set(true);
      }
    }

    gl.state.disable(.polygon_offset_fill);

    R.vao.disable();
    R.program.disable();

    if (R.line_vertex_count > 0) {
      R.line_program.enable();
      R.line_vao.enable();
      R.line_vp_location.set(view_projection_floats);
      R.line_color_location.set(R.line_color);
      gl.state.line_width.set(2.0);
      gl.state.disable(.depth_test);
      gl.draw.arrays(.lines, 0, @intCast(R.line_vertex_count));
      gl.state.enable(.depth_test);
      R.line_vao.disable();
      R.line_program.disable();
    }
  }


  //______________________________________
  // @section Buffer Upload
  //____________________________
  fn ensure_buffer (buffer :*gl.Buffer, needed :usize) void {
    if (buffer.id != 0 and buffer.size >= needed) return;
    if (buffer.id != 0) buffer.delete();
    buffer.* = gl.Buffer.create(@max(needed, 1024), .{ .target = buffer.target });
  }
  //__________________
  fn upload_geometry (R :*Type) void {
    if (R.store.geometry_gapped) {
      R.store.pack_geometry();
      R.store.geometry_gapped = false;
    }
    const vertex_data = R.store.vertices.data();
    const index_data  = R.store.indices.data();
    if (vertex_data.len == 0) return;

    const vbo_size = vertex_data.len * @sizeOf(minirender.Vertex);
    const ebo_size = index_data.len * @sizeOf(u32);

    ensure_buffer(&R.geometry_vbo, vbo_size);
    R.geometry_vbo.upload(vertex_data, 0);
    R.vao.buffer(0, R.geometry_vbo, VERTEX_STRIDE);

    ensure_buffer(&R.geometry_ebo, ebo_size);
    R.geometry_ebo.upload(index_data, 0);
    R.vao.element_buffer(R.geometry_ebo);
  }
  //__________________
  fn upload_instances (R :*Type) void {
    // Nothing left to draw has to be said, not left unsaid: the commands from last time are
    // still in the buffer, and returning without touching them draws what is gone.
    const draws = R.store.build() orelse {
      R.live_command_count = 0;
      return;
    };
    defer draws.destroy();

    const instance_size = draws.instances.len * @sizeOf(minirender.GpuInstanceData);
    ensure_buffer(&R.instance_vbo, instance_size);
    R.instance_vbo.upload(draws.instances, 0);
    R.vao.buffer(1, R.instance_vbo, INSTANCE_STRIDE);

    const indirect_size = draws.commands.len * @sizeOf(minirender.Command);
    ensure_buffer(&R.indirect_buffer, indirect_size);
    R.indirect_buffer.upload(draws.commands, 0);

    R.opaque_command_count = draws.opaque_count;
    R.live_command_count   = @intCast(draws.commands.len);
  }
};


//______________________________________
// @section Events
//____________________________
pub fn resize (R :*minirender.Render, width :u32, height :u32) void {
  gl.viewport.set(0, 0, @intCast(width), @intCast(height));
  if (width == 0 or height == 0) return;
  R.camera.aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
}

