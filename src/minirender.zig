//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
//! Minimalistic renderer
//!
//! Visualizing vector math in a 3D coordinate system.
//! Self-contained:
//! - Minimal OpenGL & GLFW bindings
//! - 5x7 bitfont
//! - Simple math library
//! - Batched immediate-mode drawing
//!
//! Usage:
//! ```zig
//! const minirender = @import("minirender");
//! var ctx = try minirender.create(allocator);
//! defer ctx.destroy();
//!
//! // each frame:
//! ctx.begin(wvp_matrix);
//! ctx.axes(1.0);
//! ctx.arrow(.{0,0,0,1}, .{1,2,3,0}, dd.Color.yellow);
//! ctx.text3d(.{1,2,3,0}, "velocity", dd.Color.white);
//! ctx.end(); // flushes all batched geometry
//! ```
//_________________________________________________________________|
pub const Renderer = @This();
// @deps std
const std = @import("std");
// @deps minirender
const gl   = @import("./minirender/lib/opengl.zig");
const glfw = @import("./minirender/lib/glfw.zig");
// @deps minirender.ui
const Vertex    = @import("./minirender/ui.zig").Vertex;
const UiVertex  = @import("./minirender/ui.zig").UiVertex;
const Camera    = @import("./minirender/camera.zig").Camera;
const font      = @import("./minirender/font.zig");
pub const Color = @import("./minirender/color.zig").Color;
pub const Ui    = @import("./minirender/ui.zig").Ui;


//______________________________________
// @section Forward Exports: Math
//____________________________
pub const Vec4          = @import("./minirender/math/vector.zig").Vec4;
pub const BiVec         = @import("./minirender/math/vector.zig").BiVec;
pub const Mat4          = @import("./minirender/math/matrix.zig").Mat4;
pub const mat4_identity = @import("./minirender/math/matrix.zig").mat4_identity;
pub const Rotor         = @import("./minirender/math/rotor.zig").Rotor;


//______________________________________
// @section Limits
//____________________________
pub const MAX_VERTICES    = 64 * 1024;
pub const BUFFER_SIZE     = MAX_VERTICES * Vertex.Stride;
pub const UI_MAX_VERTICES = 1024;
pub const UI_BUFFER_SIZE  = UI_MAX_VERTICES * UiVertex.Stride;


//______________________________________
// @section Shaders
//____________________________
const vert_src    = @import("./minirender/shaders.zig").vert_src;
const frag_src    = @import("./minirender/shaders.zig").frag_src;
const ui_vert_src = @import("./minirender/shaders.zig").ui_vert_src;
const ui_frag_src = @import("./minirender/shaders.zig").ui_frag_src;


//______________________________________
// @section Object Fields
//____________________________
// GLFW objects
window   :?*glfw.Window,

// GL objects — 3D scene
program  :gl.Uint,
vao      :gl.Uint,
vbo      :gl.Uint,
wvp_loc  :gl.Int,

// GL objects — UI overlay
ui_program         :gl.Uint = 0,
ui_vao             :gl.Uint = 0,
ui_vbo             :gl.Uint = 0,
ui_screen_size_loc :gl.Int  = -1,

// Batched geometry — 3D
line_vertices  :[MAX_VERTICES]Vertex= undefined,
line_count     :usize= 0,
tri_vertices   :[MAX_VERTICES]Vertex= undefined,
tri_count      :usize= 0,
text_vertices  :[MAX_VERTICES]Vertex= undefined,
text_count     :usize= 0,

// Batched geometry — UI
ui_vertices    :[UI_MAX_VERTICES]UiVertex = undefined,
ui_vertex_count :usize = 0,

// Camera Objects
camera  :Camera= .{},
wvp     :Mat4= mat4_identity,
view    :Mat4= mat4_identity,

// Frame timing
frame_start :f64 = 0,
frame_ms    :f32 = 0,
frame_fps   :f32 = 0,

// Mouse state
mouse_x      :f32  = 0,
mouse_y      :f32  = 0,
mouse_down   :bool = false,
ui_captured  :bool = false,


