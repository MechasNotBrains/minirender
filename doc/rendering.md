# minirender — Rendering Architecture

## Overview

Single-draw-call renderer for a modular 3D editor.
All geometry and all instances drawn with one `glMultiDrawElementsIndirect` call per frame.
GPU uploads only happen when data changes — static scenes cost zero uploads.


## Data Layout

### Shared Buffers

All shapes and instances live in shared GPU buffers:

- **Geometry VBO** — all shapes' vertex data packed contiguously.
  Per-vertex: position (vec3), normal (vec3). Stride: 24 bytes.

- **Geometry EBO** — all shapes' index data packed contiguously.

- **Instance Buffer** — all instances packed contiguously, grouped by shape.
  Per-instance: world matrix (mat4, 64 bytes), color (vec4, 16 bytes). Stride: 80 bytes.

- **Draw-Indirect Buffer** — one `DrawElementsIndirectCommand` per shape with live instances.

### Generational Arena (mstd Box)

Both shapes and instances are stored in `mstd.Box(T)` arenas.
Handles (`Box.Key`) are the only way to reference them.
Keys carry a generational version — stale keys are rejected, removed slots are reused.

- **Shape Box** — `Box(Shape)`. Each slot holds geometry metadata (offsets into shared VBO/EBO, index count).
  `Box.add` returns a shape key. `Box.rmv` frees the slot and increments the version.

- **Instance Box** — `Box(Instance)`. Each slot holds a shape key + world matrix + color.
  `Box.add` returns an instance key. `Box.rmv` frees the slot.

Box data is packed contiguously (`Box.items` returns a dense slice), which maps directly
to the GPU buffer layout — the instance Box's data slice is the upload source.

### Per-Shape Tracking

Each shape in the shape Box stores:
- `base_vertex` — offset into the shared VBO (vertex count before this shape).
- `first_index` — offset into the shared EBO (index count before this shape).
- `index_count` — number of indices for this shape.
- `base_instance` — offset into the instance buffer (recomputed on indirect rebuild).
- `instance_count` — number of live instances of this shape (recomputed on indirect rebuild).


## Indirect Draw

One `DrawElementsIndirectCommand` per shape with live instances:

```
struct DrawElementsIndirectCommand {
    index_count    : u32   // shape's triangle indices
    instance_count : u32   // how many instances of this shape
    first_index    : u32   // offset into shared EBO
    base_vertex    : i32   // offset into shared VBO
    base_instance  : u32   // offset into shared instance buffer
}
```

One `glMultiDrawElementsIndirect` call submits the entire draw-indirect buffer.
All shapes, all instances, one draw call.


## Dirty Tracking

GPU uploads only happen when data changes:

- **Instance dirty flag** — set when any instance is created, destroyed, moved, or recolored.
  On flush: if dirty, re-upload the instance buffer (or the dirty range). Clear flag.

- **Geometry dirty flag** — set when a shape is registered or removed.
  On flush: if dirty, re-upload VBO + EBO + rebuild indirect buffer. Clear flag.

- **Indirect buffer dirty flag** — set when instance counts change (add/remove instances) or geometry changes.
  On flush: if dirty, re-upload the draw-indirect buffer. Clear flag.

If nothing changed: bind VAO, bind indirect buffer, draw. Zero uploads.


## Vertex Layout (VAO)

One VAO for the entire renderer. Two binding points:

### Binding 0 — per-vertex (divisor 0)

| Location | Attribute | Size   | Offset |
|----------|-----------|--------|--------|
| 0        | position  | vec3   | 0      |
| 1        | normal    | vec3   | 12     |

Stride: 24 bytes. Bound to geometry VBO.

### Binding 1 — per-instance (divisor 1)

| Location | Attribute       | Size   | Offset |
|----------|-----------------|--------|--------|
| 2        | world row 0     | vec4   | 0      |
| 3        | world row 1     | vec4   | 16     |
| 4        | world row 2     | vec4   | 32     |
| 5        | world row 3     | vec4   | 48     |
| 6        | color           | vec4   | 64     |

Stride: 80 bytes. Bound to instance buffer.


## Shader

Vertex:
```glsl
#version 460 core
layout(location=0) in vec3 aPosition;
layout(location=1) in vec3 aNormal;
layout(location=2) in mat4 aWorld;
layout(location=6) in vec4 aColor;

uniform mat4 uViewProjection;

out vec3 vNormal;
out vec4 vColor;

void main() {
    gl_Position = uViewProjection * aWorld * vec4(aPosition, 1.0);
    vNormal = mat3(aWorld) * aNormal;
    vColor = aColor;
}
```

Fragment:
```glsl
#version 460 core
in vec3 vNormal;
in vec4 vColor;
out vec4 FragColor;

void main() {
    vec3 light_direction = normalize(vec3(0.3, 0.7, 1.0));
    float diffuse = max(dot(normalize(vNormal), light_direction), 0.0);
    float ambient = 0.15;
    FragColor = vec4(vColor.rgb * (ambient + diffuse * 0.85), vColor.a);
}
```


## mgl v4 Requirements

Functions to add to the loader:

| Function                         | GL Version | Purpose                          |
|----------------------------------|------------|----------------------------------|
| `glVertexArrayBindingDivisor`    | 4.3 (DSA)  | set per-instance divisor         |
| `glDrawElementsInstanced`        | 3.1        | fallback single-shape draw       |
| `glMultiDrawElementsIndirect`    | 4.3        | single draw call for everything  |

Types already exist in raw.zig:
- `PFNGLVERTEXARRAYBINDINGDIVISORPROC`
- `PFNGLDRAWELEMENTSINSTANCEDPROC`
- `PFNGLMULTIDRAWELEMENTSINDIRECTPROC`

VertexArray needs:
- `attribute` takes binding_point parameter (currently hardcoded to 0).
- `divisor(binding_point, value)` method — calls `glVertexArrayBindingDivisor`.

Draw module needs:
- `elements_instanced(primitive, count, index_type, instance_count)`.
- `multi_elements_indirect(primitive, indirect_buffer, draw_count, stride)`.


## Flush Sequence

```
if geometry_dirty:
    upload VBO (all shape vertices)
    upload EBO (all shape indices)
    geometry_dirty = false
    indirect_dirty = true

if instance_dirty:
    upload instance buffer
    instance_dirty = false

if indirect_dirty:
    rebuild + upload draw-indirect buffer
    indirect_dirty = false

bind VAO
bind draw-indirect buffer
set uViewProjection uniform
enable depth test, blending
glMultiDrawElementsIndirect(GL_TRIANGLES, GL_UNSIGNED_INT, null, shape_count, 0)
```


## UI Rendering (mui)

Separate from the 3D pipeline. Uses mui's data model:
- Shape: position (vec2), scale (vec2), color (vec4), kind (circle/triangle/square).
- Scene holds shapes. View defines 2D camera.
- Backend converts shapes to Instance data (position[2], scale[2], color[4], shape u8).
- Uploads to GPU, SDF fragment shader renders all shapes.
- Own shader program, own VAO, own draw call. Runs after 3D flush.
