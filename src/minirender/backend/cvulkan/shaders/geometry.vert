#version 460

layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aUV;
layout(location = 3) in vec2 aAtlasOffset;
layout(location = 4) in vec2 aAtlasScale;
layout(location = 5) in vec4 aVertexColor;

struct Instance {
  mat4 world;
  vec4 color;
  vec4 center;
  vec4 extent;
};

layout(set = 0, binding = 0, std430) readonly buffer Instances {
  Instance instances[];
};

layout(push_constant) uniform Push {
  mat4 viewProjection;
  uint textured;
} push;

layout(location = 0) out vec3 vNormal;
layout(location = 1) out vec2 vUV;
layout(location = 2) out vec2 vAtlasOffset;
layout(location = 3) out vec2 vAtlasScale;
layout(location = 4) out vec4 vColor;

void main () {
  Instance self = instances[gl_InstanceIndex];
  gl_Position   = push.viewProjection * self.world * vec4(aPosition, 1.0);
  vNormal       = mat3(self.world) * aNormal;
  vUV           = aUV;
  vAtlasOffset  = aAtlasOffset;
  vAtlasScale   = aAtlasScale;
  vColor        = self.color * aVertexColor;
}