//______________________________________
// @section Create/Destroy
//____________________________
pub fn destroy (R :*const Renderer) void {
  const mutable :*Renderer= @constCast(R);
  gl.deleteProgram(mutable.program);
  gl.deleteBuffers(1, &[_]gl.Uint{mutable.vbo});
  gl.deleteVertexArrays(1, &[_]gl.Uint{mutable.vao});
  gl.deleteProgram(mutable.ui_program);
  gl.deleteBuffers(1, &[_]gl.Uint{mutable.ui_vbo});
  gl.deleteVertexArrays(1, &[_]gl.Uint{mutable.ui_vao});
  glfw.destroy();
}
//__________________
pub fn create (allocator: std.mem.Allocator) !*@This() {
  if (glfw.create() == 0) return error.GlfwInit;
  const result = try allocator.create(Renderer);
  @memset(std.mem.asBytes(result), 0);
  result.camera      = .{};
  result.wvp         = mat4_identity;
  result.view        = mat4_identity;
  result.frame_start = glfw.getTime();

  glfw.window.hint(glfw.opengl.context.version.M , 4);
  glfw.window.hint(glfw.opengl.context.version.m , 6);
  glfw.window.hint(glfw.opengl.context.Debug, @intFromBool(true));
  glfw.window.hint(glfw.Resizable, @intFromBool(false));

  result.window = glfw.window.create(960, 540, "mmath.debug", null, null) orelse return error.GlfwWindow;
  glfw.opengl.context.setActive(result.window);
  glfw.opengl.setVSync(0);
  glfw.setUserPointer(result.window, @ptrCast(result));

  try glfw.callback.setKey(result.window, Camera.callback.key);
  try glfw.callback.setMouseBtn(result.window, Camera.callback.mouseBtn);
  try glfw.callback.setMousePos(result.window, Camera.callback.mousePos);
  try glfw.callback.setScroll(result.window, Camera.callback.scrollCallback);

  const vs = try gl.compileShader(gl.Shader_Vertex, vert_src);
  defer gl.deleteShader(vs);
  const fs = try gl.compileShader(gl.Shader_Fragment, frag_src);
  defer gl.deleteShader(fs);

  result.program = gl.createProgram();
  gl.attachShader(result.program, vs);
  gl.attachShader(result.program, fs);
  gl.linkProgram(result.program);

  var link_status: gl.Int = 0;
  gl.getProgramiv(result.program, gl.Status_Link, &link_status);
  if (link_status == gl.False) {
    return error.ProgramLinkFailed;
  }

  result.vao = 0;
  gl.genVertexArrays(1, @ptrCast(&result.vao));
  result.vbo = 0;
  gl.genBuffers(1, @ptrCast(&result.vbo));

  gl.bindVertexArray(result.vao);
  gl.bindBuffer(gl.ArrayBuffer, result.vbo);
  gl.bufferData(gl.ArrayBuffer, BUFFER_SIZE, null, gl.DYNAMIC_DRAW);

  // position: location 0, 3 floats
  gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.False, Vertex.Stride, null);
  gl.enableVertexAttribArray(0);

  // color: location 1, 4 floats, offset 12 bytes
  const color_offset: usize = 3 * @sizeOf(f32);
  gl.vertexAttribPointer(1, 4, gl.FLOAT, gl.False, Vertex.Stride, @ptrFromInt(color_offset));
  gl.enableVertexAttribArray(1);

  gl.bindVertexArray(0);

  result.wvp_loc = gl.getUniformLocation(result.program, "uWVP");

  // --- UI shader program ---
  const ui_vs = try gl.compileShader(gl.Shader_Vertex, ui_vert_src);
  defer gl.deleteShader(ui_vs);
  const ui_fs = try gl.compileShader(gl.Shader_Fragment, ui_frag_src);
  defer gl.deleteShader(ui_fs);

  result.ui_program = gl.createProgram();
  gl.attachShader(result.ui_program, ui_vs);
  gl.attachShader(result.ui_program, ui_fs);
  gl.linkProgram(result.ui_program);
  var ui_link_status: gl.Int = 0;
  gl.getProgramiv(result.ui_program, gl.Status_Link, &ui_link_status);
  if (ui_link_status == gl.False) return error.UiProgramLinkFailed;

  result.ui_screen_size_loc = gl.getUniformLocation(result.ui_program, "uScreenSize");

  // --- UI VAO/VBO ---
  gl.genVertexArrays(1, @ptrCast(&result.ui_vao));
  gl.genBuffers(1, @ptrCast(&result.ui_vbo));
  gl.bindVertexArray(result.ui_vao);
  gl.bindBuffer(gl.ArrayBuffer, result.ui_vbo);
  gl.bufferData(gl.ArrayBuffer, UI_BUFFER_SIZE, null, gl.DYNAMIC_DRAW);

  const ui_stride = UiVertex.Stride;
  gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.False, ui_stride, @ptrFromInt(0));
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(1, 2, gl.FLOAT, gl.False, ui_stride, @ptrFromInt(2 * @sizeOf(f32)));
  gl.enableVertexAttribArray(1);
  gl.vertexAttribPointer(2, 2, gl.FLOAT, gl.False, ui_stride, @ptrFromInt(4 * @sizeOf(f32)));
  gl.enableVertexAttribArray(2);
  gl.vertexAttribPointer(3, 1, gl.FLOAT, gl.False, ui_stride, @ptrFromInt(6 * @sizeOf(f32)));
  gl.enableVertexAttribArray(3);
  gl.vertexAttribPointer(4, 4, gl.FLOAT, gl.False, ui_stride, @ptrFromInt(7 * @sizeOf(f32)));
  gl.enableVertexAttribArray(4);
  gl.vertexAttribPointer(5, 4, gl.FLOAT, gl.False, ui_stride, @ptrFromInt(11 * @sizeOf(f32)));
  gl.enableVertexAttribArray(5);
  gl.vertexAttribPointer(6, 1, gl.FLOAT, gl.False, ui_stride, @ptrFromInt(15 * @sizeOf(f32)));
  gl.enableVertexAttribArray(6);
  gl.vertexAttribPointer(7, 1, gl.FLOAT, gl.False, ui_stride, @ptrFromInt(16 * @sizeOf(f32)));
  gl.enableVertexAttribArray(7);
  gl.bindVertexArray(0);

  return result;
}


