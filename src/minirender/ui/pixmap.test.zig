//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
const t  = @import("minitest");
const it = t.it;
const Pixmap  = @import("./pixmap.zig").Pixmap;
const font5x7 = @import("./font5x7.zig");


var PixmapParse = t.describe("pixmap | parse");
test PixmapParse { PixmapParse.begin(); defer PixmapParse.end();
  try it("must set bits for non-space characters", struct { fn f() !void {
    const glyph = comptime Pixmap(3, 3).parse(
      "# #" ++
      " # " ++
      "# #",
    );
    try t.expect(glyph.pixel(0, 0) == true);
    try t.expect(glyph.pixel(1, 0) == false);
    try t.expect(glyph.pixel(2, 0) == true);
    try t.expect(glyph.pixel(0, 1) == false);
    try t.expect(glyph.pixel(1, 1) == true);
    try t.expect(glyph.pixel(2, 1) == false);
    try t.expect(glyph.pixel(0, 2) == true);
    try t.expect(glyph.pixel(1, 2) == false);
    try t.expect(glyph.pixel(2, 2) == true);
  }}.f);

  try it("must produce empty pixmap for all spaces", struct { fn f() !void {
    const glyph = comptime Pixmap(5, 7).parse(
      "     " ++
      "     " ++
      "     " ++
      "     " ++
      "     " ++
      "     " ++
      "     ",
    );
    for (0..5) |column| {
      for (0..7) |row| {
        try t.expect(glyph.pixel(column, row) == false);
      }
    }
  }}.f);

  try it("must produce full pixmap for all hashes", struct { fn f() !void {
    const glyph = comptime Pixmap(5, 7).parse(
      "#####" ++
      "#####" ++
      "#####" ++
      "#####" ++
      "#####" ++
      "#####" ++
      "#####",
    );
    for (0..5) |column| {
      for (0..7) |row| {
        try t.expect(glyph.pixel(column, row) == true);
      }
    }
  }}.f);
}


var Font5x7Lookup = t.describe("font5x7 | lookup");
test Font5x7Lookup { Font5x7Lookup.begin(); defer Font5x7Lookup.end();
  try it("must return space glyph for ASCII below 0x20", struct { fn f() !void {
    const space = font5x7.glyphs[0];
    const result = font5x7.lookup(0x00);
    for (0..5) |column| {
      for (0..7) |row| {
        try t.expect(result.pixel(column, row) == space.pixel(column, row));
      }
    }
  }}.f);

  try it("must return space glyph for ASCII above 0x7E", struct { fn f() !void {
    const space = font5x7.glyphs[0];
    const result = font5x7.lookup(0xFF);
    for (0..5) |column| {
      for (0..7) |row| {
        try t.expect(result.pixel(column, row) == space.pixel(column, row));
      }
    }
  }}.f);

  try it("must return A glyph for character A", struct { fn f() !void {
    const glyph = font5x7.lookup('A');
    try t.expect(glyph.pixel(0, 0) == false);
    try t.expect(glyph.pixel(1, 0) == true);
    try t.expect(glyph.pixel(2, 0) == true);
    try t.expect(glyph.pixel(3, 0) == true);
    try t.expect(glyph.pixel(4, 0) == false);
  }}.f);

  try it("must have 95 glyphs", struct { fn f() !void {
    try t.expect(font5x7.glyphs.len == 95);
  }}.f);
}
