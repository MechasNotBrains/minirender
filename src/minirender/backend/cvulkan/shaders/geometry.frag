#version 460

layout(location = 0) in vec3 vNormal;
layout(location = 1) in vec2 vUV;
layout(location = 2) in vec2 vAtlasOffset;
layout(location = 3) in vec2 vAtlasScale;
layout(location = 4) in vec4 vColor;

layout(set = 0, binding = 1) uniform sampler2D uAtlas;

layout(push_constant) uniform Push {
  mat4 viewProjection;
  uint textured;
} push;

layout(location = 0) out vec4 FragColor;

vec3 srgb_to_linear (vec3 value) {
  return mix(value / 12.92, pow((value + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), value));
}

void main () {
  vec3  light_direction = normalize(vec3(0.3, 0.7, 1.0));
  float diffuse         = max(dot(normalize(vNormal), light_direction), 0.0);
  float ambient         = 0.40;
  vec4  base_color      = vec4(srgb_to_linear(vColor.rgb), vColor.a);
  if (push.textured != 0u && vAtlasScale.x > 0.0) {
    vec2 atlas_uv   = fract(vUV) * vAtlasScale + vAtlasOffset;
    base_color.rgb *= texture(uAtlas, atlas_uv).rgb;
  }
  FragColor = vec4(base_color.rgb * (ambient + diffuse * (1.0 - ambient)), base_color.a);
}
