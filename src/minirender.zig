//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const minirender = @This();
// Math Exports
pub const math       = @import("./minirender/math.zig");
pub const Vec4       = minirender.math.Vec4;
pub const Vec3       = minirender.math.Vec3;
pub const Vec2       = minirender.math.Vec2;
pub const Rotor      = minirender.math.Rotor;
pub const Mat4       = minirender.math.Mat4;
pub const vec4       = minirender.math.vec4;
pub const vec3       = minirender.math.vec3;
pub const vec2       = minirender.math.vec2;
// Rendering exports
pub const color      = @import("./minirender/color.zig");
pub const Color      = minirender.color.Type;
pub const camera     = @import("mcam");
pub const Camera     = minirender.camera.Camera;
pub const geometry   = @import("./minirender/geometry.zig");
pub const Vertex     = minirender.geometry.Vertex;
// UI
pub const ui         = @import("./minirender/ui.zig");
pub const Ui         = minirender.ui.Type;
// Renderer
pub const Render     = @import("./minirender/core.zig").Render;
