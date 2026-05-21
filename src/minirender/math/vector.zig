//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// @deps std
const std = @import("std");

pub const vec4 = Vec4.create;
pub const Vec4 = struct {
  x :f32= 0,  y :f32= 0,  z :f32= 0,  w :f32= 0,

  pub fn create (x: f32, y: f32, z: f32, w: f32) Vec4 {
    return .{ .x = x, .y = y, .z = z, .w = w };
  }

  pub fn point(x: f32, y: f32, z: f32) Vec4 {
    return .{ .x = x, .y = y, .z = z, .w = 1 };
  }

  pub fn dir(x: f32, y: f32, z: f32) Vec4 {
    return .{ .x = x, .y = y, .z = z, .w = 0 };
  }

  pub fn arr(self: Vec4) [4]f32 {
    return .{ self.x, self.y, self.z, self.w };
  }

  pub fn add (a: Vec4, b: Vec4) Vec4 {
    return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z, .w = a.w + b.w };
  }

  pub fn sub (a: Vec4, b: Vec4) Vec4 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z, .w = a.w - b.w };
  }

  pub fn scale (a: Vec4, s: f32) Vec4 {
    return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s, .w = a.w * s };
  }

  pub fn dot (a: Vec4, b: Vec4) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
  }

  pub fn cross (a: Vec4, b: Vec4) Vec4 {
    return .{
      .x = a.y * b.z - a.z * b.y,
      .y = a.z * b.x - a.x * b.z,
      .z = a.x * b.y - a.y * b.x,
    };
  }

  pub fn len (a: Vec4) f32 {
    return @sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
  }

  pub fn normalize (a: Vec4) Vec4 {
    const length = a.len();
    if (length < 1e-6) return Vec4{};
    return .{ .x = a.x / length, .y = a.y / length, .z = a.z / length, .w = a.w };
  }

  pub fn neg (a: Vec4) Vec4 {
    return .{ .x = -a.x, .y = -a.y, .z = -a.z, .w = -a.w };
  }

  pub fn project (a: Vec4, onto: Vec4) Vec4 {
    const d = Vec4.dot(a, onto);
    const len_sq = Vec4.dot(onto, onto);
    if (len_sq < 1e-9) return Vec4{};
    return onto.scale(d / len_sq);
  }

  pub fn reject (a: Vec4, from: Vec4) Vec4 {
    return a.sub(a.project(from));
  }

  pub fn angle_between (a: Vec4, b: Vec4) f32 {
    const al = a.len();
    const bl = b.len();
    if (al < 1e-6 or bl < 1e-6) return 0;
    const d = Vec4.dot(a, b) / (al * bl);
    return std.math.acos(std.math.clamp(d, -1.0, 1.0));
  }

  pub fn lerp (a: Vec4, b: Vec4, t: f32) Vec4 {
    return a.add(b.sub(a).scale(t));
  }

  pub fn wedge (a: Vec4, b: Vec4) BiVec {
    return .{
      .xy = a.x * b.y - b.x * a.y,
      .xz = a.x * b.z - b.x * a.z,
      .yz = a.y * b.z - b.y * a.z,
    };
  }

  pub fn reflect (v: Vec4, a: Vec4) Vec4 {
    const d = 2.0 * Vec4.dot(v, a);
    return .{
      .x = v.x - d * a.x,
      .y = v.y - d * a.y,
      .z = v.z - d * a.z,
      .w = v.w,
    };
  }
};


pub const BiVec = struct {
  xy :f32 = 0,
  xz :f32 = 0,
  yz :f32 = 0,

  pub fn add (a: BiVec, b: BiVec) BiVec {
    return .{ .xy = a.xy + b.xy, .xz = a.xz + b.xz, .yz = a.yz + b.yz };
  }

  pub fn scale (a: BiVec, s: f32) BiVec {
    return .{ .xy = a.xy * s, .xz = a.xz * s, .yz = a.yz * s };
  }

  pub fn neg (a: BiVec) BiVec {
    return .{ .xy = -a.xy, .xz = -a.xz, .yz = -a.yz };
  }

  pub fn len (a: BiVec) f32 {
    return @sqrt(a.xy * a.xy + a.xz * a.xz + a.yz * a.yz);
  }

  pub fn normalize (a: BiVec) BiVec {
    const length = a.len();
    if (length < 1e-6) return BiVec{};
    return .{ .xy = a.xy / length, .xz = a.xz / length, .yz = a.yz / length };
  }

  pub fn normal (b: BiVec) Vec4 {
    return Vec4.dir(b.yz, -b.xz, b.xy);
  }
};

