//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const atlas = @This();
pub const Atlas = @This().Type;
const This = @This();
// @deps std
const std  = @import("std");
const mstd = @import("mstd");
// @deps minirender
const cvk = @import("cvulkan");
const minirender = struct {
  const Gpu  = @import("./gpu.zig").Gpu;
  const Sync = @import("./sync.zig").Sync;
};


//_______________________________________
// @section Constants
//_____________________________
pub const format = cvk.vk.Format.r8g8b8a8_srgb;
pub const bytes_per_pixel = 4;


//_______________________________________
// @section Object Fields
//_____________________________
pub const Handle = u32;
//__________________
pub const Size = struct { width :u32 = 0, height :u32 = 0 };
//__________________
pub const Args = struct {
  cell_width  :u32,
  cell_height :u32,
  cells_len   :u32,
};
//__________________
pub const Grid = struct { columns :u32 = 0, rows :u32 = 0 };
//__________________
pub fn grid (cells_len :u32) This.Grid {
  if (cells_len == 0) return .{};
  const columns :u32= @intFromFloat(@ceil(@sqrt(@as(f64, @floatFromInt(cells_len)))));
  return .{ .columns = columns, .rows = (cells_len + columns - 1) / columns };
}
//__________________
pub const Type = struct {
  data        :cvk.image.Data    = .{},
  memory      :cvk.Memory        = .{},
  view        :cvk.image.View    = .{},
  sampler     :cvk.image.Sampler = .{},
  cell_width  :u32 = 0,
  cell_height :u32 = 0,
  columns     :u32 = 0,
  rows        :u32 = 0,
  next_slot   :u32 = 0,
  sizes       :?mstd.seq(This.Size) = null,

  pub const Handle      = This.Handle;
  pub const Size        = This.Size;
  pub const create      = This.create;
  pub const destroy     = This.destroy;
  pub const load        = This.load;
  pub const image_size  = This.image_size;
  pub const image_scale = This.image_scale;
  pub const cell_offset = This.cell_offset;
  pub const width       = This.width;
  pub const height      = This.height;
};


//_______________________________________
// @section Create/Destroy
//_____________________________
pub fn destroy (A :*const Type, gpu :*minirender.Gpu) void {
  var mutable :*Type= @constCast(A); _= &mutable;
  mutable.sampler.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.view.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
  mutable.data.destroy(&gpu.device.logical, &gpu.instance.allocator);
  if (mutable.sizes) |sizes| sizes.destroy();
  mutable.* = .{};
}
//__________________
pub fn create (
    gpu         : *minirender.Gpu,
    S           : *const minirender.Sync,
    cell_width  : u32,
    cell_height : u32,
    columns     : u32,
    rows        : u32,
    A           : std.mem.Allocator,
  ) !Type {
  var result :Type= .{
    .cell_width  = cell_width,
    .cell_height = cell_height,
    .columns     = columns,
    .rows        = rows,
    .sizes       = try .create_fill(.{}, columns * rows, A),
  };
  result.data    = .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .format          = This.format,
    .usage           = .initMany(&.{ .transfer_dst, .sampled }),
    .memory_flags    = .initOne(.device_local),
    .dimensions      = .dim2d,
    .width           = result.width(),
    .height          = result.height(),
  });
  result.memory  = .create(.{
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size_alloc      = result.data.memory.requirements.size,
    .kind            = result.data.memory.kind,
  });
  result.data.bind(.{
    .device_logical  = &gpu.device.logical,
    .memory          = &result.memory,
  });
  result.view    = .create(.{
    .image_data      = &result.data,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .aspect          = .initOne(.color),
  });
  result.sampler = .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .filter_min      = .nearest,
    .filter_mag      = .nearest,
    .address_U       = .clamp_to_edge,
    .address_V       = .clamp_to_edge,
    .address_W       = .clamp_to_edge,
  });

  const buffer = S.buffer_begin_onetime(gpu);
  buffer.image_data_transition(&result.data, .{
    .layout_old = .undefined,
    .layout_new = .transfer_dst_optimal,
    .access_trg = .initOne(.transfer_write),
    .stage_src  = .initOne(.top_of_pipe),
    .stage_trg  = .initOne(.transfer),
    .aspect     = .initOne(.color),
  });
  buffer.image_data_clear(&result.data, .{
    .layout     = .transfer_dst_optimal,
    .color      = .{ .float32 = .{ 0, 0, 0, 0 } },
    .aspect     = .initOne(.color),
  });
  buffer.image_data_transition(&result.data, .{
    .layout_old = .transfer_dst_optimal,
    .layout_new = .shader_read_only_optimal,
    .access_src = .initOne(.transfer_write),
    .access_trg = .initOne(.shader_read),
    .stage_src  = .initOne(.transfer),
    .stage_trg  = .initOne(.fragment_shader),
    .aspect     = .initOne(.color),
  });
  S.buffer_end_onetime(&buffer, gpu);
  return result;
}


