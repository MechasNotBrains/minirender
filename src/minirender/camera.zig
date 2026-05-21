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

yaw      :f32 = 0.6,
pitch    :f32 = 0.4,
distance :f32 = 6.0,
dragging :bool = false,
last_x   :f64 = 0,
last_y   :f64 = 0,


pub const ViewResult = struct { wvp: Mat4, view: Mat4 };

pub fn viewProjection (cam: *const Camera, aspect: f32) ViewResult {
  const cos_p = @cos(cam.pitch);
  const eye = Vec4{
    .x = cam.distance * cos_p * @cos(cam.yaw),
    .y = cam.distance * cos_p * @sin(cam.yaw),
    .z = cam.distance * @sin(cam.pitch),
    .w = 1,
  };
  const view = mat4LookAt(eye, Vec4.point(0, 0, 0), Vec4.dir(0, 0, 1));
  const proj = mat4Perspective(std.math.pi / 4.0, aspect, 0.1, 100.0);
  return .{ .wvp = mat4Mul(proj, view), .view = view };
}

pub const callback = struct {
  pub fn mouseBtn (win: ?*glfw.Window, button: c_int, action: c_int, _: c_int) callconv(.c) void {
    const renderer :*Renderer= @ptrCast(@alignCast(glfw.getUserPointer(win) orelse return));
    if (button == glfw.MouseButton.left) {
      renderer.mouse_down = action == glfw.Press;
      if (!renderer.ui_captured) {
        renderer.camera.dragging = action == glfw.Press;
      }
    }
  }

  pub fn mousePos (win: ?*glfw.Window, xpos: f64, ypos: f64) callconv(.c) void {
    const renderer :*Renderer= @ptrCast(@alignCast(glfw.getUserPointer(win) orelse return));
    renderer.mouse_x = @floatCast(xpos);
    renderer.mouse_y = @floatCast(ypos);
    if (!renderer.ui_captured) {
      const cam = &renderer.camera;
      if (cam.dragging) {
        const sensitivity :f32 = 0.005;
        const delta_x :f32= @floatCast(xpos - cam.last_x);
        const delta_y :f32= @floatCast(ypos - cam.last_y);
        cam.yaw   -= delta_x * sensitivity;
        cam.pitch  = std.math.clamp(cam.pitch + delta_y * sensitivity, -std.math.pi / 2.0 + 0.01, std.math.pi / 2.0 - 0.01);
      }
    }
    renderer.camera.last_x = xpos;
    renderer.camera.last_y = ypos;
  }

  pub fn scrollCallback (win: ?*glfw.Window, _: f64, yoffset: f64) callconv(.c) void {
    const renderer :*Renderer= @ptrCast(@alignCast(glfw.getUserPointer(win) orelse return));
    if (renderer.ui_captured) return;
    renderer.camera.distance = std.math.clamp(renderer.camera.distance - @as(f32, @floatCast(yoffset)) * 0.5, 1.0, 50.0);
  }
};

