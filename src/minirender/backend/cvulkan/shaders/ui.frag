#version 460

layout(location = 0) in vec2      vUV;
layout(location = 1) in vec4      vColor;
layout(location = 2) in vec2      vSize;
layout(location = 3) flat in uint vShape;
layout(location = 4) in float     vOffset;
layout(location = 5) in vec4      vAtlasRegion;

layout(set = 0, binding = 1) uniform sampler2D uAtlas;

layout(location = 0) out vec4 FragColor;

float sdf_circle (vec2 point, float radius) {
  return length(point) - radius;
}

float sdf_triangle (vec2 point, float radius) {
  return max(abs(point.x) * 0.866 - point.y * 0.5 - radius * 0.25, point.y - radius * 0.5);
}

float sdf_rectangle (vec2 point, vec2 half_size) {
  vec2 distance = abs(point) - half_size;
  return length(max(distance, 0.0)) + min(max(distance.x, distance.y), 0.0);
}

float sdf_shape (uint shape, vec2 pixel, vec2 size, float offset) {
  if (shape == 2u) return sdf_triangle(pixel, min(size.x, size.y)) - offset;
  if (shape == 3u) return sdf_rectangle(pixel, size * 0.5) - offset;
  return sdf_circle(pixel, min(size.x, size.y) * 0.5) - offset;
}

void main () {
  if (vAtlasRegion.z > 0.0) {
    vec2 atlas_uv = vUV * vAtlasRegion.zw + vAtlasRegion.xy;
    vec4 texel    = texture(uAtlas, atlas_uv);
    FragColor     = vec4(vColor.rgb * texel.rgb, vColor.a * texel.a);
    return;
  }
  vec2  centered = vUV - 0.5;
  vec2  pixel    = centered * vSize;
  float distance = sdf_shape(vShape, pixel, vSize, vOffset);
  float edge     = fwidth(distance);
  float alpha    = 1.0 - smoothstep(-edge, edge, distance);
  FragColor      = vec4(vColor.rgb, vColor.a * alpha);
}
