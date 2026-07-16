//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// UI Batching
const Color    = @import("./color.zig").Color;
const Renderer = @import("../minirender.zig").Renderer;

pub const vert = struct {
  pub fn line (R :*Renderer, px :f32, py :f32, pz :f32, c :Color) void {
    if (R.line_count >= Renderer.MAX_VERTICES) return;
    R.line_vertices[R.line_count] = .{
      .x= px,  .y= py,  .z= pz,
      .r= c.r, .g= c.g, .b= c.b, .a = c.a,
    };
    R.line_count += 1;
  }

  pub fn tri (R: *Renderer, px: f32, py: f32, pz: f32, c: Color) void {
    if (R.tri_count >= Renderer.MAX_VERTICES) return;
    R.tri_vertices[R.tri_count] = .{
      .x= px,  .y= py,  .z= pz,
      .r= c.r, .g= c.g, .b= c.b, .a= c.a,
    };
    R.tri_count += 1;
  }

  pub fn text (R: *Renderer, px: f32, py: f32, pz: f32, c: Color) void {
    if (R.text_count >= Renderer.MAX_VERTICES) return;
    R.text_vertices[R.text_count] = .{
      .x= px,  .y= py,  .z= pz,
      .r= c.r, .g= c.g, .b= c.b, .a= c.a,
    };
    R.text_count += 1;
  }
};

pub const rect = struct {
  pub fn ui (
      R             : *Renderer,
      rect_x        : f32, rect_y: f32,
      rect_w        : f32, rect_h: f32,
      corner_radius : f32,
      fill_color    : Color, border_color: Color,
      mode          : f32, fill_ratio: f32,
    ) void {
    if (R.ui_vertex_count + 6 > Renderer.UI_MAX_VERTICES) return;
    const hw = rect_w * 0.5;
    const hh = rect_h * 0.5;

    const corners = [4][2]f32{
      .{ rect_x,          rect_y          },
      .{ rect_x + rect_w, rect_y          },
      .{ rect_x + rect_w, rect_y + rect_h },
      .{ rect_x,          rect_y + rect_h },
    };
    const local = [4][2]f32{
      .{ -hw, -hh }, .{  hw, -hh },
      .{  hw,  hh }, .{ -hw,  hh },
    };
    const indices = [6]usize{ 0, 1, 2, 0, 2, 3 };
    for (indices) |idx| {
      R.ui_vertices[R.ui_vertex_count] = .{
        .screen_x   = corners[idx][0], .screen_y   = corners[idx][1],
        .local_x    = local[idx][0],   .local_y    = local[idx][1],
        .half_w     = hw,              .half_h     = hh,
        .radius     = corner_radius,
        .fill_r     = fill_color.r,    .fill_g   = fill_color.g,
        .fill_b     = fill_color.b,    .fill_a   = fill_color.a,
        .border_r   = border_color.r,  .border_g = border_color.g,
        .border_b   = border_color.b,  .border_a = border_color.a,
        .mode       = mode,
        .fill_ratio = fill_ratio,
      };
      R.ui_vertex_count += 1;
    }
  }
};

