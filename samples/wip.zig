//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps std
const std = @import("std");
// @deps minirender
const minirender = @import("minirender");
const vec3       = minirender.vec3;
const vec2       = minirender.vec2;
const vec4       = minirender.vec4;


//______________________________________
// @section Entry Point
//____________________________
pub fn main (P :std.process.Init) !void {
  var R = try minirender.Render.create(P.io, P.arena.allocator(), .{
    .title = "minirender | Sample Cube",
    .mouse = .normal,
    .atlas = .{ .cell_width = 8, .cell_height = 8, .cells_len = 0 },
  });
  defer R.destroy();

  R.camera.pos    = minirender.vec4(0.0, -6.0, 2.0, 1.0);
  R.camera.fov    = 60.0;
  R.camera.aspect = 960.0 / 540.0;

  const cube  = try R.shape(&cube_vertices, &cube_indices);
  const glass = try R.shape_alpha(&cube_vertices, &cube_indices);
  _ = try R.instance(glass, .from_translation(vec3(0.0, 0.0, 1.6)), .create(1.0, 1.0, 1.0, 0.35));
  const spare = try R.shape(&cube_vertices, &cube_indices);
  _ = try R.instance(spare, .from_translation(vec3(0.0, 2.5, 0.0)), .create(1.0, 0.5, 0.0, 1.0));

  const red   = try R.instance(cube, spin(0.0, -2.0), .create(1.0, 0.2, 0.2, 1.0));
  const green = try R.instance(cube, spin(0.0,  0.0), .create(0.2, 1.0, 0.2, 1.0));
  const blue  = try R.instance(cube, spin(0.0,  2.0), .create(0.2, 0.2, 1.0, 1.0));

  try cull_check(&R);

  try R.ui_add_many(&.{
    .create(vec2(4.0,  4.0), vec2(10.0, 6.0), vec4(0.9, 0.3, 0.3, 0.85), .square),
    .create(vec2(4.0, 12.0), vec2( 6.0, 6.0), vec4(0.3, 0.9, 0.4, 0.85), .circle),
    .create(vec2(4.0, 20.0), vec2( 6.0, 6.0), vec4(0.4, 0.5, 1.0, 0.85), .triangle),
  });
  try ui_text(&R, "minirender cvulkan", 16.0, 5.0, 2.5, vec4(1.0, 1.0, 1.0, 1.0));

  var selection :[selection_lines.len][3]f32 = undefined;
  var angle :minirender.math.Float = 0.0;
  var frame :usize = 0;
  var extra :?minirender.Instance.Id = null;
  while (!R.close()) {
    angle += 0.01;
    frame += 1;
    if (frame % 120 == 0) {
      if (extra) |id| { R.instance_remove(id); extra = null; }
      else extra = try R.instance(cube, .from_translation(vec3(0.0, 0.0, -1.6)), .create(1.0, 1.0, 0.2, 1.0));
    }
    if (frame % 180 == 0) if (extra) |id| R.reassign_instance(id, glass, .from_translation(vec3(0.0, 0.0, -1.6)), .create(0.2, 1.0, 1.0, 0.5));
    if (frame == 300) R.shape_remove(spare);
    const world_red = spin(angle, -2.0);
    R.update_instance(red,   world_red,             .create(1.0, 0.2, 0.2, 1.0));
    R.update_instance(green, spin(angle * 1.5, 0.0), .create(0.2, 1.0, 0.2, 1.0));
    R.update_instance(blue,  spin(angle * 2.0, 2.0), .create(0.2, 0.2, 1.0, 1.0));
    selection_transform(&selection, &world_red);
    R.set_selection_lines(&selection, .{ 1.0, 1.0, 0.0, 1.0 });
    R.update();
    R.clear();
    R.draw();
    const W = R.frame_width();
    const H = R.frame_height();
    const capturing = frame == 4 or frame == 5;
    const pixels :[]u8 = if (capturing) try P.arena.allocator().alloc(u8, @as(usize, W) * @as(usize, H) * 4) else &.{};
    if (capturing) R.capture_frame(pixels);
    R.present();
    if (capturing) {
      var name :[64]u8 = undefined;
      try png_write(P.io, try std.fmt.bufPrint(&name, "bin/frame{d}.png", .{ frame }), pixels, W, H, P.arena.allocator());
    }
  }
}

