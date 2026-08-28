#version 460

layout(push_constant) uniform Push {
  mat4 viewProjection;
  vec4 color;
} push;

layout(location = 0) out vec4 FragColor;

void main () {
  FragColor = push.color;
}
