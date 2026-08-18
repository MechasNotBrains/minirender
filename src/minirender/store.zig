//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
//! @fileoverview
//! Holds the shapes and instances given to a renderer, and lays them out for drawing.
//! Nothing in here talks to a graphics API, so every backend shares it.
//_________________________________________________________________________|
pub const store = @This();
pub const Store = @This().Type;
// @deps std
const std = @import("std");
// @deps mstd
const mstd = @import("mstd");
// @deps minirender
const minirender = struct {
  const Mat4            = @import("./math.zig").Mat4;
  const mat4_to_f32     = @import("./math.zig").mat4_to_f32;
  const vec4_to_f32     = @import("./math.zig").vec4_to_f32;
  const Color           = @import("./math.zig").Color;
  const Vertex          = @import("./geometry.zig").Vertex;
  const GpuInstanceData = @import("./geometry.zig").GpuInstanceData;
  const Shape           = @import("./geometry.zig").Shape;
  const Instance        = @import("./geometry.zig").Instance;
};


//______________________________________
// @section Draw Commands
//____________________________
/// @descr One draw of every instance that shares a shape.
/// @note Field for field the same as both `gl.draw.IndirectCommand` and `VkDrawIndexedIndirectCommand`.
pub const Command = extern struct {
  index_count    :u32,
  instance_count :u32,
  first_index    :u32,
  base_vertex    :i32,
  base_instance  :u32,
};
//__________________
/// @descr Everything a backend needs to draw one frame, laid out ready to upload.
pub const Draws = struct {
  A            :std.mem.Allocator,
  instances    :[]minirender.GpuInstanceData,
  commands     :[]Command,
  /// How many of the commands draw shapes without see-through faces. They come first.
  opaque_count :u32,
  pub fn destroy (D :*const Draws) void {
    D.A.free(D.instances);
    D.A.free(D.commands);
  }
};


