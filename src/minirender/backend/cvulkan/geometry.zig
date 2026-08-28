//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const geometry = @This();
pub const Geometry = @This().Type;
const This = @This();
// @deps std
const std  = @import("std");
const mstd = @import("mstd");
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu    = @import("./gpu.zig").Gpu;
  const Sync   = @import("./sync.zig").Sync;
  const sync   = @import("./sync.zig");
  const Buffer = @import("./buffer.zig").Buffer;
  const Host   = @import("./buffer.zig").buffer.Host;
  const Store  = @import("../../store.zig").Store;
  const Vertex = @import("../../geometry.zig").Vertex;
  const Command = @import("../../store.zig").Command;
  const GpuInstanceData = @import("../../geometry.zig").GpuInstanceData;
};
const sync = minirender.sync;


//_______________________________________
// @section Vertex Input
//_____________________________
pub const binding :cvk.vk.VertexInputBindingDescription = .{
  .binding   = 0,
  .stride    = @sizeOf(minirender.Vertex),
  .inputRate = @intFromEnum(cvk.vk.VertexInputRate.vertex),
};
//__________________
pub const attributes = [_]cvk.vk.VertexInputAttributeDescription{
  .{ .location = 0, .binding = 0, .format = @intFromEnum(cvk.vk.Format.r32g32b32_sfloat),    .offset = @offsetOf(minirender.Vertex, "position")     },
  .{ .location = 1, .binding = 0, .format = @intFromEnum(cvk.vk.Format.r32g32b32_sfloat),    .offset = @offsetOf(minirender.Vertex, "normal")       },
  .{ .location = 2, .binding = 0, .format = @intFromEnum(cvk.vk.Format.r32g32_sfloat),       .offset = @offsetOf(minirender.Vertex, "uv")           },
  .{ .location = 3, .binding = 0, .format = @intFromEnum(cvk.vk.Format.r32g32_sfloat),       .offset = @offsetOf(minirender.Vertex, "atlas_offset") },
  .{ .location = 4, .binding = 0, .format = @intFromEnum(cvk.vk.Format.r32g32_sfloat),       .offset = @offsetOf(minirender.Vertex, "atlas_scale")  },
  .{ .location = 5, .binding = 0, .format = @intFromEnum(cvk.vk.Format.r32g32b32a32_sfloat), .offset = @offsetOf(minirender.Vertex, "color")        },
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
  const array align(@alignOf(u32)) = @embedFile("./shaders/geometry.vert.spv").*;
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
  const array align(@alignOf(u32)) = @embedFile("./shaders/geometry.frag.spv").*;
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
pub const Patch = struct {
  slot :u32,
  data :minirender.GpuInstanceData,
};
//__________________
pub const Type = struct {
  shader          :This.Shader = .{},
  vertex_buffer   :minirender.Buffer = .{ .usage = .initOne(.vertex_buffer) },
  index_buffer    :minirender.Buffer = .{ .usage = .initOne(.index_buffer) },
  instance_buffer :[sync.frames_Len]minirender.Host = @splat(.{ .usage = .initOne(.storage_buffer) }),
  instance_dirty  :[sync.frames_Len]bool = @splat(false),
  patches         :mstd.seq(This.Patch),
  patched         :[sync.frames_Len]usize = @splat(0),
  indirect_buffer :[sync.frames_Len]minirender.Buffer = @splat(.{ .usage = .initMany(&.{ .indirect_buffer, .storage_buffer }) }),
  indirect_len    :u32 = 0,
  opaque_len      :u32 = 0,
  instance_len    :u32 = 0,


  //_______________________________________
  // @section Create/Destroy
  //_____________________________
  pub fn create (gpu :*minirender.Gpu, A :std.mem.Allocator) @This() {
    return .{ .shader = .create(gpu), .patches = .create_empty(A) };
  }
  //__________________
  pub fn destroy (G :*const @This(), gpu :*minirender.Gpu) void {
    var mutable :*@This()= @constCast(G); _= &mutable;
    mutable.shader.destroy(gpu);
    mutable.vertex_buffer.destroy(gpu);
    mutable.index_buffer.destroy(gpu);
    for (&mutable.instance_buffer) |*B| B.destroy(gpu);
    for (&mutable.indirect_buffer) |*B| B.destroy(gpu);
    mutable.patches.destroy();
    mutable.patched        = @splat(0);
    mutable.instance_dirty = @splat(false);
    mutable.indirect_len   = 0;
    mutable.opaque_len     = 0;
    mutable.instance_len   = 0;
  }


  //_______________________________________
  // @section Process
  //_____________________________
  pub fn upload (
      G     : *@This(),
      store : *minirender.Store,
      gpu   : *minirender.Gpu,
      S     : *const minirender.Sync,
    ) void {
    if (store.geometry_dirty) {
      if (store.geometry_gapped) {
        store.pack_geometry();
        store.geometry_gapped = false;
      }
      const verts = store.vertices.data();
      const inds  = store.indices.data();
      if (verts.len != 0) G.vertex_buffer.upload(gpu, S, std.mem.sliceAsBytes(verts));
      if (inds.len  != 0) G.index_buffer.upload(gpu, S, std.mem.sliceAsBytes(inds));
      store.geometry_dirty  = false;
      store.instances_dirty = true;
    }

    if (store.instances_dirty) {
      store.instances_dirty = false;
      G.instance_dirty = @splat(true);
      G.patches.clear();
      G.patched = @splat(0);
    }

    if (!G.instance_dirty[S.frameID]) return G.patch(S);
    G.instance_dirty[S.frameID] = false;
    const draws = store.build() orelse { G.indirect_len = 0; return; };
    defer draws.destroy();
    G.instance_buffer[S.frameID].fit(gpu, std.mem.sliceAsBytes(draws.instances).len);
    G.instance_buffer[S.frameID].write(0, std.mem.sliceAsBytes(draws.instances));
    G.indirect_buffer[S.frameID].upload(gpu, S, std.mem.sliceAsBytes(draws.commands));
    G.indirect_len   = @intCast(draws.commands.len);
    G.opaque_len     = draws.opaque_count;
    G.instance_len   = @intCast(draws.instances.len);
    G.patched[S.frameID] = G.patches.len();
  }
  //__________________
  pub fn patch_add (G :*@This(), slot :u32, data :minirender.GpuInstanceData) void {
    G.patches.add_one(.{ .slot = slot, .data = data }) catch { G.instance_dirty = @splat(true); };
  }
  //__________________
  pub fn patch (G :*@This(), S :*const minirender.Sync) void {
    const pending = G.patches.data();
    for (pending[G.patched[S.frameID]..]) |entry| {
      G.instance_buffer[S.frameID].write(
        entry.slot * @sizeOf(minirender.GpuInstanceData),
        std.mem.asBytes(&entry.data),
      );
    }
    G.patched[S.frameID] = pending.len;
    for (G.patched) |applied| if (applied != pending.len) return;
    G.patches.clear();
    G.patched = @splat(0);
  }
};
