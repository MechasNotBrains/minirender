//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps std
const std = @import("std");
// @deps debug.renderer
const Vec4     = @import("../math/vector.zig").Vec4;
const Color    = @import("../color.zig").Color;
const Renderer = @import("../../minirender.zig").Renderer;


pub fn hud (R: *Renderer) void {
  var ms_buf  :[32]u8= undefined;
  var fps_buf :[32]u8= undefined;
  const ms_text  = std.fmt.bufPrint(&ms_buf,  "{d:.3}ms",  .{R.frame_ms})  catch "?ms";
  const fps_text = std.fmt.bufPrint(&fps_buf, "{d:.0}fps", .{R.frame_fps}) catch "?fps";

  const cam   = &R.camera;
  const cos_p = @cos(cam.pitch);
  const eye   = Vec4{
    .x = cam.distance * cos_p * @cos(cam.yaw),
    .y = cam.distance * cos_p * @sin(cam.yaw),
    .z = cam.distance * @sin(cam.pitch),
  };
  const forward  = eye.normalize().neg();
  const world_up = Vec4.dir(0, 0, 1);
  const right    = Vec4.cross(forward, world_up).normalize();
  const up       = Vec4.cross(right, forward).normalize();

  const corner = eye
    .add(forward.scale(0.3))
    .add(right.scale(0.18))
    .add(up.scale(-0.10));
  const ms_pos  = corner.add(right.scale(-0.022));
  const fps_pos = corner.add(up.scale(-0.013));

  R.text3dSized(ms_pos, ms_text, Color.dark_gray, 0.0016);
  R.text3dSized(fps_pos, fps_text, Color.dark_gray, 0.001);
}

