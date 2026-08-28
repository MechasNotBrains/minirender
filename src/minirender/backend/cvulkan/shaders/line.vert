#version 460

layout(location = 0) in vec3 aPosition;

layout(push_constant) uniform Push {
  mat4 viewProjection;
  vec4 color;
} push;

void main () {
  gl_Position = push.viewProjection * vec4(aPosition, 1.0);
}
