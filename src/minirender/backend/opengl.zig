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
  indirect_buffer          :gl.Buffer      = .{},
  view_projection_location :gl.Uniform     = .{},

  // Dirty flags
  geometry_dirty     :bool = false,
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
    self.vao.delete();
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

    result.vao = gl.VertexArray.create();
    // Binding 0: per-vertex geometry (divisor 0)
    result.vao.attribute(0, 3, .float, 0, 0);                   // position
    result.vao.attribute(1, 3, .float, 0, 3 * @sizeOf(f32));    // normal
    // Binding 1: per-instance data (divisor 1)
    result.vao.attribute(2, 4, .float, 1, 0);                   // world row 0
    result.vao.attribute(3, 4, .float, 1, 16);                  // world row 1
    result.vao.attribute(4, 4, .float, 1, 32);                  // world row 2
    result.vao.attribute(5, 4, .float, 1, 48);                  // world row 3
    result.vao.attribute(6, 4, .float, 1, 64);                  // color
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
      .base_vertex = base_vertex,
      .first_index = first_index,
      .index_count = @intCast(inds.len),
    });

    R.geometry_dirty = true;
    return result;
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

    gl.state.enable(.depth_test);
    gl.state.enable(.blend);
    gl.state.blend.set(.src_alpha, .one_minus_src_alpha);

    if (R.live_command_count > 0) {
      R.indirect_buffer.bind(.draw_indirect);
      gl.draw.multi_elements_indirect(.triangles, .unsigned_int, R.live_command_count, 0);
    }

    R.vao.unbind();
    R.program.disable();
  }


  //______________________________________
  // @section Buffer Upload
  //____________________________
  fn ensure_buffer (buffer :*gl.Buffer, needed :usize) void {
    if (buffer.id != 0 and buffer.size >= needed) return;
    if (buffer.id != 0) buffer.delete();
    buffer.* = gl.Buffer.create(.{ .storage_dynamic = true }, @max(needed, 1024));
  }
  //__________________
  fn upload_geometry (self :*Type) void {
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
    const all_instances = self.instances.items();
    if (all_instances.len == 0) return;

    // Collect unique shape keys referenced by live instances
    var unique_keys = mstd.seq(minirender.Shape.Id).create_empty(self.A);
    defer unique_keys.destroy();

    for (all_instances) |inst| {
      if (self.shapes.get(inst.shape) == null) continue;
      var already_seen = false;
      for (unique_keys.data()) |existing| {
        if (existing.eq(inst.shape)) { already_seen = true; break; }
      }
      if (!already_seen) unique_keys.add_one(inst.shape) catch return;
    }

    const live_shape_count = unique_keys.len();
    if (live_shape_count == 0) return;

    // Count instances per unique shape
    const counts = self.A.alloc(u32, live_shape_count) catch return;
    defer self.A.free(counts);
    @memset(counts, 0);

    for (all_instances) |inst| {
      for (unique_keys.data(), 0..) |unique_key, key_index| {
        if (unique_key.eq(inst.shape)) { counts[key_index] += 1; break; }
      }
    }

    // Compute base_instance offsets
    const offsets = self.A.alloc(u32, live_shape_count) catch return;
    defer self.A.free(offsets);
    var running_offset :u32 = 0;
    for (0..live_shape_count) |key_index| {
      offsets[key_index] = running_offset;
      running_offset += counts[key_index];
    }

    const total_instances :usize = running_offset;

    // Pack instance data grouped by shape
    const gpu_data = self.A.alloc(minirender.GpuInstanceData, total_instances) catch return;
    defer self.A.free(gpu_data);
    const write_heads = self.A.alloc(u32, live_shape_count) catch return;
    defer self.A.free(write_heads);
    @memcpy(write_heads, offsets);

    for (all_instances) |inst| {
      for (unique_keys.data(), 0..) |unique_key, key_index| {
        if (unique_key.eq(inst.shape)) {
          gpu_data[write_heads[key_index]] = .{
            .world = minirender.mat4_to_f32(&inst.world),
            .color = minirender.vec4_to_f32(&inst.color)
          };
          write_heads[key_index] += 1;
          break;
        }
      }
    }

    // Build indirect commands
    const commands = self.A.alloc(gl.draw.IndirectCommand, live_shape_count) catch return;
    defer self.A.free(commands);

    for (unique_keys.data(), 0..) |unique_key, key_index| {
      const shape_data = self.shapes.get(unique_key) orelse continue;
      commands[key_index] = .{
        .index_count    = shape_data.index_count,
        .instance_count = counts[key_index],
        .first_index    = shape_data.first_index,
        .base_vertex    = shape_data.base_vertex,
        .base_instance  = offsets[key_index],
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