//_______________________________________
// @section Process
//_____________________________
pub fn load (
    A      : *Type,
    gpu    : *minirender.Gpu,
    S      : *const minirender.Sync,
    pixels : []const u8,
    size   : This.Size,
  ) ?This.Handle {
  if (A.next_slot >= A.columns * A.rows) return null;
  if (size.width == 0 or size.height == 0) return null;
  if (pixels.len < size.width * size.height * This.bytes_per_pixel) return null;
  const handle = A.next_slot;

  var staging :cvk.Buffer= .create(.{
    .device_physical = &gpu.device.physical,
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size            = pixels.len,
    .usage           = .initOne(.transfer_src),
    .memory_flags    = .initMany(&.{ .host_visible, .host_coherent }),
  });
  defer staging.destroy(&gpu.device.logical, &gpu.instance.allocator);
  var memory :cvk.Memory= .create(.{
    .device_logical  = &gpu.device.logical,
    .allocator       = &gpu.instance.allocator,
    .size_alloc      = staging.memory.requirements.size,
    .size_data       = pixels.len,
    .kind            = staging.memory.kind,
    .data            = @constCast(@ptrCast(pixels.ptr)),
  });
  defer memory.destroy(&gpu.device.logical, &gpu.instance.allocator);
  staging.bind(.{
    .device_logical  = &gpu.device.logical,
    .memory          = &memory,
  });

  const buffer = S.buffer_begin_onetime(gpu);
  buffer.image_data_transition(&A.data, .{
    .layout_old  = .shader_read_only_optimal,
    .layout_new  = .transfer_dst_optimal,
    .access_src  = .initOne(.shader_read),
    .access_trg  = .initOne(.transfer_write),
    .stage_src   = .initOne(.fragment_shader),
    .stage_trg   = .initOne(.transfer),
    .aspect      = .initOne(.color),
  });
  buffer.image_data_copy_fromBuffer(&A.data, &staging, .{
    .extent       = .{ .width = size.width, .height = size.height, .depth = 1 },
    .offset_image = .{
      .x = @intCast((handle % A.columns) * A.cell_width),
      .y = @intCast((handle / A.columns) * A.cell_height),
      .z = 0,
    },
  });
  buffer.image_data_transition(&A.data, .{
    .layout_old  = .transfer_dst_optimal,
    .layout_new  = .shader_read_only_optimal,
    .access_src  = .initOne(.transfer_write),
    .access_trg  = .initOne(.shader_read),
    .stage_src   = .initOne(.transfer),
    .stage_trg   = .initOne(.fragment_shader),
    .aspect      = .initOne(.color),
  });
  S.buffer_end_onetime(&buffer, gpu);

  if (A.sizes) |*sizes| sizes.at_ptr(handle).* = size;
  A.next_slot += 1;
  return handle;
}


//_______________________________________
// @section Ergonomic Helpers
//_____________________________
pub inline fn width  (A :*const Type) u32 { return A.cell_width  * A.columns; }
pub inline fn height (A :*const Type) u32 { return A.cell_height * A.rows; }
//__________________
pub fn image_size (A :*const Type, handle :This.Handle) This.Size {
  const sizes = A.sizes orelse return .{};
  if (handle >= sizes.len()) return .{};
  return sizes.at(handle);
}
//__________________
pub fn image_scale (A :*const Type, handle :This.Handle) [2]f32 {
  const size = A.image_size(handle);
  return .{
    @as(f32, @floatFromInt(size.width))  / @as(f32, @floatFromInt(A.width())),
    @as(f32, @floatFromInt(size.height)) / @as(f32, @floatFromInt(A.height())),
  };
}
//__________________
pub fn cell_offset (A :*const Type, handle :This.Handle) [2]f32 {
  const column = handle % A.columns;
  const row    = handle / A.columns;
  return .{
    @as(f32, @floatFromInt(column * A.cell_width))  / @as(f32, @floatFromInt(A.width())),
    @as(f32, @floatFromInt(row    * A.cell_height)) / @as(f32, @floatFromInt(A.height())),
  };
}
