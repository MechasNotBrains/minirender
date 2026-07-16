//:_______________________________________________________________________
//  minirender  |  Copyright (C) Ivan Mar (sOkam!)  |  GPL-3.0-or-later  :
//:_______________________________________________________________________

pub const vert_src: [:0]const u8 =
  \\#version 460 core
  \\layout(location=0) in vec3 aPosition;
  \\layout(location=1) in vec3 aNormal;
  \\layout(location=2) in mat4 aWorld;
  \\layout(location=6) in vec4 aColor;
  \\uniform mat4 uViewProjection;
  \\out vec3 vNormal;
  \\out vec4 vColor;
  \\void main(){
  \\  gl_Position = uViewProjection * aWorld * vec4(aPosition, 1.0);
  \\  vNormal = mat3(aWorld) * aNormal;
  \\  vColor = aColor;
  \\}
;

pub const frag_src: [:0]const u8 =
  \\#version 460 core
  \\in vec3 vNormal;
  \\in vec4 vColor;
  \\out vec4 FragColor;
  \\void main(){
  \\  vec3 light_direction = normalize(vec3(0.3, 0.7, 1.0));
  \\  float diffuse = max(dot(normalize(vNormal), light_direction), 0.0);
  \\  float ambient = 0.15;
  \\  FragColor = vec4(vColor.rgb * (ambient + diffuse * 0.85), vColor.a);
  \\}
;

pub const ui_vert_src: [:0]const u8 =
  \\#version 330 core
  \\layout(location=0) in vec2 aScreenPos;
  \\layout(location=1) in vec2 aLocalPos;
  \\layout(location=2) in vec2 aHalfSize;
  \\layout(location=3) in float aRadius;
  \\layout(location=4) in vec4 aFillColor;
  \\layout(location=5) in vec4 aBorderColor;
  \\layout(location=6) in float aMode;
  \\layout(location=7) in float aFillRatio;
  \\uniform vec2 uScreenSize;
  \\out vec2 vLocalPos;
  \\out vec2 vHalfSize;
  \\out float vRadius;
  \\out vec4 vFillColor;
  \\out vec4 vBorderColor;
  \\out float vMode;
  \\out float vFillRatio;
  \\void main(){
  \\  vec2 ndc = (aScreenPos / uScreenSize) * 2.0 - 1.0;
  \\  ndc.y = -ndc.y;
  \\  gl_Position = vec4(ndc, 0.0, 1.0);
  \\  vLocalPos = aLocalPos;
  \\  vHalfSize = aHalfSize;
  \\  vRadius = aRadius;
  \\  vFillColor = aFillColor;
  \\  vBorderColor = aBorderColor;
  \\  vMode = aMode;
  \\  vFillRatio = aFillRatio;
  \\}
;

pub const ui_frag_src: [:0]const u8 =
  \\#version 330 core
  \\in vec2 vLocalPos;
  \\in vec2 vHalfSize;
  \\in float vRadius;
  \\in vec4 vFillColor;
  \\in vec4 vBorderColor;
  \\in float vMode;
  \\in float vFillRatio;
  \\out vec4 FragColor;
  \\void main(){
  \\  vec2 d = abs(vLocalPos) - vHalfSize + vec2(vRadius);
  \\  float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - vRadius;
  \\  float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
  \\  if (alpha < 0.001) discard;
  \\  vec4 color = vFillColor;
  \\  if (vMode > 0.5 && vMode < 1.5) {
  \\    float fill_edge = -vHalfSize.x + 2.0 * vHalfSize.x * vFillRatio;
  \\    float filled = smoothstep(fill_edge + 0.5, fill_edge - 0.5, vLocalPos.x);
  \\    color = mix(vBorderColor, vFillColor, filled);
  \\  } else if (vMode > 1.5) {
  \\    float border_alpha = 1.0 - smoothstep(0.5, 1.5, abs(dist));
  \\    color = vBorderColor;
  \\    color.a *= border_alpha;
  \\  }
  \\  color.a *= alpha;
  \\  FragColor = color;
  \\}
;
