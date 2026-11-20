#include <flutter/runtime_effect.glsl>

uniform vec4 uTriangles[32];
out vec4 fragColor;

float halfQuantum(float value) {
  float normalized = value;
  float quantum = 1.0 / 2048.0;
  if (normalized < 1.0 / 256.0) {
    normalized *= 256.0;
    quantum /= 256.0;
  }
  if (normalized < 1.0 / 16.0) {
    normalized *= 16.0;
    quantum /= 16.0;
  }
  if (normalized < 1.0 / 4.0) {
    normalized *= 4.0;
    quantum /= 4.0;
  }
  if (normalized < 1.0 / 2.0) quantum /= 2.0;
  return max(quantum, 1.0 / 16777216.0);
}

void main() {
  vec3 source = vec3(FlutterFragCoord().xy, 1.0);
  float accumulated = 0.0;
  // 不提前退出，保留 Windows D3D 编译器所需的平直控制流。
  for (int triangle = 0; triangle < 8; triangle++) {
    vec4 plane = uTriangles[triangle * 4];
    if (plane.w > 0.5) {
      bool covered = true;
      for (int index = 1; index < 4; index++) {
        vec4 edge = uTriangles[triangle * 4 + index];
        float side = dot(source, edge.xyz);
        if (edge.w < 0.0) side = -side;
        if (side < 0.0 || (side == 0.0 && edge.w < 0.0)) covered = false;
      }
      // 大多数片元只属于一个三角形；未覆盖处无需重复做半精度量化。
      if (covered) {
        float alpha = clamp(dot(source, plane.xyz), 0.0, 0.5);
        float quantum = halfQuantum(alpha);
        float stored = floor(floor(alpha / quantum) * quantum * 255.0 + 0.5) / 255.0;
        accumulated = stored + accumulated * (1.0 - stored);
      }
    }
  }
  fragColor = vec4(0.0, 0.0, 0.0, accumulated);
}
