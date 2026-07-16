//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps std
const std = @import("std");
// @deps debug.types
const Vec4          = @import("./math/vector.zig").Vec4;
const BiVec         = @import("./math/vector.zig").BiVec;
const mat4Ortho     = @import("./math/matrix.zig").mat4Ortho;
const mat4_identity = @import("./math/matrix.zig").mat4_identity;
// @deps debug.ui
const gl       = @import("./lib/opengl.zig");
const Color    = @import("./color.zig").Color;
const Renderer = @import("../minirender.zig").Renderer;


// @note Vertex moved to minirender/vertex.zig

/// Ui Vertex layout
pub const UiVertex = struct {
  screen_x :f32,  screen_y :f32,
  local_x  :f32,  local_y  :f32,
  half_w   :f32,  half_h   :f32,
  radius   :f32,
  fill_r   :f32,  fill_g :f32,  fill_b :f32,  fill_a :f32,
  border_r :f32,  border_g :f32,  border_b :f32,  border_a :f32,
  mode     :f32,
  fill_ratio :f32,
  pub const Stride :gl.Sizei = @sizeOf(@This());
};



//============================================================
// UI System — comptime-generated parameter sliders
//============================================================

pub const ParamKind = enum { float, vec3, bivec };

const UiRect = struct { x: f32, y: f32, w: f32, h: f32 };

const UiStyle = struct {
  const panel_padding  :f32 = 10;
  const spacing        :f32 = 4;
  const slider_width   :f32 = 150;
  const slider_height  :f32 = 14;
  const label_height   :f32 = 16;
  const knob_width     :f32 = 8;
  const outer_radius   :f32 = 6;
  const inner_radius   :f32 = 6 - 4;
  const group_gap      :f32 = 6;
  const panel_margin   :f32 = 8;

  const panel_bg     = Color{ .r = 0.12, .g = 0.12, .b = 0.14, .a = 0.85 };
  const shadow_color = Color{ .r = 0.0,  .g = 0.0,  .b = 0.0,  .a = 0.4 };
  const track_bg     = Color{ .r = 0.2,  .g = 0.2,  .b = 0.22, .a = 1.0 };
  const knob_color   = Color{ .r = 0.9,  .g = 0.9,  .b = 0.9,  .a = 1.0 };

  const component_colors = [3]Color{
    .{ .r = 0.9, .g = 0.3, .b = 0.3, .a = 1.0 },
    .{ .r = 0.3, .g = 0.9, .b = 0.3, .a = 1.0 },
    .{ .r = 0.3, .g = 0.5, .b = 0.9, .a = 1.0 },
  };
};

fn paramComponents (comptime kind: anytype) usize {
  const as_enum: ParamKind = kind;
  return switch (as_enum) { .float => 1, .vec3, .bivec => 3 };
}

fn countSliders (comptime spec: anytype) usize {
  comptime var count: usize = 0;
  inline for (spec) |param| {
    count += comptime paramComponents(param.kind);
  }
  return count;
}

fn sliderIndex (comptime spec: anytype, comptime name: []const u8) usize {
  comptime var index: usize = 0;
  inline for (spec) |param| {
    if (comptime std.mem.eql(u8, param.name, name)) return index;
    index += comptime paramComponents(param.kind);
  }
  @compileError("Unknown parameter name: " ++ name);
}

