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
pub const gl = @import("./minirender/lib/opengl.zig");
const glfw = @import("./minirender/lib/glfw.zig");
// @deps minirender.ui
const Vertex    = @import("./minirender/ui.zig").Vertex;
const UiVertex  = @import("./minirender/ui.zig").UiVertex;
const font      = @import("./minirender/font.zig");
pub const Ui    = @import("./minirender/ui.zig").Ui;


// @note Math forward exports moved to minirender/math.zig (re-exports from mmath)
// @note Camera moved to mcam
// @note Color moved to minirender/color.zig


//______________________________________
// @section Shaders
//____________________________
const ui_vert_src = @import("./minirender/shaders.zig").ui_vert_src;
const ui_frag_src = @import("./minirender/shaders.zig").ui_frag_src;


//______________________________________
// @section Limits
//____________________________
pub const MAX_VERTICES    = 64 * 1024;
pub const BUFFER_SIZE     = MAX_VERTICES * Vertex.Stride;
pub const UI_MAX_VERTICES = 1024;
pub const UI_BUFFER_SIZE  = UI_MAX_VERTICES * UiVertex.Stride;


//______________________________________
// @section Object Fields
//____________________________
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

// Rendering options
polygon_offset_factor :f32 = 0,
polygon_offset_units  :f32 = 0,

// Frame timing
frame_start :f64 = 0,
frame_ms    :f32 = 0,
frame_fps   :f32 = 0,


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

  R.line_count = 0;
  R.tri_count  = 0;
  R.text_count = 0;
}
//__________________
pub fn end (R: *Renderer) void {
  gl.useProgram(R.program);
  gl.bindVertexArray(R.vao);
  gl.bindBuffer(gl.ArrayBuffer, R.vbo);

  var m: [16]f32 = undefined;
  for (0..16) |matrix_index| {
    m[matrix_index] = @floatCast(R.wvp.data[matrix_index]);
  }
  gl.uniformMatrix4fv(R.wvp_loc, 1, gl.False, &m);

  gl.enable(gl.DEPTH_TEST);
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

  // Flush triangles
  if (R.tri_count > 0) {
    if (R.polygon_offset_factor != 0 or R.polygon_offset_units != 0) {
      gl.enable(gl.POLYGON_OFFSET_FILL);
      gl.polygonOffset(R.polygon_offset_factor, R.polygon_offset_units);
    }
    const tri_size: gl.Sizeiptr = @intCast(R.tri_count * Vertex.Stride);
    gl.bufferSubData(gl.ArrayBuffer, 0, tri_size, &R.tri_vertices);
    gl.drawArrays(gl.Triangles, 0, @intCast(R.tri_count));
    if (R.polygon_offset_factor != 0 or R.polygon_offset_units != 0) {
      gl.disable(gl.POLYGON_OFFSET_FILL);
    }
  }

  // Flush lines
  if (R.line_count > 0) {
    const line_size: gl.Sizeiptr = @intCast(R.line_count * Vertex.Stride);
    gl.bufferSubData(gl.ArrayBuffer, 0, line_size, &R.line_vertices);
    gl.drawArrays(gl.LINES, 0, @intCast(R.line_count));
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
