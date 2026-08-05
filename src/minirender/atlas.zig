//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
const std = @import("std");
const mstd = @import("mstd");
const gl = @import("mgl").v4;

pub const Atlas = @This();

texture      :gl.Texture      = .{},
cell_width   :u32             = 0,
cell_height  :u32             = 0,
columns      :u32             = 0,
rows         :u32             = 0,
next_slot    :u32             = 0,
sizes        :?mstd.seq(Size) = null,

pub const Handle = u32;
/// Area a loaded image takes up inside its cell. The rest of the cell is never drawn.
pub const Size = struct { width :u32 = 0, height :u32 = 0 };

pub fn create (cell_width :u32, cell_height :u32, columns :u32, rows :u32, A :std.mem.Allocator) !Atlas {
  const atlas_width  = cell_width  * columns;
  const atlas_height = cell_height * rows;
  return .{
    .texture     = gl.Texture.create(.texture_2d, atlas_width, atlas_height, .rgba8, .{
      .filter_min = .nearest,
      .filter_mag = .nearest,
    }),
    .cell_width  = cell_width,
    .cell_height = cell_height,
    .columns     = columns,
    .rows        = rows,
    .sizes       = try .create_fill(.{}, columns * rows, A),
  };
}

pub fn destroy (A :*Atlas) void {
  if (A.texture.id != 0) A.texture.delete();
  if (A.sizes) |sizes| sizes.destroy();
  A.* = .{};
}

pub fn load (A :*Atlas, pixels :?*const anyopaque, width :u32, height :u32, pixel_format :gl.Texture.PixelFormat) ?Handle {
  if (A.next_slot >= A.columns * A.rows) return null;
  const handle = A.next_slot;
  const column = handle % A.columns;
  const row    = handle / A.columns;
  const offset_x = column * A.cell_width;
  const offset_y = row    * A.cell_height;
  A.texture.upload_region(offset_x, offset_y, width, height, pixels, pixel_format);
  if (A.sizes) |*sizes| sizes.at_ptr(handle).* = .{ .width = width, .height = height };
  A.next_slot += 1;
  return handle;
}

pub fn image_size (A :*const Atlas, handle :Handle) Size {
  const sizes = A.sizes orelse return .{};
  if (handle >= sizes.len()) return .{};
  return sizes.at(handle);
}

pub fn image_scale (A :*const Atlas, handle :Handle) [2]f32 {
  const atlas_width  :f32 = @floatFromInt(A.cell_width  * A.columns);
  const atlas_height :f32 = @floatFromInt(A.cell_height * A.rows);
  const size = A.image_size(handle);
  return .{
    @as(f32, @floatFromInt(size.width))  / atlas_width,
    @as(f32, @floatFromInt(size.height)) / atlas_height,
  };
}

pub fn cell_offset (A :*const Atlas, handle :Handle) [2]f32 {
  const column = handle % A.columns;
  const row    = handle / A.columns;
  const atlas_width  :f32 = @floatFromInt(A.cell_width  * A.columns);
  const atlas_height :f32 = @floatFromInt(A.cell_height * A.rows);
  return .{
    @as(f32, @floatFromInt(column * A.cell_width))  / atlas_width,
    @as(f32, @floatFromInt(row    * A.cell_height)) / atlas_height,
  };
}

pub fn bind (A :*const Atlas, unit :u32) void {
  A.texture.bind(unit);
}