//______________________________________
// @section Helpers
//____________________________
pub fn present (R :*const @This()) void { glfw.opengl.present(R.window); }
pub fn close   (R :*const @This()) bool { return glfw.window.close(R.window) != 0; }
pub fn sync    (R :*const @This()) void { _=R; glfw.sync(); }
// Convenience: clear screen
pub fn clear (R :*const @This(), r :f32, g :f32, b :f32) void { _=R;
  gl.clearColor(r, g, b, 1.0);
  gl.clear(gl.Color | gl.Depth);
}


//______________________________________
// @section Batching
//____________________________
pub const push_vert_line = @import("./minirender/batching.zig").vert.line;
pub const push_vert_tri  = @import("./minirender/batching.zig").vert.tri;
pub const push_vert_text = @import("./minirender/batching.zig").vert.text;
pub const push_rect_ui   = @import("./minirender/batching.zig").rect.ui;


//______________________________________
// @section Frame begin / end
//____________________________
pub fn begin (R :*Renderer) void {
  const now     = glfw.getTime();
  const elapsed = now - R.frame_start;
  R.frame_start = now;
  R.frame_ms    = @floatCast(elapsed * 1000.0);
  R.frame_fps   = if (R.frame_ms > 0.0) 1000.0 / R.frame_ms else 0.0;

  R.wvp        = mat4_identity;
  R.view       = mat4_identity;
  R.line_count = 0;
  R.tri_count  = 0;
  R.text_count = 0;
}
//__________________
pub fn end (R: *Renderer) void {
  gl.useProgram(R.program);
  gl.bindVertexArray(R.vao);
  gl.bindBuffer(gl.ArrayBuffer, R.vbo);

  var m = R.wvp;
  gl.uniformMatrix4fv(R.wvp_loc, 1, gl.False, &m);

  gl.enable(gl.DEPTH_TEST);
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

  // Flush lines
  if (R.line_count > 0) {
    const size: gl.Sizeiptr = @intCast(R.line_count * Vertex.Stride);
    gl.bufferSubData(gl.ArrayBuffer, 0, size, &R.line_vertices);
    gl.drawArrays(gl.LINES, 0, @intCast(R.line_count));
  }

  // Flush triangles
  if (R.tri_count > 0) {
    const size: gl.Sizeiptr = @intCast(R.tri_count * Vertex.Stride);
    gl.bufferSubData(gl.ArrayBuffer, 0, size, &R.tri_vertices);
    gl.drawArrays(gl.Triangles, 0, @intCast(R.tri_count));
  }

  // Flush 3D text on top of everything (no depth test)
  if (R.text_count > 0) {
    gl.disable(gl.DEPTH_TEST);
    const size: gl.Sizeiptr = @intCast(R.text_count * Vertex.Stride);
    gl.bufferSubData(gl.ArrayBuffer, 0, size, &R.text_vertices);
    gl.drawArrays(gl.Triangles, 0, @intCast(R.text_count));
    gl.enable(gl.DEPTH_TEST);
  }

  gl.bindVertexArray(0);
  gl.useProgram(0);
}


