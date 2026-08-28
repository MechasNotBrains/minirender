//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________
pub const render = @This();
pub const Render = @This().Type;
// @deps std
const std = @import("std");
// @deps minirender
const mstd        = @import("mstd");
const msys        = @import("msys");
const mcam        = @import("mcam");
const minp        = @import("minp");
const minirender  = struct {
  const Mat4      = @import("./math.zig").Mat4;
  const Color     = @import("./math.zig").Color;
  const Store     = @import("./store.zig").Store;
  const backend   = struct {
    const Cvulkan = @import("./backend/cvulkan.zig").Type;
    const cvulkan = @import("./backend/cvulkan.zig");
  };
};


//______________________________________
// @section Subtypes
//____________________________
pub const Shape    = @import("./geometry.zig").Shape;
pub const Instance = @import("./geometry.zig").Instance;
pub const Vertex   = @import("./geometry.zig").Vertex;
pub const Command  = @import("./store.zig").Command;
pub const atlas    = @import("./backend/cvulkan/atlas.zig");
pub const Atlas    = atlas.Atlas;
pub const cull     = @import("./backend/cvulkan/cull.zig");
pub const ui       = @import("./backend/cvulkan/ui.zig");
pub const Ui       = ui.Ui;


//______________________________________
// @section Render
//____________________________
pub const Type = struct {
  //______________________________________
  // @section Object Fields
  //____________________________
  system          :msys.System,
  input           :minp.Manager,
  camera          :mcam.Camera,
  backend         :minirender.backend.Cvulkan,
  userdata        :?*anyopaque,
  close_on_escape :bool = true,


  //______________________________________
  // @section Create/Destroy
  //____________________________
  pub fn destroy (R :*const @This()) void {
    var mutable :*@This()= @constCast(R); _=&mutable;
    mutable.backend.destroy();
    mutable.system.term();
  }
  //__________________
  pub const create_args = struct {
    atlas     :atlas.Args,
    title     :mstd.zstring                    = "minirender",
    debug     :bool                            = false,
    mouse     :msys.Options.Input.Mouse.Mode   = .normal,
    resizable :bool                            = true,
    userdata  :?*anyopaque                     = null,
  };
  //__________________
  pub fn create (
      io  : std.Io,
      A   : std.mem.Allocator,
      arg : @This().create_args,
    ) !@This() {
    var result :@This()= undefined;
    result.input  = .empty;
    result.system = try msys.init(io, A, .{
      .api             = .vk,
      .window          = .{
        .title         = arg.title,
        .resizable     = arg.resizable,
      },
      .input           = .{ .mouse = .{ .mode = arg.mouse } },
    }); //:: result.system
    result.camera   = mcam.Camera{};
    result.userdata = arg.userdata;
    result.backend  = try .create(A, .{ .system= &result.system, .atlas= arg.atlas, .debug= arg.debug });
    result.system.window.user = arg.userdata;
    return result;
  }

  //______________________________________
  // @section Process
  //____________________________
  pub fn close   (R :*const @This()) bool { return R.system.close(); }
  pub fn present (R :*@This()) void { R.backend.present(); }
  pub fn update  (R :*@This()) void {
    if (R.userdata == null) {
      R.userdata = @ptrCast(R);
      R.system.window.user = R.userdata;
    }
    var events = R.system.events();
    while (events.next()) |ev| {
      R.input.event(ev);
      switch (ev) {
        .resize => |size| minirender.backend.cvulkan.resize(R, size.w, size.h),
        else    => {},
      }
    }
    R.camera.update(&R.camera, &R.input);
    R.input.mouse.change = .create(0,0,0,0);
    if (R.close_on_escape and R.input.key.active(.escape)) R.system.set_close(true);
    R.backend.update();
  }

  //__________________
  pub fn draw  (R :*@This()) void { R.backend.draw(&R.camera); }
  pub fn clear (R :*@This()) void { R.backend.clear(); }


  //______________________________________
  // @section Geometry
  //____________________________
  /// @descr
  ///  Returns the shapes and instances given to this renderer.
  ///  Every backend keeps them the same way, so nothing about them is dispatched.
  pub fn store (R :*@This()) *minirender.Store { return &R.backend.store; }
  //__________________
  pub fn shape (
      R     : *@This(),
      verts : []const Vertex,
      inds  : []const u32,
    ) !Shape.Id { return R.store().shape_add(verts, inds, false); }
  //__________________
  pub fn shape_alpha (
      R     : *@This(),
      verts : []const Vertex,
      inds  : []const u32,
    ) !Shape.Id { return R.store().shape_add(verts, inds, true); }
  //__________________
  pub fn instance (
      R     : *@This(),
      id    : Shape.Box.Key,
      world : minirender.Mat4,
      color : minirender.Color,
    ) !Instance.Id { return R.store().instance_add(id, world, color); }
  //__________________
  /// @descr Drops an instance, so whatever it was drawing stops being drawn.
  pub fn instance_remove (R :*@This(), id :Instance.Id) void { R.store().instance_remove(id); }
  //__________________
  /// @descr Lets go of a shape, along with the geometry it owns.
  pub fn shape_remove (R :*@This(), id :Shape.Id) void { R.store().shape_remove(id); }
  //__________________
  pub fn reassign_instance (
      R     : *@This(),
      id    : Instance.Id,
      S     : Shape.Id,
      world : minirender.Mat4,
      color : minirender.Color,
    ) void { R.store().instance_reassign(id, S, world, color); }
  //__________________
  pub fn set_selection_lines (
      R         : *@This(),
      positions : []const [3]f32,
      color     : [4]f32,
    ) void { R.backend.set_selection_lines(positions, color); }
  //__________________
  pub fn clear_selection_lines (R :*@This()) void { R.backend.clear_selection_lines(); }
  //__________________
  pub fn atlas_load (
      R      : *@This(),
      pixels : []const u8,
      size   : atlas.Size,
    ) ?atlas.Handle { return R.backend.atlas_load(pixels, size); }
  //__________________
  pub fn atlas_resize (R :*@This(), arg :atlas.Args) !void { try R.backend.atlas_resize(arg); }
  //__________________
  pub fn cull_counters (R :*@This()) cull.Counters { return R.backend.cull_counters(); }
  //__________________
  pub fn instances_read (R :*@This(), frameID :usize) []const Instance.Gpu { return R.backend.instances_read(frameID); }
  pub fn capture_frame (R :*@This(), trg :[]u8) void { R.backend.capture_frame(trg); }
  pub fn frame_width   (R :*const @This()) u32 { return R.backend.width(); }
  pub fn frame_height  (R :*const @This()) u32 { return R.backend.height(); }
  pub fn cull_instances_read (R :*@This(), trg :[]Instance.Gpu) void { R.backend.cull_instances_read(trg); }
  pub fn cull_commands_read  (R :*@This(), trg :[]Command) void { R.backend.cull_commands_read(trg); }
  //__________________
  pub fn ui_add      (R :*@This(), item :ui.Shape)         !void { try R.backend.ui_add(item); }
  pub fn ui_add_many (R :*@This(), items :[]const ui.Shape) !void { try R.backend.ui_add_many(items); }
  pub fn ui_view     (R :*@This()) *ui.View  { return R.backend.ui_view(); }
  pub fn ui_scene    (R :*@This()) *ui.Scene { return R.backend.ui_scene(); }
  //__________________
  pub fn atlas_scale  (R :*const @This(), handle :atlas.Handle) [2]f32 { return R.backend.atlas_scale(handle); }
  pub fn atlas_offset (R :*const @This(), handle :atlas.Handle) [2]f32 { return R.backend.atlas_offset(handle); }
  //__________________
  pub fn update_instance (
      R     : *@This(),
      id    : Instance.Id,
      world : minirender.Mat4,
      color : minirender.Color,
    ) void { R.backend.update_instance(id, world, color); }

  //______________________________________
  // @section Events
  //____________________________
  pub const resize = minirender.backend.cvulkan.resize;
};

