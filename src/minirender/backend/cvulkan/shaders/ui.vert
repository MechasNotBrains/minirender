#version 460

layout(location = 0) in vec2 aPosition;
layout(location = 1) in vec2 aUV;

struct Instance {
  vec2  position;
  vec2  scale;
  vec4  color;
  vec4  uv;
  uint  kind;
  float offset;
  uint  padding0;
  uint  padding1;
};

layout(set = 0, binding = 0, std430) readonly buffer Instances {
  Instance instances[];
};

layout(push_constant) uniform Push {
  vec2 screen;
} push;

layout(location = 0) out vec2      vUV;
layout(location = 1) out vec4      vColor;
layout(location = 2) out vec2      vSize;
layout(location = 3) flat out uint vShape;
layout(location = 4) out float     vOffset;
layout(location = 5) out vec4      vAtlasRegion;

void main () {
  Instance self = instances[gl_InstanceIndex];
  vec2 pixel    = aPosition * self.scale + self.position;
  vec2 ndc      = (pixel / push.screen) * 2.0 - 1.0;
  gl_Position   = vec4(ndc, 0.0, 1.0);
  vUV           = aUV;
  vColor        = self.color;
  vSize         = self.scale;
  vShape        = self.kind;
  vOffset       = self.offset;
  vAtlasRegion  = self.uv;
}