pub fn Ui (comptime spec: anytype) type {
  const slider_count = comptime countSliders(spec);

  return struct {
    const Self = @This();

    values     :[slider_count]f32,
    min_values :[slider_count]f32,
    max_values :[slider_count]f32,
    active     :?usize = null,

    pub fn init () Self {
      var result: Self = undefined;
      result.active = null;
      comptime var idx: usize = 0;
      inline for (spec) |param| {
        const components = comptime paramComponents(param.kind);
        if (components == 1) {
          result.values[idx]     = param.default_val;
          result.min_values[idx] = param.min;
          result.max_values[idx] = param.max;
          idx += 1;
        } else {
          inline for (0..3) |comp| {
            result.values[idx]     = param.default_val[comp];
            result.min_values[idx] = param.min;
            result.max_values[idx] = param.max;
            idx += 1;
          }
        }
      }
      return result;
    }

    pub fn getFloat (self: *const Self, comptime name: []const u8) f32 {
      const idx = comptime sliderIndex(spec, name);
      return self.values[idx];
    }

    pub fn getVec3 (self: *const Self, comptime name: []const u8) Vec4 {
      const base = comptime sliderIndex(spec, name);
      return Vec4.dir(self.values[base], self.values[base + 1], self.values[base + 2]);
    }

    pub fn getBivec (self: *const Self, comptime name: []const u8) BiVec {
      const base = comptime sliderIndex(spec, name);
      return .{ .xy = self.values[base], .xz = self.values[base + 1], .yz = self.values[base + 2] };
    }

    fn sliderTrackRect (slider_idx: usize) UiRect {
      const panel_x = 960.0 - UiStyle.panel_margin - UiStyle.panel_padding * 2 - UiStyle.slider_width;
      var cursor_y = UiStyle.panel_margin + UiStyle.panel_padding;
      comptime var idx: usize = 0;
      inline for (spec) |param| {
        cursor_y += UiStyle.label_height + UiStyle.spacing;
        const components = comptime paramComponents(param.kind);
        inline for (0..components) |_| {
          if (idx == slider_idx) {
            return .{
              .x = panel_x + UiStyle.panel_padding,
              .y = cursor_y,
              .w = UiStyle.slider_width,
              .h = UiStyle.slider_height,
            };
          }
          cursor_y += UiStyle.slider_height + UiStyle.spacing;
          idx += 1;
        }
        cursor_y += UiStyle.group_gap;
      }
      return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    }

    pub fn update (self: *Self, renderer: *Renderer) void {
      const mx = renderer.mouse_x;
      const my = renderer.mouse_y;

      const panel_rect = Self.panelRect();
      const panel_hit = mx >= panel_rect.x and mx <= panel_rect.x + panel_rect.w
                    and my >= panel_rect.y and my <= panel_rect.y + panel_rect.h;

      renderer.ui_captured = panel_hit or self.active != null;

      if (renderer.mouse_down and self.active == null and panel_hit) {
        inline for (0..slider_count) |idx| {
          const track = Self.sliderTrackRect(idx);
          if (mx >= track.x and mx <= track.x + track.w
            and my >= track.y and my <= track.y + track.h)
          {
            self.active = idx;
            break;
          }
        }
      }

      if (self.active) |idx| {
        if (renderer.mouse_down) {
          const track = Self.sliderTrackRect(idx);
          const normalized = std.math.clamp((mx - track.x) / track.w, 0.0, 1.0);
          self.values[idx] = self.min_values[idx] + normalized * (self.max_values[idx] - self.min_values[idx]);
        } else {
          self.active = null;
        }
      }

      if (!renderer.mouse_down) {
        renderer.camera.dragging = false;
      }
    }

    fn panelRect () UiRect {
      const panel_w = UiStyle.slider_width + UiStyle.panel_padding * 2;
      const panel_x = 960.0 - UiStyle.panel_margin - panel_w;
      var panel_h: f32 = UiStyle.panel_padding;
      inline for (spec) |param| {
        panel_h += UiStyle.label_height + UiStyle.spacing;
        const components: f32 = @floatFromInt(comptime paramComponents(param.kind));
        panel_h += components * (UiStyle.slider_height + UiStyle.spacing);
        panel_h += UiStyle.group_gap;
      }
      panel_h += UiStyle.panel_padding;
      return .{ .x = panel_x, .y = UiStyle.panel_margin, .w = panel_w, .h = panel_h };
    }

    pub fn draw (self: *const Self, renderer: *Renderer) void {
      const panel = Self.panelRect();

      // Shadow
      renderer.push_rect_ui(
        panel.x + 3, panel.y + 3, panel.w, panel.h,
        UiStyle.outer_radius, UiStyle.shadow_color, UiStyle.shadow_color, 0, 0,
      );
      // Panel background
      renderer.push_rect_ui(
        panel.x, panel.y, panel.w, panel.h,
        UiStyle.outer_radius, UiStyle.panel_bg, UiStyle.panel_bg, 0, 0,
      );

      var cursor_y = panel.y + UiStyle.panel_padding;
      comptime var idx: usize = 0;

      inline for (spec) |param| {
        // Label — rendered as screen-space bitfont via the 3D text pipeline
        cursor_y += UiStyle.label_height + UiStyle.spacing;

        const components = comptime paramComponents(param.kind);
        inline for (0..components) |comp| {
          const track_x = panel.x + UiStyle.panel_padding;
          const track_y = cursor_y;
          const normalized = (self.values[idx] - self.min_values[idx])
                           / (self.max_values[idx] - self.min_values[idx]);

          const fill_color = if (components > 1)
            UiStyle.component_colors[comp]
          else
            Color{ .r = 0.5, .g = 0.7, .b = 0.9, .a = 1.0 };

          // Track background + fill
          renderer.push_rect_ui(
            track_x, track_y, UiStyle.slider_width, UiStyle.slider_height,
            UiStyle.inner_radius, fill_color, UiStyle.track_bg, 1.0, normalized,
          );

          // Knob
          const knob_x = track_x + normalized * (UiStyle.slider_width - UiStyle.knob_width);
          const knob_color = if (self.active != null and self.active.? == idx)
            Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 }
          else
            UiStyle.knob_color;
          renderer.push_rect_ui(
            knob_x, track_y, UiStyle.knob_width, UiStyle.slider_height,
            UiStyle.slider_height * 0.5, knob_color, knob_color, 0, 0,
          );

          cursor_y += UiStyle.slider_height + UiStyle.spacing;
          idx += 1;
        }
        cursor_y += UiStyle.group_gap;
      }
      renderer.ui_flush();

      // Labels via existing bitfont in screen space
      Self.drawLabels(self, renderer, panel);
    }

    fn drawLabels (_: *const Self, renderer: *Renderer, panel: UiRect) void {
      // Save current 3D state
      const saved_wvp        = renderer.wvp;
      const saved_view       = renderer.view;
      const saved_line_count = renderer.line_count;
      const saved_tri_count  = renderer.tri_count;
      renderer.line_count    = 0;
      renderer.tri_count     = 0;

      // Orthographic projection for screen-space text
      renderer.wvp  = mat4Ortho(960.0, 540.0);
      renderer.view = mat4_identity;

      var cursor_y = panel.y + UiStyle.panel_padding;
      inline for (spec) |param| {
        const label_x = panel.x + UiStyle.panel_padding;
        renderer.textScreen(label_x, cursor_y + 2, param.name, Color.white, 2.0);
        cursor_y += UiStyle.label_height + UiStyle.spacing;
        const components :f32= @floatFromInt(comptime paramComponents(param.kind));
        cursor_y += components * (UiStyle.slider_height + UiStyle.spacing);
        cursor_y += UiStyle.group_gap;
      }

      // Flush the text as screen-space triangles
      if (renderer.tri_count > 0) {
        gl.useProgram(renderer.program);
        gl.bindVertexArray(renderer.vao);
        gl.bindBuffer(gl.ArrayBuffer, renderer.vbo);
        //__________________________________________________________
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.False, Vertex.Stride, @ptrFromInt(0));
        // Location 1: aCol (4 floats)
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 4, gl.FLOAT, gl.False, Vertex.Stride, @ptrFromInt(3 * @sizeOf(f32)));
        // Clean up any lingering active UI layout slots so they don't break state
        gl.disableVertexAttribArray(2);
        gl.disableVertexAttribArray(3);
        gl.disableVertexAttribArray(4);
        gl.disableVertexAttribArray(5);
        gl.disableVertexAttribArray(6);
        gl.disableVertexAttribArray(7);
        //__________________________________________________________
        var ortho = renderer.wvp;
        gl.uniformMatrix4fv(renderer.wvp_loc, 1, gl.False, &ortho);
        gl.disable(gl.DEPTH_TEST);
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        const text_size: gl.Sizeiptr = @intCast(renderer.tri_count * Vertex.Stride);
        gl.bufferSubData(gl.ArrayBuffer, 0, text_size, &renderer.tri_vertices);
        gl.drawArrays(gl.Triangles, 0, @intCast(renderer.tri_count));
        gl.bindVertexArray(0);
        gl.useProgram(0);
        gl.enable(gl.DEPTH_TEST);
      }

      // Restore state
      renderer.wvp        = saved_wvp;
      renderer.view       = saved_view;
      renderer.line_count = saved_line_count;
      renderer.tri_count  = saved_tri_count;
    }
  };
}

