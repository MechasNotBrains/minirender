//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const Color = @This();

r: f32,  g: f32,  b: f32,  a: f32 = 1,

pub const red       = Color{ .r = 1, .g = 0.2, .b = 0.2 };
pub const green     = Color{ .r = 0.2, .g = 1, .b = 0.2 };
pub const blue      = Color{ .r = 0.3, .g = 0.3, .b = 1 };
pub const yellow    = Color{ .r = 1, .g = 1, .b = 0.2 };
pub const cyan      = Color{ .r = 0.2, .g = 1, .b = 1 };
pub const magenta   = Color{ .r = 1, .g = 0.2, .b = 1 };
pub const white     = Color{ .r = 1, .g = 1, .b = 1 };
pub const gray      = Color{ .r = 0.5, .g = 0.5, .b = 0.5 };
pub const dark_gray = Color{ .r = 0.3, .g = 0.3, .b = 0.3 };

