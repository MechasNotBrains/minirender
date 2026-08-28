#version 460

layout(push_constant) uniform Push {
  mat4 viewProjection;
  vec4 color;
} push;

layout(location = 0) out vec4 FragColor;

vec3 srgb_to_linear (vec3 value) {
  return mix(value / 12.92, pow((value + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), value));
}

void main () {
  FragColor = vec4(srgb_to_linear(push.color.rgb), push.color.a);
}