//______________________________________
// @section Store
//____________________________
pub const Type = struct {
  A         :std.mem.Allocator,
  shapes    :minirender.Shape.Box,
  instances :minirender.Instance.Box,
  vertices  :mstd.seq(minirender.Vertex),
  indices   :mstd.seq(u32),

  /// Whether the geometry buffers have to be uploaded again.
  geometry_dirty  :bool = false,
  /// Whether a shape has been let go of, leaving a gap in the geometry buffers to close.
  geometry_gapped :bool = false,
  /// Whether the instance data has to be laid out and uploaded again.
  instances_dirty :bool = false,


  //______________________________________
  // @section Create/Destroy
  //____________________________
  pub fn create (A :std.mem.Allocator) Type {
    return Type{
      .A         = A,
      .shapes    = .create_empty(A),
      .instances = .create_empty(A),
      .vertices  = .create_empty(A),
      .indices   = .create_empty(A),
    };
  }
  //__________________
  pub fn destroy (S :*Type) void {
    S.shapes.destroy();
    S.instances.destroy();
    S.vertices.destroy();
    S.indices.destroy();
  }


  //______________________________________
  // @section Shapes
  //____________________________
  pub fn shape_add (
      S     : *Type,
      verts : []const minirender.Vertex,
      inds  : []const u32,
      alpha : bool,
    ) !minirender.Shape.Id {
    const base_vertex :i32 = @intCast(S.vertices.len());
    const first_index :u32 = @intCast(S.indices.len());

    try S.vertices.add_many(verts);
    try S.indices.add_many(inds);

    const result = try S.shapes.add(.{
      .base_vertex  = base_vertex,
      .first_index  = first_index,
      .index_count  = @intCast(inds.len),
      .vertex_count = @intCast(verts.len),
      .alpha        = alpha,
    });

    S.geometry_dirty = true;
    return result;
  }
  //__________________
  /// @descr
  ///  Lets go of a shape, along with the geometry it owns.
  ///
  ///  Shapes are laid end to end in one pair of buffers, so letting one go leaves a gap in
  ///  the middle of them. The gap is closed on the next upload, which is also where every
  ///  shape learns where its geometry ended up.
  pub fn shape_remove (S :*Type, id :minirender.Shape.Id) void {
    if (S.shapes.get(id) == null) return;
    S.shapes.rmv(id);
    S.geometry_gapped = true;
    S.geometry_dirty  = true;
  }


  //______________________________________
  // @section Instances
  //____________________________
  pub fn instance_add (
      S     : *Type,
      id    : minirender.Shape.Id,
      world : minirender.Mat4,
      color : minirender.Color,
    ) !minirender.Instance.Id {
    if (S.shapes.get(id) == null) return error.InvalidShapeId;

    const key = try S.instances.add(.{
      .shape = id,
      .world = world,
      .color = color,
    });

    S.instances_dirty = true;
    return key;
  }
  //__________________
  /// @descr
  ///  Drops an instance, so whatever it was drawing stops being drawn.
  ///  The instance data is packed afresh on the next sync, so nothing else has to move.
  pub fn instance_remove (S :*Type, id :minirender.Instance.Id) void {
    if (S.instances.get(id) == null) return;
    S.instances.rmv(id);
    S.instances_dirty = true;
  }
  //__________________
  pub fn instance_reassign (
      S     : *Type,
      id    : minirender.Instance.Id,
      shape : minirender.Shape.Id,
      world : minirender.Mat4,
      color : minirender.Color,
    ) void {
    const inst = S.instances.get(id) orelse return;
    inst.shape = shape;
    inst.world = world;
    inst.color = color;
    S.instances_dirty = true;
  }
  //__________________
  /// @descr
  ///  Moves an instance to a new transform and color.
  /// @returns
  ///  Where the instance already sits in the data laid out last, when it has a place of its own.
  ///  A backend can write that one entry instead of laying every instance out again.
  ///  Returns null when the instance has no place yet, and marks the instances to be laid out afresh.
  pub fn instance_update (
      S     : *Type,
      id    : minirender.Instance.Id,
      world : minirender.Mat4,
      color : minirender.Color,
    ) ?u32 {
    const inst = S.instances.get(id) orelse return null;
    inst.world = world;
    inst.color = color;
    return inst.gpu_offset orelse {
      S.instances_dirty = true;
      return null;
    };
  }


  //______________________________________
  // @section Layout
  //____________________________
  /// @descr
  ///  Lays the geometry of every shape still held down end to end again, closing the gaps
  ///  left by the ones let go of, and tells each shape where its own ended up.
  pub fn pack_geometry (S :*Type) void {
    var packed_vertices = mstd.seq(minirender.Vertex).create_empty(S.A);
    var packed_indices  = mstd.seq(u32).create_empty(S.A);

    const old_vertices = S.vertices.data();
    const old_indices  = S.indices.data();

    for (S.shapes.mitems()) |*held| {
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

    S.vertices.destroy();
    S.indices.destroy();
    S.vertices = packed_vertices;
    S.indices  = packed_indices;
  }
  //__________________
  /// @descr
  ///  Groups every instance by the shape it draws, and writes one command per shape.
  ///  Shapes without see-through faces come first, so a backend can draw them before the rest.
  ///  Returns null when there is nothing left to draw.
  /// @important The result owns its memory. Call `destroy` on it once it has been uploaded.
  pub fn build (S :*Type) ?Draws {
    const all_instances = S.instances.items();
    if (all_instances.len == 0) return null;

    const max_shape_slots = S.shapes.refs.items.len;
    if (max_shape_slots == 0) return null;

    // O(n) pass 1: count instances per shape slot
    const shape_counts = S.A.alloc(u32, max_shape_slots) catch return null;
    defer S.A.free(shape_counts);
    @memset(shape_counts, 0);

    for (all_instances) |inst| {
      if (S.shapes.get(inst.shape) == null) continue;
      shape_counts[inst.shape.id] += 1;
    }

    // Collect live shapes and compute offsets
    var live_shape_ids = S.A.alloc(minirender.Shape.Id, max_shape_slots) catch return null;
    defer S.A.free(live_shape_ids);
    var shape_to_offset = S.A.alloc(u32, max_shape_slots) catch return null;
    defer S.A.free(shape_to_offset);
    var live_shape_count :u32 = 0;
    var running_offset :u32 = 0;
    var opaque_count :u32 = 0;

    for ([2]bool{ false, true }) |alpha_pass| {
      var shapes = S.shapes.pairs();
      while (shapes.next()) |entry| {
        const slot = entry.key.id;
        if (shape_counts[slot] == 0) continue;
        if (entry.value.alpha != alpha_pass) continue;
        live_shape_ids[live_shape_count] = entry.key;
        shape_to_offset[slot] = running_offset;
        running_offset += shape_counts[slot];
        live_shape_count += 1;
      }
      if (!alpha_pass) opaque_count = live_shape_count;
    }

    if (live_shape_count == 0) return null;
    const total_instances :usize = running_offset;

    // O(n) pass 2: pack instance data grouped by shape
    const gpu_data = S.A.alloc(minirender.GpuInstanceData, total_instances) catch return null;
    const write_heads = S.A.alloc(u32, max_shape_slots) catch {
      S.A.free(gpu_data);
      return null;
    };
    defer S.A.free(write_heads);
    @memcpy(write_heads[0..max_shape_slots], shape_to_offset[0..max_shape_slots]);

    for (S.instances.mitems()) |*inst| {
      if (S.shapes.get(inst.shape) == null) continue;
      const slot = inst.shape.id;
      const gpu_index = write_heads[slot];
      gpu_data[gpu_index] = .{
        .world = minirender.mat4_to_f32(&inst.world),
        .color = minirender.vec4_to_f32(&inst.color),
      };
      inst.gpu_offset = gpu_index;
      write_heads[slot] += 1;
    }

    // Build one command per shape
    const commands = S.A.alloc(Command, live_shape_count) catch {
      S.A.free(gpu_data);
      return null;
    };

    for (live_shape_ids[0..live_shape_count], 0..) |shape_key, command_index| {
      const slot = shape_key.id;
      const shape_data = S.shapes.get(shape_key) orelse continue;
      commands[command_index] = .{
        .index_count    = shape_data.index_count,
        .instance_count = shape_counts[slot],
        .first_index    = shape_data.first_index,
        .base_vertex    = shape_data.base_vertex,
        .base_instance  = shape_to_offset[slot],
      };
    }

    return Draws{
      .A            = S.A,
      .instances    = gpu_data,
      .commands     = commands,
      .opaque_count = opaque_count,
    };
  }
};
