//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const Camera = @This();
// @deps std
const std = @import("std");
// @deps debug.types
const Vec4            = @import("./math/vector.zig").Vec4;
const Mat4            = @import("./math/matrix.zig").Mat4;
const mat4LookAt      = @import("./math/matrix.zig").mat4LookAt;
const mat4Perspective = @import("./math/matrix.zig").mat4Perspective;
const mat4Mul         = @import("./math/matrix.zig").mat4Mul;
// @deps debug.ui
const glfw     = @import("./lib/glfw.zig");
const Renderer = @import("../minirender.zig").Renderer;

position          :Vec4 = .{ .x = 3, .y = -3, .z = 2, .w = 1 },
yaw               :f32 = 0.6,
pitch             :f32 = 0.4,
move_speed        :f32 = 5.0,
mouse_sensitivity :f32 = 0.002,
scroll_speed_factor    :f32 = 1.2,
scroll_move_multiplier :f32 = 4.0,
near              :f32 = 0.1,
far               :f32 = 100.0,

bind_forward      :c_int = glfw.Key.w,
bind_backward     :c_int = glfw.Key.r,
bind_left         :c_int = glfw.Key.a,
bind_right        :c_int = glfw.Key.s,
bind_up           :c_int = glfw.Key.space,
bind_shift        :[2]c_int = .{ glfw.Key.left_shift, glfw.Key.right_shift },

right_mouse_down  :bool = false,
key_forward       :bool = false,
key_backward      :bool = false,
key_left          :bool = false,
key_right         :bool = false,
key_up            :bool = false,
key_shift         :bool = false,
mouse_delta_x     :f32 = 0,
mouse_delta_y     :f32 = 0,
last_x            :f64 = 0,
last_y            :f64 = 0,


pub const ViewResult = struct { wvp: Mat4, view: Mat4 };

pub fn viewProjection (cam: *const Camera, aspect: f32) ViewResult {
  const cos_pitch = @cos(cam.pitch);
  const target = Vec4{
    .x = cam.position.x + cos_pitch * @sin(cam.yaw),
    .y = cam.position.y + cos_pitch * @cos(cam.yaw),
    .z = cam.position.z + @sin(cam.pitch),
    .w = 1,
  };
  const view = mat4LookAt(cam.position, target, Vec4.dir(0, 0, 1));
  const proj = mat4Perspective(std.math.pi / 4.0, aspect, cam.near, cam.far);
  return .{ .wvp = mat4Mul(proj, view), .view = view };
}

pub fn update (cam: *Camera, delta_time: f32) void {
  if (cam.right_mouse_down) {
    cam.yaw += cam.mouse_delta_x * cam.mouse_sensitivity;
    cam.pitch = std.math.clamp(
      cam.pitch - cam.mouse_delta_y * cam.mouse_sensitivity,
      -std.math.pi / 2.0 + 0.01,
      std.math.pi / 2.0 - 0.01,
    );
  }
  cam.mouse_delta_x = 0;
  cam.mouse_delta_y = 0;

  var forward_amount: f32 = 0;
  var right_amount: f32 = 0;
  var vertical_amount: f32 = 0;
  if (cam.key_forward)  forward_amount += 1;
  if (cam.key_backward) forward_amount -= 1;
  if (cam.key_left)     right_amount -= 1;
  if (cam.key_right)    right_amount += 1;
  if (cam.key_up and !cam.key_shift) vertical_amount += 1;
  if (cam.key_up and cam.key_shift)  vertical_amount -= 1;

  const speed = cam.move_speed * delta_time;
  const sin_yaw = @sin(cam.yaw);
  const cos_yaw = @cos(cam.yaw);

  cam.position.x += (forward_amount * sin_yaw + right_amount * cos_yaw) * speed;
  cam.position.y += (forward_amount * cos_yaw - right_amount * sin_yaw) * speed;
  cam.position.z += vertical_amount * speed;
}


pub const callback = struct {
  pub fn key (win: ?*glfw.Window, pressed_key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = scancode;
    _ = mods;
    if (pressed_key == glfw.Key.escape and (action == glfw.Press or action == glfw.Release)) {
      glfw.window.setClose(win, glfw.True);
      return;
    }
    const renderer :*Renderer= @ptrCast(@alignCast(glfw.getUserPointer(win) orelse return));
    const cam = &renderer.camera;
    const pressed = action == glfw.Press or action == glfw.Repeat;
    if (pressed_key == cam.bind_forward)  cam.key_forward  = pressed;
    if (pressed_key == cam.bind_backward) cam.key_backward = pressed;
    if (pressed_key == cam.bind_left)     cam.key_left     = pressed;
    if (pressed_key == cam.bind_right)    cam.key_right    = pressed;
    if (pressed_key == cam.bind_up)       cam.key_up       = pressed;
    if (pressed_key == cam.bind_shift[0] or pressed_key == cam.bind_shift[1]) cam.key_shift = pressed;
  }

  pub fn mouseBtn (win: ?*glfw.Window, button: c_int, action: c_int, _: c_int) callconv(.c) void {
    const renderer :*Renderer= @ptrCast(@alignCast(glfw.getUserPointer(win) orelse return));
    if (button == glfw.MouseButton.left) {
      renderer.mouse_down = action == glfw.Press;
    }
    if (button == glfw.MouseButton.right) {
      renderer.camera.right_mouse_down = action == glfw.Press;
      if (action == glfw.Press) {
        glfw.setInputMode(win, glfw.Cursor.Mode, glfw.Cursor.Disabled);
      } else {
        glfw.setInputMode(win, glfw.Cursor.Mode, glfw.Cursor.Normal);
      }
    }
  }

  pub fn mousePos (win: ?*glfw.Window, xpos: f64, ypos: f64) callconv(.c) void {
    const renderer :*Renderer= @ptrCast(@alignCast(glfw.getUserPointer(win) orelse return));
    renderer.mouse_x = @floatCast(xpos);
    renderer.mouse_y = @floatCast(ypos);
    const cam = &renderer.camera;
    if (cam.right_mouse_down) {
      cam.mouse_delta_x += @as(f32, @floatCast(xpos - cam.last_x));
      cam.mouse_delta_y += @as(f32, @floatCast(ypos - cam.last_y));
    }
    cam.last_x = xpos;
    cam.last_y = ypos;
  }

  pub fn scrollCallback (win: ?*glfw.Window, _: f64, yoffset: f64) callconv(.c) void {
    const renderer :*Renderer= @ptrCast(@alignCast(glfw.getUserPointer(win) orelse return));
    if (renderer.ui_captured) return;
    const cam = &renderer.camera;
    const direction: f32 = if (yoffset > 0) 1.0 else -1.0;

    if (cam.key_shift) {
      if (direction > 0) {
        cam.move_speed *= cam.scroll_speed_factor;
      } else {
        cam.move_speed /= cam.scroll_speed_factor;
      }
      cam.move_speed = @max(1.0, cam.move_speed);
    } else {
      const distance = cam.move_speed * cam.scroll_move_multiplier * 0.016;
      const sin_yaw = @sin(cam.yaw);
      const cos_yaw = @cos(cam.yaw);
      cam.position.x += sin_yaw * direction * distance;
      cam.position.y += cos_yaw * direction * distance;
    }
  }
};
