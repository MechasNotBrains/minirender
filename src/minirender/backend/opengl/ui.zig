//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
const std = @import("std");
const gl  = @import("mgl").v4;
const mui = @import("mui");
const minirender = struct {
  const shaders = @import("./shaders.zig");
};


pub const GpuInstance = extern struct {
  position :[2]f32 = .{ 0, 0 },
  scale    :[2]f32 = .{ 0, 0 },
  color    :[4]f32 = .{ 1, 1, 1, 1 },
  uv       :[4]f32 = .{ 0, 0, 0, 0 },
  kind     :u32    = 0,
  offset   :f32    = 0,
  pad0     :u32    = 0,
  pad1     :u32    = 0,
};


pub const Render = struct {
  program              :gl.Shader      = undefined,
  vao                  :gl.VertexArray  = .{},
  quad_vbo             :gl.Buffer      = .{},
  quad_ebo             :gl.Buffer      = .{},
  instance_ssbo        :gl.Buffer      = .{ .target = .storage },
  screen_size_location :gl.Uniform     = .{},
  atlas_location       :gl.Uniform     = .{},
  instance_count       :usize          = 0,


  pub fn create () !Render {
    var result :Render = .{};

    result.program = try .create(
      try gl.Shader.vertex(minirender.shaders.ui_vert_src),
      try gl.Shader.fragment(minirender.shaders.ui_frag_src),
    );
    result.screen_size_location = result.program.uniform("uScreenSize");
    result.atlas_location       = result.program.uniform("uAtlas");

    result.vao = gl.VertexArray.create();
    result.vao.attribute(0, 2, .float, 0, 0);
    result.vao.attribute(1, 2, .float, 0, 2 * @sizeOf(f32));

    const quad_vertices = [4][4]f32{
      .{ 0, 0,  0, 0 },
      .{ 1, 0,  1, 0 },
      .{ 1, 1,  1, 1 },
      .{ 0, 1,  0, 1 },
    };
    const quad_indices = [6]u32{ 0, 1, 2, 0, 2, 3 };

    result.quad_vbo = gl.Buffer.create(@sizeOf(@TypeOf(quad_vertices)), .{});
    result.quad_vbo.upload(&quad_vertices, 0);
    result.vao.buffer(0, result.quad_vbo, 4 * @sizeOf(f32));

    result.quad_ebo = gl.Buffer.create(@sizeOf(@TypeOf(quad_indices)), .{});
    result.quad_ebo.upload(&quad_indices, 0);
    result.vao.element_buffer(result.quad_ebo);

    return result;
  }

  pub fn destroy (R :*Render) void {
    R.program.delete();
    R.vao.delete();
    if (R.quad_vbo.id      != 0) R.quad_vbo.delete();
    if (R.quad_ebo.id      != 0) R.quad_ebo.delete();
    if (R.instance_ssbo.id != 0) R.instance_ssbo.delete();
  }

  pub fn sync (R :*Render, scene :*const mui.Scene, screen_width :f32, screen_height :f32) void {
    const shapes = scene.shapes.data();
    if (shapes.len == 0) {
      R.instance_count = 0;
      return;
    }

    const needed = shapes.len * @sizeOf(GpuInstance);
    if (R.instance_ssbo.id == 0 or R.instance_ssbo.size < needed) {
      if (R.instance_ssbo.id != 0) R.instance_ssbo.delete();
      R.instance_ssbo = gl.Buffer.create(@max(needed, 1024), .{ .target = .storage });
    }

    const gpu_data = std.heap.page_allocator.alloc(GpuInstance, shapes.len) catch return;
    defer std.heap.page_allocator.free(gpu_data);

    for (shapes, 0..) |shape, index| {
      gpu_data[index] = .{
        .position = .{
          @floatCast(shape.transform.data[0] / 100.0 * screen_width),
          @floatCast(shape.transform.data[1] / 100.0 * screen_height),
        },
        .scale = .{
          @floatCast(shape.transform.data[2] / 100.0 * screen_width),
          @floatCast(shape.transform.data[3] / 100.0 * screen_height),
        },
        .color = .{
          @floatCast(shape.color.r()),
          @floatCast(shape.color.g()),
          @floatCast(shape.color.b()),
          @floatCast(shape.color.a()),
        },
        .uv = .{
          @floatCast(shape.uv.data[0]),
          @floatCast(shape.uv.data[1]),
          @floatCast(shape.uv.data[2]),
          @floatCast(shape.uv.data[3]),
        },
        .kind = @intFromEnum(shape.kind),
        .offset = @floatCast(shape.offset),
      };
    }

    R.instance_ssbo.upload(gpu_data, 0);
    R.instance_count = shapes.len;

    R.program.enable();
    R.vao.enable();
    R.screen_size_location.set([2]f32{ screen_width, screen_height });
    R.atlas_location.set(@as(i32, 0));
    R.instance_ssbo.enable_base(0);

    gl.state.disable(.depth_test);
    gl.state.enable(.blend);
    gl.state.blend.set(.src_alpha, .one_minus_src_alpha);

    gl.draw.elements_instanced(.triangles, 6, .unsigned_int, R.instance_count);

    gl.state.enable(.depth_test);
    R.vao.disable();
    R.program.disable();
  }
};