//______________________________________
// @section Capture
//____________________________
fn png_chunk (out :*std.ArrayList(u8), A :std.mem.Allocator, kind :*const [4]u8, body :[]const u8) !void {
  var head :[4]u8 = undefined;
  std.mem.writeInt(u32, &head, @intCast(body.len), .big);
  try out.appendSlice(A, &head);
  try out.appendSlice(A, kind);
  try out.appendSlice(A, body);
  var hasher = std.hash.Crc32.init();
  hasher.update(kind);
  hasher.update(body);
  var crc :[4]u8 = undefined;
  std.mem.writeInt(u32, &crc, hasher.final(), .big);
  try out.appendSlice(A, &crc);
}
//__________________
fn png_write (io :std.Io, path :[]const u8, pixels :[]const u8, W :u32, H :u32, A :std.mem.Allocator) !void {
  var raw = std.ArrayList(u8).empty;
  defer raw.deinit(A);
  for (0..H) |row| {
    try raw.append(A, 0);
    const line = pixels[row * W * 4 ..][0 .. W * 4];
    for (0..W) |column| {
      try raw.append(A, line[column * 4 + 2]);
      try raw.append(A, line[column * 4 + 1]);
      try raw.append(A, line[column * 4 + 0]);
    }
  }

  var body = std.ArrayList(u8).empty;
  defer body.deinit(A);
  try body.appendSlice(A, &.{ 0x78, 0x01 });
  var head :usize = 0;
  while (head < raw.items.len) {
    const span = @min(raw.items.len - head, 65535);
    const last :u8 = if (head + span >= raw.items.len) 1 else 0;
    try body.append(A, last);
    var size :[4]u8 = undefined;
    std.mem.writeInt(u16, size[0..2], @intCast(span), .little);
    std.mem.writeInt(u16, size[2..4], @intCast(~@as(u16, @intCast(span))), .little);
    try body.appendSlice(A, &size);
    try body.appendSlice(A, raw.items[head..][0..span]);
    head += span;
  }
  var sum_a :u32 = 1;
  var sum_b :u32 = 0;
  for (raw.items) |byte| {
    sum_a = (sum_a + byte) % 65521;
    sum_b = (sum_b + sum_a) % 65521;
  }
  var adler :[4]u8 = undefined;
  std.mem.writeInt(u32, &adler, (sum_b << 16) | sum_a, .big);
  try body.appendSlice(A, &adler);

  var out = std.ArrayList(u8).empty;
  defer out.deinit(A);
  try out.appendSlice(A, &.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A });
  var header :[13]u8 = undefined;
  std.mem.writeInt(u32, header[0..4], W, .big);
  std.mem.writeInt(u32, header[4..8], H, .big);
  header[8]  = 8;
  header[9]  = 2;
  header[10] = 0;
  header[11] = 0;
  header[12] = 0;
  try png_chunk(&out, A, "IHDR", &header);
  try png_chunk(&out, A, "IDAT", body.items);
  try png_chunk(&out, A, "IEND", &.{});

  try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.items });
}


//______________________________________
// @section Text
//____________________________
fn ui_text (
    R      : *minirender.Render,
    text   : []const u8,
    start_x : f32,
    start_y : f32,
    height  : f32,
    color   : minirender.Color,
  ) !void {
  const width   = height * @as(f32, minirender.font5x7.W) / @as(f32, minirender.font5x7.H);
  const advance = width * 1.25;
  var cursor_x  = start_x;
  for (text) |character| {
    const region = minirender.font5x7.region(character);
    if (region[2] > 0.0) try R.ui_add(.{
      .transform = .create(cursor_x, start_y, width, height),
      .uv        = .create(region[0], region[1], region[2], region[3]),
      .color     = color,
      .kind      = .square,
    });
    cursor_x += advance;
  }
}


