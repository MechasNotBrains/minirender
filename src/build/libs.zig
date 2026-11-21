const confy = @import("confy");

//______________________________________
// @section Freetype
//____________________________
pub const freetype = struct {
  //__________________
  pub const dependency = confy.dependency("freetype", "https://github.com/OpenQuake3/freetype-prebuilt", .{.src= "freetype/include"});
  //__________________
  pub const url = struct {
    const base          = "https://github.com/OpenQuake3/freetype-prebuilt/releases/download/v2.13.3/freetype-";
    pub const static    = struct {
      pub const windows = freetype.url.base ++ "x86_64-windows-gnu.a";
      pub const linux   = freetype.url.base ++ "x86_64-linux-gnu.a";
      pub const mac     = struct {
        pub const x64   = freetype.url.base ++ "x86_64-macos.a";
        pub const arm64 = freetype.url.base ++ "aarch64-macos.a";
      };
    };
    pub const dynamic   = struct {
      pub const windows = struct {
        pub const dll   = freetype.url.base ++ "x86_64-windows-gnu.dll";
        pub const dll_a = freetype.url.base ++ "x86_64-windows-gnu.dll.a";
      };
      pub const linux   = freetype.url.base ++ "x86_64-linux-gnu.so";
      pub const mac     = struct {
        pub const x64   = freetype.url.base ++ "x86_64-macos.dylib";
        pub const arm64 = freetype.url.base ++ "aarch64-macos.dylib";
      };
    };
  };
  //__________________
  pub fn download (
      P      : confy.Process,
      cfg    : confy.Config,
      system : confy.System,
      root   : confy.cstring,
    ) !confy.cstring {
    const A   = P.arena.allocator();
    const io  = P.io;
    const dl  = confy.file.download_args{.redownload= false};
    const trg = try confy.path.join(A, &.{root, cfg.dir.bin, try system.zig_triple(A)});
    try confy.dir.create(trg, io, .{});
    switch (system.os) {
      .linux => {
        try confy.file.download(freetype.url.static.linux,  try confy.path.join(A, &.{trg, "libfreetype.a"}), io, A, dl);
        try confy.file.download(freetype.url.dynamic.linux, try confy.path.join(A, &.{trg, "libfreetype.so"}), io, A, dl);
      },
      .windows => {
        try confy.file.download(freetype.url.static.windows,        try confy.path.join(A, &.{trg, "libfreetype_static.a"}), io, A, dl);
        try confy.file.download(freetype.url.dynamic.windows.dll,   try confy.path.join(A, &.{trg, "libfreetype.dll"}), io, A, dl);
        try confy.file.download(freetype.url.dynamic.windows.dll_a, try confy.path.join(A, &.{trg, "libfreetype.a"}), io, A, dl);
      },
      .macos => switch (system.cpu) {
        .x86_64 => {
          try confy.file.download(freetype.url.static.mac.x64,  try confy.path.join(A, &.{trg, "libfreetype.a"}), io, A, dl);
          try confy.file.download(freetype.url.dynamic.mac.x64, try confy.path.join(A, &.{trg, "libfreetype.dylib"}), io, A, dl);
        },
        .aarch64 => {
          try confy.file.download(freetype.url.static.mac.arm64,  try confy.path.join(A, &.{trg, "libfreetype.a"}), io, A, dl);
          try confy.file.download(freetype.url.dynamic.mac.arm64, try confy.path.join(A, &.{trg, "libfreetype.dylib"}), io, A, dl);
        },
        else => return error.UnsupportedMacCPU,
      },
      else => return error.UnsupportedOS,
    }
    return trg;
  }
};

