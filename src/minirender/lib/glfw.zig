//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const glfw = @This();
pub const __helpers = @import("std").zig.c_translation.helpers;

pub const Monitor = *const anyopaque;
pub const Window  = *const anyopaque;

extern fn glfwInit() c_int;
pub const create = glfwInit;

extern fn glfwTerminate() void;
pub const destroy = glfwTerminate;

pub const True      = @as(c_int, 1);
pub const False     = @as(c_int, 0);
pub const Resizable = __helpers.promoteIntLiteral(c_int, 0x00020003, .hex);

pub const opengl = struct {
  extern fn glfwSwapBuffers(window: ?*Window) void;
  pub const present = glfwSwapBuffers;

  extern fn glfwSwapInterval(interval: c_int) void;
  pub const setVSync = glfwSwapInterval;
  // pub const Api           = c.GLFW_OPENGL_API;
  // pub const ESApi         = c.GLFW_OPENGL_ES_API;
  // pub const ForwardCompat = c.GLFW_OPENGL_FORWARD_COMPAT;
  // pub const profile       = struct {
  //   pub const Hint        = c.GLFW_OPENGL_PROFILE;
  //   pub const Any         = c.GLFW_OPENGL_ANY_PROFILE;
  //   pub const Core        = c.GLFW_OPENGL_CORE_PROFILE;
  //   pub const Compat      = c.GLFW_OPENGL_COMPAT_PROFILE;
  // }; //:: glfw.opengl.profile
  pub const context = struct {
    extern fn glfwMakeContextCurrent(window: ?*Window) void;
    pub const setActive   = glfwMakeContextCurrent;
    pub const version     = struct {
      pub const M = __helpers.promoteIntLiteral(c_int, 0x00022002, .hex);
      pub const m = __helpers.promoteIntLiteral(c_int, 0x00022003, .hex);
      pub const p = __helpers.promoteIntLiteral(c_int, 0x00022004, .hex);
    }; //:: glfw.opengl.context.version
    // pub const Robustness  = c.GLFW_CONTEXT_ROBUSTNESS;
    pub const Debug = __helpers.promoteIntLiteral(c_int, 0x00022007, .hex);
  }; //:: glfw.opengl.context
  // pub const extension     = struct {
  //   pub fn supported (name :glfw.String) bool { return c.glfwExtensionSupported(name.ptr) == glfw.True; }
  // }; //:: glfw.opengl.extension
}; //:: glfw.opengl

pub const window = struct {
  extern fn glfwCreateWindow(width: c_int, height: c_int, title: [*c]const u8, monitor: ?*Monitor, share: ?*Window) ?*Window;
  pub const create = glfwCreateWindow;

  extern fn glfwWindowShouldClose(window: ?*Window) c_int;
  pub const close = glfwWindowShouldClose;

  extern fn glfwWindowHint(hint: c_int, value: c_int) void;
  pub const hint = glfwWindowHint;

  extern fn glfwSetWindowShouldClose(window: ?*glfw.Window, value: c_int) void;
  pub const setClose = glfwSetWindowShouldClose;
};

extern fn glfwPollEvents() void;
pub const sync = glfwPollEvents;

extern fn glfwGetTime() f64;
pub const getTime = glfwGetTime;

pub const callback = struct {
  // try glfw.callback.setMouseBtn(win.ct, in.cb.mouseBtn);
  // try glfw.callback.setMousePos(win.ct, in.cb.mousePos);

  pub const Fn    = struct {
    pub const Key      = ?*const fn (window: ?*glfw.Window, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void;
    pub const MousePos = ?*const fn (window: ?*glfw.Window, xpos: f64, ypos: f64) callconv(.c) void;
    pub const MouseBtn = ?*const fn (window: ?*glfw.Window, button: c_int, action: c_int, mods: c_int) callconv(.c) void;
    pub const Scroll   = ?*const fn (window: ?*glfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void;
  };
  extern fn glfwSetKeyCallback(window: ?*glfw.Window, callback: glfw.callback.Fn.Key) glfw.callback.Fn.Key;
  pub fn setKey (W :?*glfw.Window, F :glfw.callback.Fn.Key) !void { if (glfwSetKeyCallback(W,F) != null) return error.glfw_cb_SetKeyFailed; }
  pub const default = struct {
    pub fn key (win :?*glfw.Window, K :c_int, code :c_int, action :c_int, mods :c_int) callconv(.c) void {_=mods;_=code;
      if (K == glfw.Key.escape and (action == glfw.Press or action == glfw.Release)) glfw.window.setClose(win, glfw.True);
    }
    pub fn mousePos (win  :?*glfw.Window, xpos: f64, ypos: f64) callconv(.c) void {_=win;_=xpos;_=ypos;
    }
    pub fn mouseBtn (win :?*glfw.Window, button: c_int, action: c_int, mods: c_int) callconv(.c) void {_=win;_=button;_=action;_=mods;
    }
  };

  extern fn glfwSetMouseButtonCallback(window: ?*glfw.Window, callback :glfw.callback.Fn.MouseBtn) glfw.callback.Fn.MouseBtn;
  extern fn glfwSetCursorPosCallback(window: ?*glfw.Window, callback :glfw.callback.Fn.MousePos) glfw.callback.Fn.MousePos;
  extern fn glfwSetScrollCallback(window: ?*glfw.Window, callback :glfw.callback.Fn.Scroll) glfw.callback.Fn.Scroll;
  pub fn setMousePos (W :?*glfw.Window, F :glfw.callback.Fn.MousePos) !void { if (glfwSetCursorPosCallback(W,F) != null) return error.glfw_cb_SetMousePosFailed; }
  pub fn setMouseBtn (W :?*glfw.Window, F :glfw.callback.Fn.MouseBtn) !void { if (glfwSetMouseButtonCallback(W,F) != null) return error.glfw_cb_SetMouseBtnFailed; }
  pub fn setScroll   (W :?*glfw.Window, F :glfw.callback.Fn.Scroll)   !void { if (glfwSetScrollCallback(W,F)     != null) return error.glfw_cb_SetScrollFailed; }
};

// Inputs
pub const Release = @as(c_int, 0);
pub const Press   = @as(c_int, 1);
pub const Repeat  = @as(c_int, 2);
pub const Key = struct {
  pub const space      = @as(c_int, 32);
  pub const a          = @as(c_int, 65);
  pub const r          = @as(c_int, 82);
  pub const s          = @as(c_int, 83);
  pub const w          = @as(c_int, 87);
  pub const escape     = @as(c_int, 256);
  pub const left_shift = @as(c_int, 340);
  pub const right_shift= @as(c_int, 341);
};

pub const Cursor = struct {
  pub const Normal   = @as(c_int, 0x00034001);
  pub const Hidden   = @as(c_int, 0x00034002);
  pub const Disabled = @as(c_int, 0x00034003);
  pub const Mode     = @as(c_int, 0x00033001);
};

extern fn glfwSetInputMode(window: ?*Window, mode: c_int, value: c_int) void;
pub const setInputMode = glfwSetInputMode;

pub const MouseButton = struct {
  pub const left   = @as(c_int, 0);
  pub const right  = @as(c_int, 1);
  pub const middle = @as(c_int, 2);
};

extern fn glfwSetWindowUserPointer(window: ?*Window, pointer: ?*anyopaque) void;
pub const setUserPointer = glfwSetWindowUserPointer;

extern fn glfwGetWindowUserPointer(window: ?*Window) ?*anyopaque;
pub const getUserPointer = glfwGetWindowUserPointer;