//______________________________________
// @section Cull Check
//____________________________
fn cull_frame (R :*minirender.Render) minirender.cull.Counters {
  R.update();
  R.clear();
  R.draw();
  R.present();
  return R.cull_counters();
}
//__________________
fn cull_check (R :*minirender.Render) !void {
  const kept   = cull_frame(R);
  const facing = R.camera.pos;

  R.camera.pos = minirender.vec4(0.0, 4000.0, 0.0, 1.0);
  const away = cull_frame(R);

  R.camera.pos = facing;
  const back = cull_frame(R);

  std.debug.print("cull | facing {any}\n", .{kept});
  std.debug.print("cull | away   {any}\n", .{away});
  std.debug.print("cull | back   {any}\n", .{back});
  var out_instances :[8]minirender.Instance.Gpu = undefined;
  var out_commands  :[8]minirender.Command = undefined;
  R.cull_instances_read(out_instances[0..kept.instance_len]);
  R.cull_commands_read(out_commands[0..(kept.opaque_len + kept.alpha_len)]);
  for (out_instances[0..kept.instance_len], 0..) |entry, id| {
    std.debug.print("cull out | instance {d} color {any}\n", .{ id, entry.color });
  }
  for (out_commands[0..(kept.opaque_len + kept.alpha_len)], 0..) |entry, id| {
    std.debug.print("cull out | command {d} {any}\n", .{ id, entry });
  }

  if (kept.opaque_len == 0 and kept.alpha_len == 0) return error.CullDropsEverything;
  if (away.opaque_len != 0 or away.alpha_len != 0) return error.CullDropsNothing;
  if (back.opaque_len != kept.opaque_len or back.alpha_len != kept.alpha_len) return error.CullNotRepeatable;
}


//__________________
fn spin (angle :minirender.math.Float, offset :minirender.math.Float) minirender.Mat4 {
  var world = minirender.Mat4.from_rotation_z(angle);
  world.translate(vec3(offset, 0.0, 0.0));
  return world;
}

//______________________________________
// @section Atlas
//____________________________
const checker_size = 8;
//__________________
const checker_pixels = build: {
  var pixels :[checker_size * checker_size * 4]u8 = undefined;
  for (0..checker_size) |row| for (0..checker_size) |column| {
    const value :u8 = if ((row + column) % 2 == 0) 255 else 90;
    const index = (row * checker_size + column) * 4;
    pixels[index + 0] = value;
    pixels[index + 1] = value;
    pixels[index + 2] = value;
    pixels[index + 3] = 255;
  };
  break :build pixels;
};


//______________________________________
// @section Selection
//____________________________
const selection_lines = [_][3]f32{
  .{ -0.55, -0.55, -0.55 }, .{  0.55, -0.55, -0.55 },
  .{  0.55, -0.55, -0.55 }, .{  0.55,  0.55, -0.55 },
  .{  0.55,  0.55, -0.55 }, .{ -0.55,  0.55, -0.55 },
  .{ -0.55,  0.55, -0.55 }, .{ -0.55, -0.55, -0.55 },
  .{ -0.55, -0.55,  0.55 }, .{  0.55, -0.55,  0.55 },
  .{  0.55, -0.55,  0.55 }, .{  0.55,  0.55,  0.55 },
  .{  0.55,  0.55,  0.55 }, .{ -0.55,  0.55,  0.55 },
  .{ -0.55,  0.55,  0.55 }, .{ -0.55, -0.55,  0.55 },
  .{ -0.55, -0.55, -0.55 }, .{ -0.55, -0.55,  0.55 },
  .{  0.55, -0.55, -0.55 }, .{  0.55, -0.55,  0.55 },
  .{  0.55,  0.55, -0.55 }, .{  0.55,  0.55,  0.55 },
  .{ -0.55,  0.55, -0.55 }, .{ -0.55,  0.55,  0.55 },
};
//__________________
fn selection_transform (trg :[][3]f32, world :*const minirender.Mat4) void {
  for (trg, selection_lines) |*position, local| {
    const point = world.apply(minirender.vec4(local[0], local[1], local[2], 1.0));
    position.* = .{ @floatCast(point.x()), @floatCast(point.y()), @floatCast(point.z()) };
  }
}


