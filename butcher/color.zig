//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const Color = @This();

r :f32,  g :f32,  b :f32,  a :f32= 1,

pub const red       = Color{ .r= 1.0, .g= 0.2, .b= 0.2 };
pub const green     = Color{ .r= 0.2, .g= 1.0, .b= 0.2 };
pub const blue      = Color{ .r= 0.3, .g= 0.3, .b= 1.0 };
pub const yellow    = Color{ .r= 1.0, .g= 1.0, .b= 0.2 };
pub const cyan      = Color{ .r= 0.2, .g= 1.0, .b= 1.0 };
pub const magenta   = Color{ .r= 1.0, .g= 0.2, .b= 1.0 };
pub const white     = Color{ .r= 1.0, .g= 1.0, .b= 1.0 };
pub const gray      = Color{ .r= 0.5, .g= 0.5, .b= 0.5 };
pub const dark_gray = Color{ .r= 0.3, .g= 0.3, .b= 0.3 };

// Transparent: 0.25
pub const red_025       = Color{ .r= 1.0, .g= 0.2, .b= 0.2, .a= 0.25 };
pub const green_025     = Color{ .r= 0.2, .g= 1.0, .b= 0.2, .a= 0.25 };
pub const blue_025      = Color{ .r= 0.3, .g= 0.3, .b= 1.0, .a= 0.25 };
pub const yellow_025    = Color{ .r= 1.0, .g= 1.0, .b= 0.2, .a= 0.25 };
pub const cyan_025      = Color{ .r= 0.2, .g= 1.0, .b= 1.0, .a= 0.25 };
pub const magenta_025   = Color{ .r= 1.0, .g= 0.2, .b= 1.0, .a= 0.25 };
pub const white_025     = Color{ .r= 1.0, .g= 1.0, .b= 1.0, .a= 0.25 };
pub const gray_025      = Color{ .r= 0.5, .g= 0.5, .b= 0.5, .a= 0.25 };
pub const dark_gray_025 = Color{ .r= 0.3, .g= 0.3, .b= 0.3, .a= 0.25 };

