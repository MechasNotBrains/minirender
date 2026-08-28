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


## GPU-Driven Rendering

The goal of this backend, in every sense of the term. Not the OpenGL renderer wearing Vulkan's API.

### Principle

The GPU decides what it draws. The CPU uploads data and submits one call.

Instance data lives in storage buffers that the shader indexes itself. It is not handed to the
shader by the fixed-function stage through a vertex binding marked per-instance. That
distinction is the whole difference: a per-instance vertex binding can only deliver one struct
per instance in lockstep, while a buffer the shader indexes can be read by any stage, in any
order, by any invocation, and can be written by a compute pass before the draw runs.

### Mechanism

- **Instance data.** A `readonly buffer` indexed by `gl_InstanceIndex`.
  `gl_InstanceIndex` already includes `firstInstance`, so a command that sets `firstInstance`
  addresses its own slice of one shared buffer, with no shader-side arithmetic.
- **Per-draw data.** `gl_DrawID` says which command inside a multi-draw is executing, so
  per-shape data is a second buffer indexed by it. Needs `shaderDrawParameters`.
- **Draw parameters.** `vkCmdDrawIndexedIndirect` reads `VkDrawIndexedIndirectCommand` from a
  buffer. `Store.Command` is already field for field that struct.
- **Draw count.** `vkCmdDrawIndexedIndirectCount` reads the number of commands from a buffer as
  well, so a compute pass culls and writes how many survived. This is the step that makes the
  renderer GPU-driven instead of GPU-fed: the CPU stops knowing how many draws happen. Done, in
  `cvulkan/cull.zig`.

### What cvulkan already provides

Every feature this needs is declarable today through `cvk_device_features_Required.user`, and is
already checked by `cvk_device_features_supported` and combined by `cvk_device_features_merge`:

| Feature                          | Version | Enables                                       |
|:---------------------------------|:--------|:----------------------------------------------|
| `multiDrawIndirect`              | 1.0     | `drawCount` above 1 in one indirect call      |
| `drawIndirectFirstInstance`      | 1.0     | non-zero `firstInstance` in indirect commands |
| `wideLines`                      | 1.0     | line width above 1.0                          |
| `shaderDrawParameters`           | 1.1     | `gl_DrawID`, `gl_BaseInstance`                |
| `drawIndirectCount`              | 1.2     | count sourced from a buffer                   |
| `descriptorIndexing` and friends | 1.2     | bindless texture arrays                       |
| `scalarBlockLayout`              | 1.2     | buffer layouts that match the source structs  |
| `bufferDeviceAddress`            | 1.2     | raw pointers through push constants           |

`cvk_descriptor_binding_create_args` takes an arbitrary `VkDescriptorType`, a `stage` mask, and
`count`/`element`, so storage buffers and descriptor arrays need nothing added.
`cvk_pipeline_compute_create` exists, and `mech/cvulkan/compute.c` already dispatches through
barriers, so the culling pass has its foundation.

## Done

- [x] Split the non-OpenGL behavior out of `backend/opengl.zig` into `minirender/store.zig`
  - [x] `Store` holds shapes, instances, vertices, indices and the dirty flags
  - [x] `Store.build` groups instances by shape and writes one `Command` per shape, opaque first
  - [x] `Command` is field for field both `gl.draw.IndirectCommand` and `VkDrawIndexedIndirectCommand`
  - [x] `core.zig` calls the store directly instead of dispatching to a backend
  - [x] `backend/cvulkan.zig` holds a `Store`, so `core.zig` can reach it before anything else exists


## Missing from cvulkan

Items that have to be added to the C library and its Zig bindings before the backend can be written.

- [x] **Depth attachment binding.** `cvk_Rendering` now holds `color` and `depth_stencil` as
      `cvk_Attachment` values plus a `has_stencil` flag, and `cvk_command_rendering_begin` fills
      `pDepthAttachment` and `pStencilAttachment` from them.
- [x] **Index type.** `cvk_command_buffer_index_bind` takes `offset` and `kind` through an args
      object. `VK_INDEX_TYPE_UINT16` is `0`, so omitting `kind` keeps the previous behavior.
- [x] **Indirect draw.** `cvk_command_draw` now covers all six draw calls. `indirect_buffer` and
      `count_buffer` being NULL or not selects direct/indirect/indirect-count, and `indexed`
      selects the indexed variant. `cvk_command_draw_indexed` folded into it.

Not missing:
- `wideLines` is declarable through `features.user`, like every other feature in the
  GPU-Driven Rendering table above.
- Input assembly topology and rasterization line width / depth bias need no arguments.
  The `_defaults()` results are meant to be changed by the caller, which is what the
  examples already do for `cullMode`.
- The depth image is assembled by the caller from `cvk_image_data_create`, `cvk_memory_create`,
  `cvk_image_data_bind` and `cvk_image_view_create`, the same way every other image is.
  `mech/cvulkan/indirect.c` does it.
- `cvk_rendering_create` defaults the depth format to `D32_SFLOAT`, or `D32_SFLOAT_S8_UINT` when
  stencil is on. The spec only guarantees one of `D32_SFLOAT_S8_UINT` / `D24_UNORM_S8_UINT`, so a
  caller on hardware without the first passes its own format.


## Backend work

- [x] **Bootstrap.** Instance, validation, physical/logical device, queue, swapchain, image views.
      Surface comes from `mglfw.vk.surface`; `msys` already defaults to `.api = .vk`.
