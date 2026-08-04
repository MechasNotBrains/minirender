//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const render = @This();
pub const Render = @This().Type;
// @deps std
const std = @import("std");
// @deps mstd
const mstd = @import("mstd");
// @deps minirender
const gl = @import("mgl").v4;
const mcam = @import("mcam");
const minirender = struct {
  const Mat4            = @import("../math.zig").Mat4;
  const mat4_to_f32     = @import("../math.zig").mat4_to_f32;
  const vec4_to_f32     = @import("../math.zig").vec4_to_f32;
  const Color           = @import("../math.zig").Color;
  const Vertex          = @import("../geometry.zig").Vertex;
  const GpuInstanceData = @import("../geometry.zig").GpuInstanceData;
  const Shape           = @import("../geometry.zig").Shape;
  const Instance        = @import("../geometry.zig").Instance;
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
  shapes     :minirender.Shape.Box,
  instances  :minirender.Instance.Box,
  vertices   :mstd.seq(minirender.Vertex),
  indices    :mstd.seq(u32),

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

  // Dirty flags
  geometry_dirty     :bool = false,
  /// Whether a shape has been let go of, leaving a gap in the geometry buffers to close.
  geometry_gapped    :bool = false,
  instances_dirty    :bool = false,
  live_command_count :u32  = 0,


  //______________________________________
  // @section Create/Destroy
  //____________________________
  pub fn destroy (self :*Type) void {
    self.shapes.destroy();
    self.instances.destroy();
    self.vertices.destroy();
    self.indices.destroy();
    self.program.delete();
    self.line_program.delete();
    self.vao.delete();
    self.line_vao.delete();
    if (self.line_vbo.id != 0) self.line_vbo.delete();
    if (self.geometry_vbo.id    != 0) self.geometry_vbo.delete();
    if (self.geometry_ebo.id    != 0) self.geometry_ebo.delete();
    if (self.instance_vbo.id    != 0) self.instance_vbo.delete();
    if (self.indirect_buffer.id != 0) self.indirect_buffer.delete();
  }
  //__________________
  pub const create_args = struct {
    debug :bool = false,
  };
  //__________________
  pub fn create (A :std.mem.Allocator, args :create_args) !Type {
    var result = Type{
      .A = A,
      .shapes    = .create_empty(A),
      .instances = .create_empty(A),
      .vertices  = .create_empty(A),
      .indices   = .create_empty(A),
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
  pub fn shape (
      R     : *Type,
      verts : []const minirender.Vertex,
      inds  : []const u32,
    ) !minirender.Shape.Id {
    const base_vertex :i32 = @intCast(R.vertices.len());
    const first_index :u32 = @intCast(R.indices.len());

    try R.vertices.add_many(verts);
    try R.indices.add_many(inds);

    const result = try R.shapes.add(.{
      .base_vertex  = base_vertex,
      .first_index  = first_index,
      .index_count  = @intCast(inds.len),
      .vertex_count = @intCast(verts.len),
    });

    R.geometry_dirty = true;
    return result;
  }
  //__________________
  /// @descr
  ///  Lets go of a shape, along with the geometry it owns.
  ///
  ///  Shapes are laid end to end in one pair of buffers, so letting one go leaves a gap in
  ///  the middle of them. The gap is closed on the next upload, which is also where every
  ///  shape learns where its geometry ended up.
  pub fn shape_remove (R :*Type, id :minirender.Shape.Id) void {
    if (R.shapes.get(id) == null) return;
    R.shapes.rmv(id);
    R.geometry_gapped = true;
    R.geometry_dirty  = true;
  }
  //__________________
  pub fn instance (
      R     : *Type,
      id    : minirender.Shape.Id,
      world : minirender.Mat4,
      color : minirender.Color,
    ) !minirender.Instance.Id {
    if (R.shapes.get(id) == null) return error.InvalidShapeId;

    const key = try R.instances.add(.{
      .shape = id,
      .world = world,
      .color = color,
    });

    R.instances_dirty = true;
    return key;
  }
  //__________________
  /// @descr
  ///  Drops an instance, so whatever it was drawing stops being drawn.
  ///  The instance data is packed afresh on the next sync, so nothing else has to move.
  pub fn instance_remove (R :*Type, id :minirender.Instance.Id) void {
    if (R.instances.get(id) == null) return;
    R.instances.rmv(id);
    R.instances_dirty = true;
  }
  //__________________
  pub fn reassign_instance (
      R     : *Type,
      id    : minirender.Instance.Id,
      S     : minirender.Shape.Id,
      world : minirender.Mat4,
      color : minirender.Color,
    ) void {
    const inst = R.instances.get(id) orelse return;
    inst.shape = S;
    inst.world = world;
    inst.color = color;
    R.instances_dirty = true;
  }
  //__________________
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
    const inst = R.instances.get(id) orelse return;
    inst.world = world;
    inst.color = color;
    const gpu_index = inst.gpu_offset orelse {
      R.instances_dirty = true;
      return;
    };
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
  pub fn sync (
      R      : *Type,
      camera : *const mcam.Camera,
    ) void {
    if (R.geometry_dirty) {
      R.upload_geometry();
      R.geometry_dirty  = false;
      R.instances_dirty = true;
    }

    if (R.instances_dirty) {
      R.upload_instances();
      R.instances_dirty = false;
    }

    R.program.enable();
    R.vao.bind();

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
      R.indirect_buffer.bind();
      gl.draw.multi_elements_indirect(.triangles, .unsigned_int, R.live_command_count, 0);
    }

    gl.state.disable(.polygon_offset_fill);

    R.vao.unbind();
    R.program.disable();

    if (R.line_vertex_count > 0) {
      R.line_program.enable();
      R.line_vao.bind();
      R.line_vp_location.set(view_projection_floats);
      R.line_color_location.set(R.line_color);
      gl.state.line_width.set(2.0);
      gl.state.disable(.depth_test);
      gl.draw.arrays(.lines, 0, @intCast(R.line_vertex_count));
      gl.state.enable(.depth_test);
      R.line_vao.unbind();
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
  /// @descr
  ///  Lays the geometry of every shape still held down end to end again, closing the gaps
  ///  left by the ones let go of, and tells each shape where its own ended up.
  fn pack_geometry (self :*Type) void {
    var packed_vertices = mstd.seq(minirender.Vertex).create_empty(self.A);
    var packed_indices  = mstd.seq(u32).create_empty(self.A);

    const old_vertices = self.vertices.data();
    const old_indices  = self.indices.data();

    for (self.shapes.mitems()) |*held| {
      const vertex_from :usize = @intCast(held.base_vertex);
      const vertex_upto = vertex_from + held.vertex_count;
      const index_upto  = held.first_index + held.index_count;
      if (vertex_upto > old_vertices.len or index_upto > old_indices.len) continue;

      const moved_base  :i32 = @intCast(packed_vertices.len());
      const moved_first :u32 = @intCast(packed_indices.len());
      packed_vertices.add_many(old_vertices[vertex_from..vertex_upto]) catch return;
      packed_indices.add_many(old_indices[held.first_index..index_upto]) catch return;
      held.base_vertex = moved_base;
      held.first_index = moved_first;
    }

    self.vertices.destroy();
    self.indices.destroy();
    self.vertices = packed_vertices;
    self.indices  = packed_indices;
  }
  //__________________
  fn upload_geometry (self :*Type) void {
    if (self.geometry_gapped) {
      self.pack_geometry();
      self.geometry_gapped = false;
    }
    const vertex_data = self.vertices.data();
    const index_data  = self.indices.data();
    if (vertex_data.len == 0) return;

    const vbo_size = vertex_data.len * @sizeOf(minirender.Vertex);
    const ebo_size = index_data.len * @sizeOf(u32);

    ensure_buffer(&self.geometry_vbo, vbo_size);
    self.geometry_vbo.upload(vertex_data, 0);
    self.vao.buffer(0, self.geometry_vbo, VERTEX_STRIDE);

    ensure_buffer(&self.geometry_ebo, ebo_size);
    self.geometry_ebo.upload(index_data, 0);
    self.vao.element_buffer(self.geometry_ebo);
  }
  //__________________
  fn upload_instances (self :*Type) void {
    // Nothing left to draw has to be said, not left unsaid: the commands from last time are
    // still in the buffer, and returning without touching them draws what is gone.
    const all_instances = self.instances.items();
    if (all_instances.len == 0) {
      self.live_command_count = 0;
      return;
    }

    const max_shape_slots = self.shapes.refs.items.len;
    if (max_shape_slots == 0) {
      self.live_command_count = 0;
      return;
    }

    // O(n) pass 1: count instances per shape slot
    const shape_counts = self.A.alloc(u32, max_shape_slots) catch return;
    defer self.A.free(shape_counts);
    @memset(shape_counts, 0);

    for (all_instances) |inst| {
      if (self.shapes.get(inst.shape) == null) continue;
      shape_counts[inst.shape.id] += 1;
    }

    // Collect live shapes and compute offsets
    var live_shape_ids = self.A.alloc(u32, max_shape_slots) catch return;
    defer self.A.free(live_shape_ids);
    var shape_to_offset = self.A.alloc(u32, max_shape_slots) catch return;
    defer self.A.free(shape_to_offset);
    var live_shape_count :u32 = 0;
    var running_offset :u32 = 0;

    for (0..max_shape_slots) |slot| {
      if (shape_counts[slot] == 0) continue;
      live_shape_ids[live_shape_count] = @intCast(slot);
      shape_to_offset[slot] = running_offset;
      running_offset += shape_counts[slot];
      live_shape_count += 1;
    }

    if (live_shape_count == 0) {
      self.live_command_count = 0;
      return;
    }
    const total_instances :usize = running_offset;

    // O(n) pass 2: pack instance data grouped by shape
    const gpu_data = self.A.alloc(minirender.GpuInstanceData, total_instances) catch return;
    defer self.A.free(gpu_data);
    const write_heads = self.A.alloc(u32, max_shape_slots) catch return;
    defer self.A.free(write_heads);
    @memcpy(write_heads[0..max_shape_slots], shape_to_offset[0..max_shape_slots]);

    for (self.instances.mitems()) |*inst| {
      if (self.shapes.get(inst.shape) == null) continue;
      const slot = inst.shape.id;
      const gpu_index = write_heads[slot];
      gpu_data[gpu_index] = .{
        .world = minirender.mat4_to_f32(&inst.world),
        .color = minirender.vec4_to_f32(&inst.color),
      };
      inst.gpu_offset = gpu_index;
      write_heads[slot] += 1;
    }

    // Build indirect commands
    const commands = self.A.alloc(gl.draw.IndirectCommand, live_shape_count) catch return;
    defer self.A.free(commands);

    for (live_shape_ids[0..live_shape_count], 0..) |slot, command_index| {
      const shape_key = minirender.Shape.Id{ .id = slot, .version = self.shapes.refs.items[slot].version };
      const shape_data = self.shapes.get(shape_key) orelse continue;
      commands[command_index] = .{
        .index_count    = shape_data.index_count,
        .instance_count = shape_counts[slot],
        .first_index    = shape_data.first_index,
        .base_vertex    = shape_data.base_vertex,
        .base_instance  = shape_to_offset[slot],
      };
    }

    // Upload
    const instance_size = total_instances * @sizeOf(minirender.GpuInstanceData);
    ensure_buffer(&self.instance_vbo, instance_size);
    self.instance_vbo.upload(gpu_data, 0);
    self.vao.buffer(1, self.instance_vbo, INSTANCE_STRIDE);

    const indirect_size = live_shape_count * @sizeOf(gl.draw.IndirectCommand);
    ensure_buffer(&self.indirect_buffer, indirect_size);
    self.indirect_buffer.upload(commands, 0);

    self.live_command_count = @intCast(live_shape_count);
  }
};

