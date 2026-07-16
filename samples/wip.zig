//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps std
const std = @import("std");
// @deps minirender
const minirender = @import("minirender");

pub fn main() !void {
  var R = try minirender.Render.create(std.heap.page_allocator, .{
    .title = "minirender sample",
  });
  defer R.destroy();

  R.camera.pos = minirender.vec4(0.0, -6.0, 2.0, 1.0);
  R.camera.fov = 60.0;
  R.camera.aspect = 960.0 / 540.0;

  const cube = try R.shape(&cube_vertices, &cube_indices);

  _ = try R.instance(cube, translation(-2.0, 0.0, 0.0), .{ 1.0, 0.2, 0.2, 1.0 });
  _ = try R.instance(cube, translation( 0.0, 0.0, 0.0), .{ 0.2, 1.0, 0.2, 1.0 });
  _ = try R.instance(cube, translation( 2.0, 0.0, 0.0), .{ 0.2, 0.2, 1.0, 1.0 });

  while (!R.close()) {
    R.update();
    R.clear();
    R.sync();
    R.present();
  }
}

fn translation(x: f32, y: f32, z: f32) [16]f32 {
  return .{
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    x,   y,   z,   1.0,
  };
}

const Vertex = minirender.Vertex;

const cube_vertices = [_]Vertex{
  // front
  .{ .position = .{ -0.5, -0.5,  0.5 }, .normal = .{  0.0,  0.0,  1.0 } },
  .{ .position = .{  0.5, -0.5,  0.5 }, .normal = .{  0.0,  0.0,  1.0 } },
  .{ .position = .{  0.5,  0.5,  0.5 }, .normal = .{  0.0,  0.0,  1.0 } },
  .{ .position = .{ -0.5,  0.5,  0.5 }, .normal = .{  0.0,  0.0,  1.0 } },
  // back
  .{ .position = .{  0.5, -0.5, -0.5 }, .normal = .{  0.0,  0.0, -1.0 } },
  .{ .position = .{ -0.5, -0.5, -0.5 }, .normal = .{  0.0,  0.0, -1.0 } },
  .{ .position = .{ -0.5,  0.5, -0.5 }, .normal = .{  0.0,  0.0, -1.0 } },
  .{ .position = .{  0.5,  0.5, -0.5 }, .normal = .{  0.0,  0.0, -1.0 } },
  // top
  .{ .position = .{ -0.5,  0.5,  0.5 }, .normal = .{  0.0,  1.0,  0.0 } },
  .{ .position = .{  0.5,  0.5,  0.5 }, .normal = .{  0.0,  1.0,  0.0 } },
  .{ .position = .{  0.5,  0.5, -0.5 }, .normal = .{  0.0,  1.0,  0.0 } },
  .{ .position = .{ -0.5,  0.5, -0.5 }, .normal = .{  0.0,  1.0,  0.0 } },
  // bottom
  .{ .position = .{ -0.5, -0.5, -0.5 }, .normal = .{  0.0, -1.0,  0.0 } },
  .{ .position = .{  0.5, -0.5, -0.5 }, .normal = .{  0.0, -1.0,  0.0 } },
  .{ .position = .{  0.5, -0.5,  0.5 }, .normal = .{  0.0, -1.0,  0.0 } },
  .{ .position = .{ -0.5, -0.5,  0.5 }, .normal = .{  0.0, -1.0,  0.0 } },
  // right
  .{ .position = .{  0.5, -0.5,  0.5 }, .normal = .{  1.0,  0.0,  0.0 } },
  .{ .position = .{  0.5, -0.5, -0.5 }, .normal = .{  1.0,  0.0,  0.0 } },
  .{ .position = .{  0.5,  0.5, -0.5 }, .normal = .{  1.0,  0.0,  0.0 } },
  .{ .position = .{  0.5,  0.5,  0.5 }, .normal = .{  1.0,  0.0,  0.0 } },
  // left
  .{ .position = .{ -0.5, -0.5, -0.5 }, .normal = .{ -1.0,  0.0,  0.0 } },
  .{ .position = .{ -0.5, -0.5,  0.5 }, .normal = .{ -1.0,  0.0,  0.0 } },
  .{ .position = .{ -0.5,  0.5,  0.5 }, .normal = .{ -1.0,  0.0,  0.0 } },
  .{ .position = .{ -0.5,  0.5, -0.5 }, .normal = .{ -1.0,  0.0,  0.0 } },
};

const cube_indices = [_]u32{
  0,  1,  2,  2,  3,  0,
  4,  5,  6,  6,  7,  4,
  8,  9,  10, 10, 11, 8,
  12, 13, 14, 14, 15, 12,
  16, 17, 18, 18, 19, 16,
  20, 21, 22, 22, 23, 20,
};
