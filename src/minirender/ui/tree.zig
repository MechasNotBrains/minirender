//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
const std  = @import("std");
const mstd = @import("mstd");
const mui  = @import("mui");
const font5x7 = @import("./font5x7.zig");


pub const Row = struct {
  depth       :u16,
  label       :mstd.cstring,
  selected    :bool = false,
  has_children :bool = false,
};

pub const Input = struct {
  mouse_x     :f32 = 0,
  mouse_y     :f32 = 0,
  click       :bool = false,
  scroll      :f32 = 0,
  reveal      :?usize = null,
  pinned      :[]const usize = &.{},
};

pub const Result = struct {
  clicked_row :?usize = null,
  width       :f32 = 0,
  height      :f32 = 0,
};

pub const Theme = struct {
  background          :mui.Color = .create(0.12, 0.12, 0.12, 1.0),
  foreground          :mui.Color = .create(0.80, 0.80, 0.80, 1.0),
  background_selected :mui.Color = .create(0.25, 0.35, 0.55, 1.0),
  background_pinned   :mui.Color = .create(0.20, 0.20, 0.20, 1.0),
  fold                :mui.Color = .create(0.50, 0.50, 0.50, 1.0),
  indent_size         :f32 = 1.5,
  row_height          :f32 = 2.0,
  padding             :f32 = 0.3,
  padding_x           :f32 = 1.0,
};