- [x] **Shaders.** `cvk_shader_create` takes SPIR-V only. Port both GLSL pairs from
      `backend/opengl/shaders.zig` and compile them the way `mech/cvulkan/shaders/` already does.
  - [x] each pair belongs to the element that draws with it: `geometry.Shader` and `lines.Shader`.
        There is no `shader.zig`
  - [x] `uViewProjection` becomes a push constant
  - [x] `uAtlas` is a combined image sampler at set 0 binding 1, bound every frame from
        `cvulkan/atlas.zig`. The push constant range covers vertex and fragment now that the
        fragment stage reads `textured`
  - [x] `uTextured` becomes a push constant, read by `geometry.frag` exactly as the OpenGL pair does
- [x] **Instance data.** Storage buffer read by `gl_InstanceIndex`, bound at set 0 binding 0
- [x] **GPU-driven draw count.** `cvulkan/cull.zig` runs `shaders/cull.comp` before the rendering
      pass, one invocation per command. Each tests its instances against the six frustum planes,
      compacts the survivors into its own instance buffer through `atomicAdd`, rewrites
      `instance_count` and `base_instance`, and claims an output command slot from the opaque or
      the alpha counter. `vkCmdDrawIndexedIndirectCount` then reads both the commands and how many
      there are from those buffers. The CPU passes a maximum, never a count.
  - [x] `Shape` measures its own box at `shape_add`; `store.build` carries it into every instance,
        so the cull test needs no second per-shape buffer and no `gl_DrawID`
- [x] **Frames in flight.** Instance buffer, command buffer, fence and semaphore per frame.
      `update_instance` writes into the mapped buffer of the frame being recorded.
  - [x] command buffer, fence and semaphore per frame, plus a descriptor set per frame
  - [x] the instance buffer is one per frame, and a `buffer.Host`: a host visible storage buffer
        that stays mapped, so the cull pass reads it with no staging copy and no queue wait
  - [x] `update_instance` keeps the slot `store.instance_update` hands back and appends one
        `Geometry.Patch`. Each frame applies the patches added since its own turn, straight into
        its mapped buffer. The list clears once every frame has caught up
  - [x] the indirect buffer is one per frame, written on the same turn as its instance buffer
- [x] **Geometry buffers.** Vertex and index buffers grown by recreating them in `Buffer.upload`
- [x] **Two pipelines for the alpha pass.** `graphics_opaque` writes depth, `graphics_alpha` does not.
      `draw` issues one indirect call per range, offset by `opaque_len` commands into the same buffer
- [x] **Line pipeline.** `lines.zig` owns its shader, its line-list pipeline and its vertex buffer.
      `viewProjection` and `color` travel together in one push constant range covering both stages.
  - [x] parity with the OpenGL backend: depth test off, `lineWidth` 2.0 through `wideLines`
- [ ] **Resize.** `cvk_device_swapchain_recreate`, plus the depth image alongside it.
      Blocked upstream: cvulkan marks that function `FIX: Does not work as expected. Currently gives
      validation errors on unreachable semaphore.` The callback tracks window size and camera aspect,
      but the swapchain keeps its original extent until that is fixed in cvulkan.


## Blocked on minirender.zig

- [x] `minirender.Atlas` was `atlas.zig`, which imports `mgl`. It now resolves to
      `backend/cvulkan/atlas.zig` through `core.zig`, so the Vulkan root exports a Vulkan atlas
- [x] `minirender.ui` / `Ui` resolve to `backend/cvulkan/ui.zig` through `core.zig`. `mui` is a
      dependency of the Vulkan build now, and `ui.zig` (the OpenGL union) is left to `core.gl.zig`

### Toward mui

`backend/cvulkan/ui.zig` is laid out the way `mui/src/mui/backend/mgpu` already is, so it lifts
into mui as a second backend beside `mgpu` with the minirender types swapped out:

| here                        | mui                              |
|:----------------------------|:---------------------------------|
| `Instance` + `Instance.upload` | `backend/mgpu/instance.zm`    |
| `Shader` + `vertex`/`fragment` | `backend/mgpu/shader.zm`      |
| `Screen` push constant       | `backend/mgpu/core.zm` `Screen`  |
| `Type`, `create`/`destroy`   | `backend/mgpu/core.zm` `Type`    |
| `sync` / `draw`              | `backend/mgpu.zm` `update` / `pass_draw` |

- [ ] the port of minirender's UI onto mui is still unfinished upstream: `mui`'s own shape has
      `uv` and `offset`, but `backend/mgpu` ignores both. The shaders here carry them, as the
      OpenGL pair in `backend/opengl/shaders.zig` does


## Blocked on core.zig

- [x] `create` asks for `.api = .vk`, with no `mgl.v4.load` and no `@panic` arms left
- [x] `cb.resize` no longer calls `mgl.v4.viewport.set`. The viewport is set per command buffer,
      inside `pass_draw`


## Order

1. Grow `mech/cvulkan/` until it draws minirender's vertex format, instanced, with depth.
2. Add the missing cvulkan pieces upstream. They are additions to structs that already exist.
3. Write `backend/cvulkan.zig` against the store.
4. Replace the `@panic` arms in `core.zig`.


## Notes

`colorBlend_attachment_defaults` is `SRC_ALPHA`/`ONE_MINUS_SRC_ALPHA` with blending enabled, which
matches what the OpenGL backend does, so it needs no argument.

`depthStencil_defaults` is test on, write on, `COMPARE_OP_GREATER`: reversed depth. It pairs with
`mmath.Mat4.perspective`, which is reverse-Z (near maps to 1, far to 0), so the depth attachment
clears to `0.0`, not `1.0`.
