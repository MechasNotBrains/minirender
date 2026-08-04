//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________

pub const vert_src: [:0]const u8 =
  \\#version 460 core
  \\layout(location=0) in vec3 aPosition;
  \\layout(location=1) in vec3 aNormal;
  \\layout(location=2) in vec2 aUV;
  \\layout(location=3) in vec2 aAtlasOffset;
  \\layout(location=4) in vec2 aAtlasScale;
  \\layout(location=5) in mat4 aWorld;
  \\layout(location=9) in vec4 aColor;
  \\uniform mat4 uViewProjection;
  \\out vec3 vNormal;
  \\out vec2 vUV;
  \\out vec2 vAtlasOffset;
  \\out vec2 vAtlasScale;
  \\out vec4 vColor;
  \\void main(){
  \\  gl_Position = uViewProjection * aWorld * vec4(aPosition, 1.0);
  \\  vNormal = mat3(aWorld) * aNormal;
  \\  vUV = aUV;
  \\  vAtlasOffset = aAtlasOffset;
  \\  vAtlasScale = aAtlasScale;
  \\  vColor = aColor;
  \\}
;

pub const frag_src: [:0]const u8 =
  \\#version 460 core
  \\in vec3 vNormal;
  \\in vec2 vUV;
  \\in vec2 vAtlasOffset;
  \\in vec2 vAtlasScale;
  \\in vec4 vColor;
  \\uniform sampler2D uAtlas;
  \\uniform bool uTextured;
  \\out vec4 FragColor;
  \\void main(){
  \\  vec3 light_direction = normalize(vec3(0.3, 0.7, 1.0));
  \\  float diffuse = max(dot(normalize(vNormal), light_direction), 0.0);
  \\  float ambient = 0.15;
  \\  vec4 base_color = vColor;
  \\  if (uTextured && vAtlasScale.x > 0.0) {
  \\    vec2 atlas_uv = fract(vUV) * vAtlasScale + vAtlasOffset;
  \\    base_color.rgb *= texture(uAtlas, atlas_uv).rgb;
  \\  }
  \\  FragColor = vec4(base_color.rgb * (ambient + diffuse * 0.85), base_color.a);
  \\}
;

pub const line_vert_src: [:0]const u8 =
  \\#version 460 core
  \\layout(location=0) in vec3 aPosition;
  \\uniform mat4 uViewProjection;
  \\void main(){
  \\  gl_Position = uViewProjection * vec4(aPosition, 1.0);
  \\}
;

pub const line_frag_src: [:0]const u8 =
  \\#version 460 core
  \\uniform vec4 uLineColor;
  \\out vec4 FragColor;
  \\void main(){
  \\  FragColor = uLineColor;
  \\}
;

pub const ui_vert_src: [:0]const u8 =
  \\#version 460 core
  \\layout(location=0) in vec2 aPosition;
  \\layout(location=1) in vec2 aUV;
  \\struct Instance {
  \\  vec2 position;
  \\  vec2 scale;
  \\  vec4 color;
  \\  vec4 uv;
  \\  uint kind;
  \\  float offset;
  \\  uint pad0; uint pad1;
  \\};
  \\layout(std430, binding=0) readonly buffer InstanceBuffer {
  \\  Instance instances[];
  \\};
  \\uniform vec2 uScreenSize;
  \\out vec2 vUV;
  \\out vec4 vColor;
  \\out vec2 vSize;
  \\flat out uint vShape;
  \\out float vOffset;
  \\out vec4 vAtlasRegion;
  \\void main(){
  \\  Instance shape = instances[gl_InstanceID];
  \\  vec2 pixel     = aPosition * shape.scale + shape.position;
  \\  vec2 ndc       = (pixel / uScreenSize) * 2.0 - 1.0;
  \\  ndc.y          = -ndc.y;
  \\  gl_Position    = vec4(ndc, 0.0, 1.0);
  \\  vUV            = aUV;
  \\  vColor         = shape.color;
  \\  vSize          = shape.scale;
  \\  vShape         = shape.kind;
  \\  vOffset        = shape.offset;
  \\  vAtlasRegion   = shape.uv;
  \\}
;

pub const ui_frag_src: [:0]const u8 =
  \\#version 460 core
  \\in vec2 vUV;
  \\in vec4 vColor;
  \\in vec2 vSize;
  \\flat in uint vShape;
  \\in float vOffset;
  \\in vec4 vAtlasRegion;
  \\uniform sampler2D uAtlas;
  \\out vec4 FragColor;
  \\float sdf_circle(vec2 point, float radius){
  \\  return length(point) - radius;
  \\}
  \\float sdf_triangle(vec2 point, float radius){
  \\  return max(abs(point.x) * 0.866 - point.y * 0.5 - radius * 0.25, point.y - radius * 0.5);
  \\}
  \\float sdf_rectangle(vec2 point, vec2 half_size){
  \\  vec2 d = abs(point) - half_size;
  \\  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
  \\}
  \\float sdf_shape(uint shape, vec2 pixel, vec2 size, float offset){
  \\  if(shape == 2u) return sdf_triangle(pixel, min(size.x, size.y)) - offset;
  \\  if(shape == 3u) return sdf_rectangle(pixel, size * 0.5) - offset;
  \\  return sdf_circle(pixel, min(size.x, size.y) * 0.5) - offset;
  \\}
  \\void main(){
  \\  vec2  centered = vUV - 0.5;
  \\  vec2  pixel    = centered * vSize;
  \\  float dist     = sdf_shape(vShape, pixel, vSize, vOffset);
  \\  float edge     = fwidth(dist);
  \\  float alpha    = 1.0 - smoothstep(-edge, edge, dist);
  \\  vec4  base     = vColor;
  \\  if (vAtlasRegion.z > 0.0) {
  \\    vec2 atlas_uv = vUV * vAtlasRegion.zw + vAtlasRegion.xy;
  \\    base.rgb *= texture(uAtlas, atlas_uv).rgb;
  \\  }
  \\  FragColor = vec4(base.rgb, base.a * alpha);
  \\}
;
