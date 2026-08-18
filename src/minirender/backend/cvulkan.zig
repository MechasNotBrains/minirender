//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const render = @This();
pub const Render = @This().Type;
// @deps minirender
const minirender = struct {
  const Store = @import("../store.zig").Store;
};

//______________________________________
// @section Object Fields
//____________________________
pub const Type = struct {
  // CPU data
  store :minirender.Store,

  //______________________________________
  // @section Create/Destroy
  //____________________________
  // TODO:

  //______________________________________
  // @section Process
  //____________________________
  // TODO:
};
