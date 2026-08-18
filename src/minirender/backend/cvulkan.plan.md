# cvulkan backend | Plan

Implements `minirender.backend.cvulkan.Render` against [cvulkan](https://codeberg.org/heysokam/cvulkan),
matching the API that `core.zig` already dispatches to for the OpenGL backend.

Reference paths:
- cvulkan C library : `~/gd/tools/vulkan/cvk`
- cvulkan Zig FFI   : `~/gd/tools/vulkan/cvk.ffi/zig`
- Working sandbox   : `mech/cvulkan/`
- Closest example   : `cvk/examples/009.quad_instanced.c`


## The contract

`core.zig` reaches into `backend.store` directly for everything that holds shapes and instances,
so the backend only has to provide what actually touches the GPU:

| Function                 | Notes                                                          |
|:-------------------------|:---------------------------------------------------------------|
| `create`                 | Bootstrap, pipelines, per-frame resources                       |
| `destroy`                | In reverse, after `device_logical_wait`                         |
| `clear`                  | A rendering pass with `LOAD_OP_CLEAR`                           |
| `sync`                   | Upload what is dirty, record and submit the frame               |
| `update_instance`        | Write one entry through `store.instance_update`                 |
| `set_selection_lines`    | Upload line positions, keep the count and color                 |
| `clear_selection_lines`  | Drop the line count to zero                                     |

Everything else (`shape`, `shape_alpha`, `shape_remove`, `instance`, `instance_remove`,
`reassign_instance`) is served by `minirender.Store` and never reaches a backend.


## Done

- [x] Split the non-OpenGL behavior out of `backend/opengl.zig` into `minirender/store.zig`
  - [x] `Store` holds shapes, instances, vertices, indices and the dirty flags
  - [x] `Store.build` groups instances by shape and writes one `Command` per shape, opaque first
  - [x] `Command` is field for field both `gl.draw.IndirectCommand` and `VkDrawIndexedIndirectCommand`
  - [x] `core.zig` calls the store directly instead of dispatching to a backend
  - [x] `backend/cvulkan.zig` holds a `Store`, so `core.zig` can reach it before anything else exists


## Missing from cvulkan

Items that have to be added to the C library and its Zig bindings before the backend can be written.

- [ ] **Depth attachment binding.** `cvk_rendering_create_args` takes a `depth` format and
      `cvk_Rendering` stores it, but `cvk_command_rendering_begin` hardcodes `colorAttachmentCount = 1`
      and never fills `pDepthAttachment`. Needs a depth image view in
      `cvk_command_rendering_begin_args`.
- [ ] **Depth image helper.** A swapchain-sized depth image + view, with format selection and
      recreation alongside `cvk_device_swapchain_recreate`.
- [ ] **Indirect draw.** Only `cvk_command_draw` and `cvk_command_draw_indexed` exist.
      `Store.build` already produces the command buffer contents, so this needs
      `cvk_command_draw_indexed_indirect` over `vkCmdDrawIndexedIndirect`.
      Without it the draw becomes a loop of `draw_indexed`, one call per shape.
- [ ] **Input assembly args.** `cvk_pipeline_state_inputAssembly_defaults()` is triangle-list only.
      The selection lines need `TOPOLOGY_LINE_LIST`.
- [ ] **Rasterization args.** `cvk_pipeline_state_rasterization_defaults()` fixes `lineWidth` at 1.0
      and `depthBiasEnable` at false. Lines are drawn at 2.0, and the shapes are drawn with a
      depth bias of (1, 1).
- [ ] **`wideLines` device feature.** Required for any line width above 1.0.


## Backend work

- [ ] **Bootstrap.** Instance, validation, physical/logical device, queue, swapchain, image views.
      Surface comes from `mglfw.vk.surface`; `msys` already defaults to `.api = .vk`.
- [ ] **Shaders.** `cvk_shader_create` takes SPIR-V only. Port both GLSL pairs from
      `backend/opengl/shaders.zig` and compile them the way `mech/cvulkan/shaders/` already does.
  - [ ] `uViewProjection` becomes a push constant
  - [ ] `uAtlas` becomes a combined image sampler descriptor
  - [ ] `uTextured` becomes a push constant or a specialization constant
- [ ] **Instance data.** OpenGL uses a second vertex binding at divisor 1. cvulkan's example reads a
      storage buffer by `gl_InstanceIndex` instead, which is what the existing helpers demonstrate.
      Pick one before writing the vertex input state.
- [ ] **Frames in flight.** Instance buffer, command buffer, fence and semaphore per frame.
      `update_instance` writes into the mapped buffer of the frame being recorded.
- [ ] **Geometry buffers.** Vertex and index buffers grown the way `ensure_buffer` does in OpenGL.
- [ ] **Two pipelines for the alpha pass**, or `VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE`.
      OpenGL draws the opaque commands, turns depth writes off, then draws the rest.
- [ ] **Line pipeline.** Second pipeline at line-list topology over its own vertex buffer.
- [ ] **Resize.** `cvk_device_swapchain_recreate`, plus the depth image alongside it.


## Blocked on core.zig

- [ ] `create` hardcodes `.api = .gl` and calls `mgl.v4.load`. Needs to branch on the backend asked for.
- [ ] `cb.resize` calls `mgl.v4.viewport.set`. Vulkan sets the viewport per command buffer and
      recreates the swapchain instead.


## Order

1. Grow `mech/cvulkan/` until it draws minirender's vertex format, instanced, with depth.
2. Add the missing cvulkan pieces upstream. They are additions to structs that already exist.
3. Write `backend/cvulkan.zig` against the store.
4. Replace the `@panic` arms in `core.zig`.


## Notes

Two cvulkan defaults already match what the OpenGL backend does, so neither needs an argument:
`colorBlend_attachment_defaults` is `SRC_ALPHA`/`ONE_MINUS_SRC_ALPHA` with blending enabled, and
`depthStencil_defaults` is test on, write on, `COMPARE_OP_LESS`.
