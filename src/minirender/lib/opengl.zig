//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
// Minimal OpenGL bindings: only what we need, nothing else
pub const gl = @This();
// @deps std
const std = @import("std");

// Types
pub const Uint     = c_uint;
pub const Int      = c_int;
pub const Sizei    = c_int;
pub const Sizeiptr = isize;
pub const Enum     = c_uint;
pub const Float    = f32;
pub const Boolean  = u8;
pub const Char     = u8;
pub const Bitfield = c_uint;

// Constants
pub const FLOAT               = 0x1406;
pub const False               = 0;
pub const TRUE                = 1;
pub const Triangles           = 0x0004;
pub const LINES               = 0x0001;
pub const ArrayBuffer         = 0x8892;
pub const DYNAMIC_DRAW        = 0x88E8;
pub const Shader_Fragment     = 0x8B30;
pub const Shader_Vertex       = 0x8B31;
pub const COMPILE_STATUS      = 0x8B81;
pub const Status_Link         = 0x8B82;
pub const DEPTH_TEST          = 0x0B71;
pub const BLEND               = 0x0BE2;
pub const SRC_ALPHA           = 0x0302;
pub const ONE_MINUS_SRC_ALPHA = 0x0303;
pub const Color               = 0x00004000;
pub const Depth               = 0x00000100;
pub const INFO_LOG_LENGTH     = 0x8B84;

// Function pointer types — loaded at runtime
extern fn glGenBuffers              (Sizei, [*]Uint) callconv(.c) void;
extern fn glBindBuffer              (Enum, Uint) callconv(.c) void;
extern fn glBufferData              (Enum, Sizeiptr, ?*const anyopaque, Enum) callconv(.c) void;
extern fn glBufferSubData           (Enum, Sizeiptr, Sizeiptr, *const anyopaque) callconv(.c) void;
extern fn glGenVertexArrays         (Sizei, [*]Uint) callconv(.c) void;
extern fn glBindVertexArray         (Uint) callconv(.c) void;
extern fn glEnableVertexAttribArray (Uint) callconv(.c) void;
extern fn glDisableVertexAttribArray (index: gl.Uint) callconv(.c) void;
extern fn glVertexAttribPointer     (Uint, Int, Enum, Boolean, Sizei, ?*const anyopaque) callconv(.c) void;
extern fn glCreateShader            (Enum) callconv(.c) Uint;
extern fn glShaderSource            (Uint, Sizei, [*]const [*]const Char, ?[*]const Int) callconv(.c) void;
extern fn glCompileShader           (Uint) callconv(.c) void;
extern fn glGetShaderiv             (Uint, Enum, *Int) callconv(.c) void;
extern fn glGetShaderInfoLog        (Uint, Sizei, ?*Sizei, [*]Char) callconv(.c) void;
extern fn glCreateProgram           () callconv(.c) Uint;
extern fn glAttachShader            (Uint, Uint) callconv(.c) void;
extern fn glLinkProgram             (Uint) callconv(.c) void;
extern fn glGetProgramiv            (Uint, Enum, *Int) callconv(.c) void;
extern fn glGetProgramInfoLog       (Uint, Sizei, ?*Sizei, [*]Char) callconv(.c) void;
extern fn glUseProgram              (Uint) callconv(.c) void;
extern fn glDeleteShader            (Uint) callconv(.c) void;
extern fn glDeleteProgram           (Uint) callconv(.c) void;
extern fn glDeleteBuffers           (Sizei, [*]const Uint) callconv(.c) void;
extern fn glDeleteVertexArrays      (Sizei, [*]const Uint) callconv(.c) void;
extern fn glGetUniformLocation      (Uint, [*:0]const Char) callconv(.c) Int;
extern fn glUniformMatrix4fv        (Int, Sizei, Boolean, *const [16]Float) callconv(.c) void;
extern fn glDrawArrays              (Enum, Int, Sizei) callconv(.c) void;
extern fn glEnable                  (Enum) callconv(.c) void;
extern fn glDisable                 (Enum) callconv(.c) void;
extern fn glBlendFunc               (Enum, Enum) callconv(.c) void;
extern fn glLineWidth               (Float) callconv(.c) void;
extern fn glClear                   (Bitfield) callconv(.c) void;
extern fn glClearColor              (Float, Float, Float, Float) callconv(.c) void;
extern fn glUniform2f               (Int, Float, Float) callconv(.c) void;

// Loaded function pointers
pub const genBuffers               = glGenBuffers;
pub const bindBuffer               = glBindBuffer;
pub const bufferData               = glBufferData;
pub const bufferSubData            = glBufferSubData;
pub const genVertexArrays          = glGenVertexArrays;
pub const bindVertexArray          = glBindVertexArray;
pub const enableVertexAttribArray  = glEnableVertexAttribArray;
pub const disableVertexAttribArray = glDisableVertexAttribArray;
pub const vertexAttribPointer      = glVertexAttribPointer;
pub const createShader             = glCreateShader;
pub const shaderSource             = glShaderSource;
pub const getShaderiv              = glGetShaderiv;
pub const getShaderInfoLog         = glGetShaderInfoLog;
pub const createProgram            = glCreateProgram;
pub const attachShader             = glAttachShader;
pub const linkProgram              = glLinkProgram;
pub const getProgramiv             = glGetProgramiv;
pub const getProgramInfoLog        = glGetProgramInfoLog;
pub const useProgram               = glUseProgram;
pub const deleteShader             = glDeleteShader;
pub const deleteProgram            = glDeleteProgram;
pub const deleteBuffers            = glDeleteBuffers;
pub const deleteVertexArrays       = glDeleteVertexArrays;
pub const getUniformLocation       = glGetUniformLocation;
pub const uniformMatrix4fv         = glUniformMatrix4fv;
pub const uniform2f                = glUniform2f;
pub const drawArrays               = glDrawArrays;
pub const enable                   = glEnable;
pub const disable                  = glDisable;
pub const blendFunc                = glBlendFunc;
pub const lineWidth                = glLineWidth;
pub const clear                    = glClear;
pub const clearColor               = glClearColor;

pub fn compileShader (shader_type :gl.Enum, source :[*:0]const u8) !gl.Uint {
  const shader = gl.createShader(shader_type);
  const sources = [_][*]const u8{source};
  gl.shaderSource(shader, 1, &sources, null);
  glCompileShader(shader);

  var status: gl.Int = 0;
  gl.getShaderiv(shader, gl.COMPILE_STATUS, &status);
  if (status == gl.False) {
    var log_len: gl.Int = 0;
    gl.getShaderiv(shader, gl.INFO_LOG_LENGTH, &log_len);
    if (log_len > 0) {
      var buf: [512]u8 = undefined;
      gl.getShaderInfoLog(shader, 512, null, &buf);
      std.log.err("shader compile error: {s}", .{buf[0..@min(@as(usize, @intCast(log_len)), 512)]});
    }
    return error.ShaderCompileFailed;
  }
  return shader;
}