pub fn ui_flush (R: *Renderer) void {
  if (R.ui_vertex_count == 0) return;

  gl.useProgram(R.ui_program);
  gl.bindVertexArray(R.ui_vao);
  gl.bindBuffer(gl.ArrayBuffer, R.ui_vbo);

  gl.uniform2f(R.ui_screen_size_loc, 960.0, 540.0);

  gl.disable(gl.DEPTH_TEST);
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

  const size: gl.Sizeiptr = @intCast(R.ui_vertex_count * @as(usize, @intCast(UiVertex.Stride)));
  gl.bufferSubData(gl.ArrayBuffer, 0, size, &R.ui_vertices);
  gl.drawArrays(gl.Triangles, 0, @intCast(R.ui_vertex_count));

  gl.bindVertexArray(0);
  gl.useProgram(0);
  gl.enable(gl.DEPTH_TEST);

  R.ui_vertex_count = 0;
}


//______________________________________
// @section Drawing
//____________________________
// Coordinates
pub const coordinates   = @import("./minirender/draw/coordinates.zig");
pub const axes          = coordinates.axes;
pub const grid          = coordinates.grid;
// Lines
pub const lines         = @import("./minirender/draw/lines.zig");
pub const point         = lines.point;
pub const line          = lines.line;
pub const thickLine     = lines.thickLine;
pub const arrow         = lines.arrow;
// Primitives
pub const primitives    = @import("./minirender/draw/primitives.zig");
pub const triangle      = primitives.triangle;
pub const plane         = primitives.plane;
pub const bounds        = primitives.bounds;
pub const circle        = primitives.circle;
pub const sphere        = primitives.sphere;
// Rotor
pub const rotor_draw    = @import("./minirender/draw/rotor.zig");
pub const rotor         = rotor_draw.rotor;
pub const rotor_basis   = rotor_draw.rotor_basis;
// Text
pub const text          = @import("./minirender/draw/text.zig");
pub const text3d        = text.text3d;
pub const text3dSized   = text.text3dSized;
pub const textScreen    = text.textScreen;
pub const vec4Label     = text.vec4Label;
// Ui
pub const ui            = @import("./minirender/draw/ui.zig");
pub const hud           = ui.hud;
// Vectors
pub const vector        = @import("./minirender/draw/vector.zig");
pub const parallelogram = vector.parallelogram;
pub const reflection    = vector.reflection;
pub const angle         = vector.angle;
pub const basis         = vector.basis;
pub const projection    = vector.projection;
pub const vec           = vector.vec;
pub const vecAt         = vector.vecAt;
pub const cross         = vector.cross;