//______________________________________
// @section Geometry
//____________________________
const cube_indices = [_]u32{
   0,  1,  2,  2,  3,  0,
   4,  5,  6,  6,  7,  4,
   8,  9, 10, 10, 11,  8,
  12, 13, 14, 14, 15, 12,
  16, 17, 18, 18, 19, 16,
  20, 21, 22, 22, 23, 20,
};
//__________________
const cube_vertices = [_]minirender.Vertex{
  // front
  .{ .position= .{ -0.5, -0.5,  0.5 }, .normal= .{  0.0,  0.0,  1.0 } },
  .{ .position= .{  0.5, -0.5,  0.5 }, .normal= .{  0.0,  0.0,  1.0 } },
  .{ .position= .{  0.5,  0.5,  0.5 }, .normal= .{  0.0,  0.0,  1.0 } },
  .{ .position= .{ -0.5,  0.5,  0.5 }, .normal= .{  0.0,  0.0,  1.0 } },
  // back
  .{ .position= .{  0.5, -0.5, -0.5 }, .normal= .{  0.0,  0.0, -1.0 } },
  .{ .position= .{ -0.5, -0.5, -0.5 }, .normal= .{  0.0,  0.0, -1.0 } },
  .{ .position= .{ -0.5,  0.5, -0.5 }, .normal= .{  0.0,  0.0, -1.0 } },
  .{ .position= .{  0.5,  0.5, -0.5 }, .normal= .{  0.0,  0.0, -1.0 } },
  // top
  .{ .position= .{ -0.5,  0.5,  0.5 }, .normal= .{  0.0,  1.0,  0.0 } },
  .{ .position= .{  0.5,  0.5,  0.5 }, .normal= .{  0.0,  1.0,  0.0 } },
  .{ .position= .{  0.5,  0.5, -0.5 }, .normal= .{  0.0,  1.0,  0.0 } },
  .{ .position= .{ -0.5,  0.5, -0.5 }, .normal= .{  0.0,  1.0,  0.0 } },
  // bottom
  .{ .position= .{ -0.5, -0.5, -0.5 }, .normal= .{  0.0, -1.0,  0.0 } },
  .{ .position= .{  0.5, -0.5, -0.5 }, .normal= .{  0.0, -1.0,  0.0 } },
  .{ .position= .{  0.5, -0.5,  0.5 }, .normal= .{  0.0, -1.0,  0.0 } },
  .{ .position= .{ -0.5, -0.5,  0.5 }, .normal= .{  0.0, -1.0,  0.0 } },
  // right
  .{ .position= .{  0.5, -0.5,  0.5 }, .normal= .{  1.0,  0.0,  0.0 } },
  .{ .position= .{  0.5, -0.5, -0.5 }, .normal= .{  1.0,  0.0,  0.0 } },
  .{ .position= .{  0.5,  0.5, -0.5 }, .normal= .{  1.0,  0.0,  0.0 } },
  .{ .position= .{  0.5,  0.5,  0.5 }, .normal= .{  1.0,  0.0,  0.0 } },
  // left
  .{ .position= .{ -0.5, -0.5, -0.5 }, .normal= .{ -1.0,  0.0,  0.0 } },
  .{ .position= .{ -0.5, -0.5,  0.5 }, .normal= .{ -1.0,  0.0,  0.0 } },
  .{ .position= .{ -0.5,  0.5,  0.5 }, .normal= .{ -1.0,  0.0,  0.0 } },
  .{ .position= .{ -0.5,  0.5, -0.5 }, .normal= .{ -1.0,  0.0,  0.0 } },
};

