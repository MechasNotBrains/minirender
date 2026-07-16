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
const minirender = struct {
  const math           = @import("../math.zig");
  const Mat4           = math.Mat4;
  const mat4_to_f32    = math.mat4_to_f32;
  const shaders        = @import("./opengl/shaders.zig");
  const vertex         = @import("../vertex.zig");
  const Vertex         = vertex.Vertex;
  const GpuInstanceData = vertex.GpuInstanceData;
  const shapes         = @import("../shape.zig");
  const Shape          = shapes.Shape;
  const Instance       = shapes.Instance;
  const ShapeBox       = shapes.ShapeBox;
  const InstanceBox    = shapes.InstanceBox;
  const ShapeKey       = shapes.ShapeKey;
  const InstanceKey    = shapes.InstanceKey;
};

const VERTEX_STRIDE   :u32 = @sizeOf(minirender.Vertex);
const INSTANCE_STRIDE :u32 = @sizeOf(minirender.GpuInstanceData);


//______________________________________
// @section Renderer
//____________________________

pub const Type = struct {
  allocator :std.mem.Allocator,

  // CPU data
  shapes     :minirender.ShapeBox,
  instances  :minirender.InstanceBox,
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
  geometry_dirty     :bool  = false,
  instances_dirty    :bool  = false,
  live_command_count :u32   = 0,


  //______________________________________
  // @section Create/Destroy
  //____________________________

  pub fn create (allocator :std.mem.Allocator) !Type {
    var result = Type{
      .allocator = allocator,
      .shapes    = minirender.ShapeBox.create_empty(allocator),
      .instances = minirender.InstanceBox.create_empty(allocator),
      .vertices  = mstd.seq(minirender.Vertex).create_empty(allocator),
      .indices   = mstd.seq(u32).create_empty(allocator),
    };

    result.program = try gl.Shader.create(
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

  pub fn destroy (self :*Type) void {
    self.shapes.destroy();
    self.instances.destroy();
    self.vertices.destroy();
    self.indices.destroy();

    self.program.delete();
    self.vao.delete();
    if (self.geometry_vbo.id != 0) self.geometry_vbo.delete();
    if (self.geometry_ebo.id != 0) self.geometry_ebo.delete();
    if (self.instance_vbo.id != 0) self.instance_vbo.delete();
    if (self.indirect_buffer.id != 0) self.indirect_buffer.delete();
  }


  //______________________________________
  // @section Shape/Instance Registration
  //____________________________

  pub fn shape (self :*Type, vertex_data :[]const minirender.Vertex, index_data :[]const u32) !minirender.ShapeKey {
    const base_vertex :i32 = @intCast(self.vertices.len());
    const first_index :u32 = @intCast(self.indices.len());

    try self.vertices.add_many(vertex_data);
    try self.indices.add_many(index_data);

    const key = try self.shapes.add(.{
      .base_vertex = base_vertex,
      .first_index = first_index,
      .index_count = @intCast(index_data.len),
    });

    self.geometry_dirty = true;
    return key;
  }

  pub fn instance (self :*Type, shape_key :minirender.ShapeKey, world :[16]f32, color :[4]f32) !minirender.InstanceKey {
    if (self.shapes.get(shape_key) == null) return error.InvalidShapeKey;

    const key = try self.instances.add(.{
      .shape = shape_key,
      .world = world,
      .color = color,
    });

    self.instances_dirty = true;
    return key;
  }


  //______________________________________
  // @section Sync
  //____________________________

  pub fn sync (self :*Type, view_projection :minirender.Mat4) void {
    if (self.geometry_dirty) {
      self.upload_geometry();
      self.geometry_dirty = false;
      self.instances_dirty = true;
    }

    if (self.instances_dirty) {
      self.upload_instances();
      self.instances_dirty = false;
    }

    self.program.enable();
    self.vao.bind();

    const view_projection_floats = minirender.mat4_to_f32(&view_projection);
    self.view_projection_location.set(view_projection_floats);

    gl.state.enable(.depth_test);
    gl.state.enable(.blend);
    gl.state.blend.set(.src_alpha, .one_minus_src_alpha);

    if (self.indirect_buffer.id != 0 and self.live_command_count > 0) {
      self.indirect_buffer.bind(.draw_indirect);
      gl.draw.multi_elements_indirect(.triangles, .unsigned_int, self.live_command_count, 0);
    }

    self.vao.unbind();
    self.program.disable();
  }


  //______________________________________
  // @section Buffer Upload
  //____________________________

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

  fn upload_instances (self :*Type) void {
    const all_instances = self.instances.items();
    if (all_instances.len == 0) return;

    // Collect unique shape keys referenced by live instances
    var unique_keys = mstd.seq(minirender.ShapeKey).create_empty(self.allocator);
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
    const counts = self.allocator.alloc(u32, live_shape_count) catch return;
    defer self.allocator.free(counts);
    @memset(counts, 0);

    for (all_instances) |inst| {
      for (unique_keys.data(), 0..) |unique_key, key_index| {
        if (unique_key.eq(inst.shape)) { counts[key_index] += 1; break; }
      }
    }

    // Compute base_instance offsets
    const offsets = self.allocator.alloc(u32, live_shape_count) catch return;
    defer self.allocator.free(offsets);
    var running_offset :u32 = 0;
    for (0..live_shape_count) |key_index| {
      offsets[key_index] = running_offset;
      running_offset += counts[key_index];
    }

    const total_instances :usize = running_offset;

    // Pack instance data grouped by shape
    const gpu_data = self.allocator.alloc(minirender.GpuInstanceData, total_instances) catch return;
    defer self.allocator.free(gpu_data);
    const write_heads = self.allocator.alloc(u32, live_shape_count) catch return;
    defer self.allocator.free(write_heads);
    @memcpy(write_heads, offsets);

    for (all_instances) |inst| {
      for (unique_keys.data(), 0..) |unique_key, key_index| {
        if (unique_key.eq(inst.shape)) {
          gpu_data[write_heads[key_index]] = .{ .world = inst.world, .color = inst.color };
          write_heads[key_index] += 1;
          break;
        }
      }
    }

    // Build indirect commands
    const commands = self.allocator.alloc(gl.draw.IndirectCommand, live_shape_count) catch return;
    defer self.allocator.free(commands);

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

  fn ensure_buffer (buffer :*gl.Buffer, needed :usize) void {
    if (buffer.id != 0 and buffer.size >= needed) return;
    if (buffer.id != 0) buffer.delete();
    buffer.* = gl.Buffer.create(.{ .storage_dynamic = true }, @max(needed, 1024));
  }


  //______________________________________
  // @section Clear
  //____________________________

  pub fn clear (_:*const Type) void {
    gl.fb.clear.color.set(.{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 });
    gl.fb.clear.screen(.{ .color = true, .depth = true });
  }
};
