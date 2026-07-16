//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
const std = @import("std");
const mmath = @import("mmath");
const Vec4 = @import("./vector.zig").Vec4;

pub const Mat4 = mmath.matrix.Mat4;
const Float = mmath.matrix.float.Float;
pub const mat4_identity = Mat4.Identity;

pub fn mat4Mul(a: Mat4, b: Mat4) Mat4 {
  var r: [16]Float = undefined;
  for (0..4) |row| {
    for (0..4) |col| {
      var sum: Float = 0;
      for (0..4) |k| {
        sum += a.data[k * 4 + row] * b.data[col * 4 + k];
      }
      r[col * 4 + row] = sum;
    }
  }
  return .{ .data = r };
}

pub fn mat4Perspective(fov_y: Float, aspect: Float, near: Float, far: Float) Mat4 {
  const f = 1.0 / @tan(fov_y * 0.5);
  const nf = 1.0 / (near - far);
  return Mat4.create(
    f / aspect, 0, 0,                   0,
    0,          f, 0,                   0,
    0,          0, (far + near) * nf,   -1,
    0,          0, 2.0 * far * near * nf, 0,
  );
}

pub fn mat4LookAt(eye: Vec4, center: Vec4, up: Vec4) Mat4 {
  const fx :Float = center.x - eye.x;
  const fy :Float = center.y - eye.y;
  const fz :Float = center.z - eye.z;
  const fl = @sqrt(fx * fx + fy * fy + fz * fz);
  const f_x = fx / fl;
  const f_y = fy / fl;
  const f_z = fz / fl;

  const sx :Float = f_y * up.z - f_z * up.y;
  const sy :Float = f_z * up.x - f_x * up.z;
  const sz :Float = f_x * up.y - f_y * up.x;
  const sl = @sqrt(sx * sx + sy * sy + sz * sz);
  const s_x = sx / sl;
  const s_y = sy / sl;
  const s_z = sz / sl;

  const u_x = s_y * f_z - s_z * f_y;
  const u_y = s_z * f_x - s_x * f_z;
  const u_z = s_x * f_y - s_y * f_x;

  return Mat4.create(
    s_x,  u_x,  -f_x, 0,
    s_y,  u_y,  -f_y, 0,
    s_z,  u_z,  -f_z, 0,
    -(s_x * eye.x + s_y * eye.y + s_z * eye.z),
    -(u_x * eye.x + u_y * eye.y + u_z * eye.z),
    f_x * eye.x + f_y * eye.y + f_z * eye.z,
    1,
  );
}

pub fn mat4Ortho(width: Float, height: Float) Mat4 {
  return Mat4.create(
    2.0 / width, 0,             0, 0,
    0,           -2.0 / height, 0, 0,
    0,            0,           -1, 0,
   -1.0,          1.0,          0, 1,
  );
}