pub const Type = struct {
  scroll_offset :f32 = 0,
  folded        :mstd.seq(u32),

  pub fn create (A :std.mem.Allocator) Type {
    return .{ .folded = .create_empty(A) };
  }

  pub fn destroy (tree :*Type) void {
    tree.folded.destroy();
  }

  pub fn is_folded (tree :*const Type, row_index :usize) bool {
    const index :u32 = @intCast(row_index);
    for (tree.folded.data()) |entry| {
      if (entry == index) return true;
    }
    return false;
  }

  pub fn toggle_fold (tree :*Type, row_index :usize) void {
    const index :u32 = @intCast(row_index);
    for (tree.folded.data(), 0..) |entry, position| {
      if (entry != index) continue;
      tree.folded.remove(position);
      return;
    }
    tree.folded.add_one(index) catch {};
  }

  pub fn unfold (tree :*Type, row_index :usize) void {
    const index :u32 = @intCast(row_index);
    for (tree.folded.data(), 0..) |entry, position| {
      if (entry != index) continue;
      tree.folded.remove(position);
      return;
    }
  }

  pub fn visible_rows (
      tree :*const Type,
      rows :[]const Row,
      buffer :*mstd.seq(usize),
    ) void {
    buffer.clear();
    var skip_below :u16 = std.math.maxInt(u16);
    for (rows, 0..) |row, index| {
      if (row.depth > skip_below) continue;
      skip_below = std.math.maxInt(u16);
      buffer.add_one(index) catch return;
      if (row.has_children and tree.is_folded(index))
        skip_below = row.depth;
    }
  }

  pub fn draw (
      tree         :*Type,
      scene        :*mui.Scene,
      rows         :[]const Row,
      visible      :[]const usize,
      anchor_x     :f32,
      anchor_y     :f32,
      max_height   :f32,
      aspect_ratio :f32,
      input        :Input,
      theme        :Theme,
    ) Result {
    if (visible.len == 0) return .{};

    const dot_height = theme.row_height / 9.0;
    const dot_width = dot_height / aspect_ratio;
    const char_advance = 6.0 * dot_width;
    const fold_marker_width = char_advance * 2.0;
    const text_offset_y = (theme.row_height - 7.0 * dot_height) / 2.0;

    var max_text_width :f32 = 0;
    for (visible) |row_index| {
      const row = rows[row_index];
      const indent = @as(f32, @floatFromInt(row.depth)) * theme.indent_size;
      const label_width = @as(f32, @floatFromInt(row.label.len)) * char_advance;
      const total = indent + fold_marker_width + label_width;
      if (total > max_text_width) max_text_width = total;
    }

    const panel_width = max_text_width + 2.0 * theme.padding_x;
    const visible_count :f32 = @floatFromInt(visible.len);
    const content_height = visible_count * theme.row_height;
    const panel_height = @min(content_height + 2.0 * theme.padding, max_height);
    const panel_x = anchor_x - panel_width;
    const panel_y = anchor_y;

    const inside_panel = input.mouse_x >= panel_x and input.mouse_x < anchor_x
      and input.mouse_y >= panel_y and input.mouse_y < panel_y + panel_height;

    if (inside_panel and input.scroll != 0) {
      tree.scroll_offset -= input.scroll * theme.row_height * 3.0;
    }

    const area_top = panel_y + theme.padding;
    const area_bottom = panel_y + panel_height - theme.padding;

    if (input.reveal) |reveal_row| {
      const reveal_pinned_height = @as(f32, @floatFromInt(input.pinned.len)) * theme.row_height;
      for (visible, 0..) |row_index, draw_index| {
        if (row_index != reveal_row) continue;
        const target_y = @as(f32, @floatFromInt(draw_index)) * theme.row_height;
        if (target_y - tree.scroll_offset < reveal_pinned_height) {
          tree.scroll_offset = @max(target_y - reveal_pinned_height, 0);
        } else if (target_y + theme.row_height - tree.scroll_offset > area_bottom - area_top) {
          tree.scroll_offset = target_y + theme.row_height - (area_bottom - area_top);
        }
        break;
      }
    }

    var pinned_count :usize = 0;
    for (input.pinned) |pinned_row| {
      var found :?usize = null;
      for (visible, 0..) |row_index, draw_index| {
        if (row_index != pinned_row) continue;
        found = draw_index;
        break;
      }
      const draw_index = found orelse break;
      const flow_y = area_top + @as(f32, @floatFromInt(draw_index)) * theme.row_height - tree.scroll_offset;
      const slot_y = area_top + @as(f32, @floatFromInt(pinned_count)) * theme.row_height;
      if (flow_y >= slot_y) break;
      pinned_count += 1;
    }
    const pinned_height = @as(f32, @floatFromInt(pinned_count)) * theme.row_height;
    const scroll_top = area_top + pinned_height;
    const scroll_span = area_bottom - scroll_top;

    const max_scroll = @max(content_height - scroll_span, 0);
    tree.scroll_offset = @max(0, @min(tree.scroll_offset, max_scroll));

    scene.add(.{
      .transform = .create(panel_x, panel_y, panel_width, panel_height),
      .color     = theme.background,
      .kind      = .square,
    }) catch return .{};

    var result = Result{
      .width  = panel_width,
      .height = panel_height,
    };

    const context = RowContext{
      .panel_x           = panel_x,
      .panel_width       = panel_width,
      .dot_width         = dot_width,
      .dot_height        = dot_height,
      .char_advance      = char_advance,
      .fold_marker_width = fold_marker_width,
      .text_offset_y     = text_offset_y,
      .inside_panel      = inside_panel,
    };

    for (visible, 0..) |row_index, draw_index| {
      const row_y = area_top + @as(f32, @floatFromInt(draw_index)) * theme.row_height - tree.scroll_offset;
      if (row_y < scroll_top) continue;
      if (row_y + theme.row_height > area_bottom) continue;
      tree.row_draw(scene, rows[row_index], row_index, row_y, null, context, input, theme, &result);
    }

    for (input.pinned[0..pinned_count], 0..) |pinned_row, pinned_index| {
      if (pinned_row >= rows.len) continue;
      const row_y = area_top + @as(f32, @floatFromInt(pinned_index)) * theme.row_height;
      tree.row_draw(scene, rows[pinned_row], pinned_row, row_y, theme.background_pinned, context, input, theme, &result);
    }

    return result;
  }

  const RowContext = struct {
    panel_x           :f32,
    panel_width       :f32,
    dot_width         :f32,
    dot_height        :f32,
    char_advance      :f32,
    fold_marker_width :f32,
    text_offset_y     :f32,
    inside_panel      :bool,
  };

  fn row_draw (
      tree       :*Type,
      scene      :*mui.Scene,
      row        :Row,
      row_index  :usize,
      row_y      :f32,
      background :?mui.Color,
      context    :RowContext,
      input      :Input,
      theme      :Theme,
      result     :*Result,
    ) void {
    if (background) |color| {
      scene.add(.{
        .transform = .create(context.panel_x, row_y, context.panel_width, theme.row_height),
        .color     = color,
        .kind      = .square,
      }) catch return;
    } else if (row.selected) {
      scene.add(.{
        .transform = .create(context.panel_x, row_y, context.panel_width, theme.row_height),
        .color     = theme.background_selected,
        .kind      = .square,
      }) catch return;
    }

    const indent = @as(f32, @floatFromInt(row.depth)) * theme.indent_size;
    const row_hit = context.inside_panel and input.mouse_y >= row_y and input.mouse_y < row_y + theme.row_height;

    var text_x = context.panel_x + theme.padding_x + indent;
    const text_y = row_y + context.text_offset_y;

    if (row.has_children) {
      const folded = tree.is_folded(row_index);
      const marker :mstd.cstring = if (folded) "+" else "-";
      if (row_hit and input.click and input.mouse_x < text_x + context.fold_marker_width) {
        tree.toggle_fold(row_index);
      } else if (row_hit and input.click) {
        result.clicked_row = row_index;
      }
      draw_label(scene, marker, text_x, text_y, context.dot_width, context.dot_height, context.char_advance, theme.fold);
    } else {
      if (row_hit and input.click) {
        result.clicked_row = row_index;
      }
    }
    text_x += context.fold_marker_width;

    draw_label(scene, row.label, text_x, text_y, context.dot_width, context.dot_height, context.char_advance, theme.foreground);
  }
};

fn draw_label (
    scene        :*mui.Scene,
    text         :mstd.cstring,
    start_x      :f32,
    start_y      :f32,
    dot_width    :f32,
    dot_height   :f32,
    char_advance :f32,
    color        :mui.Color,
  ) void {
  var cursor_x = start_x;
  for (text) |character| {
    const glyph = font5x7.lookup(character);
    for (0..7) |glyph_row| {
      for (0..5) |column| {
        if (!glyph.pixel(column, glyph_row)) continue;
        scene.add(.{
          .transform = .create(
            cursor_x + @as(f32, @floatFromInt(column)) * dot_width,
            start_y + @as(f32, @floatFromInt(glyph_row)) * dot_height,
            dot_width,
            dot_height,
          ),
          .color = color,
          .kind  = .square,
        }) catch return;
      }
    }
    cursor_x += char_advance;
  }
}
