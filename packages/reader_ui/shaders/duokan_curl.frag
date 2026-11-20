#include <flutter/runtime_effect.glsl>

uniform vec2 uSheetSize;
uniform vec4 uPaperColor;
uniform float uMirror;
uniform float uHasBackground;
uniform vec2 uFrontSize;
uniform vec2 uBackgroundSize;
uniform vec4 uCurlSpace;
uniform float uProfileCount;
uniform vec4 uProjectionProfile[24];
uniform vec3 uShadowAlphaPlane;
uniform vec4 uShadowEdges[3];
uniform sampler2D uFront;
uniform sampler2D uBackground;

out vec4 fragColor;

vec3 projectionAt(float x) {
  x = clamp(x, uProjectionProfile[0].x, uProjectionProfile[23].x);
  vec4 a = uProjectionProfile[0];
  vec4 b = uProjectionProfile[1];
  // 不在循环中提前退出，避免 ANGLE 展开嵌套跳转时触发 D3D 编译器异常。
  for (int index = 2; index < 24; index++) {
    if (x > b.x) {
      a = b;
      b = uProjectionProfile[index];
    }
  }
  float weight = clamp((x - a.x) / (b.x - a.x), 0.0, 1.0);
  return mix(a.yzw, b.yzw, weight);
}

// 半精度写回的量级；法线和混色表达式仍保持高精度。
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

float halfTrunc(float value) {
  float quantum = halfQuantum(value);
  return floor(value / quantum) * quantum;
}

float halfUnit(float value) {
  float quantum = halfQuantum(value);
  float scaled = value / quantum;
  float lower = floor(scaled);
  float fraction = scaled - lower;
  bool increment = fraction > 0.5 ||
      (fraction == 0.5 && mod(lower, 2.0) == 1.0);
  return (lower + (increment ? 1.0 : 0.0)) * quantum;
}

vec4 sample565(vec4 value) {
  vec3 levels = vec3(31.0, 63.0, 31.0);
  vec3 sampled = floor(clamp(value.rgb, 0.0, 1.0) * levels + 0.5) / levels;
  return vec4(sampled, 1.0);
}

vec4 halfRound(vec4 value) {
  return vec4(halfUnit(value.r), halfUnit(value.g), halfUnit(value.b), value.a);
}

// 显式落到像素中心，避免运行时着色器的默认采样器引入双线性插值。
vec2 nearestUV(vec2 uv, vec2 size) {
  return (clamp(floor(uv * size), vec2(0.0), size - 1.0) + 0.5) / size;
}

vec4 shadowColor(vec2 source) {
  bool covered = true;
  for (int index = 0; index < 3; index++) {
    vec4 edge = uShadowEdges[index];
    float side = dot(vec3(source, 1.0), edge.xyz);
    // 先用公共边的同一组系数求值，再反转方向，保证两侧互补。
    if (edge.w < 0.0) side = -side;
    if (side < 0.0 || (side == 0.0 && edge.w < 0.0)) {
      covered = false;
    }
  }
  // alpha 已在几何中乘 0.5；在片元写回时截断并按原 RGBA8 源色阶混合。
  float alpha = clamp(dot(vec3(source, 1.0), uShadowAlphaPlane), 0.0, 0.5);
  float stored = floor(halfTrunc(alpha) * 255.0 + 0.5) / 255.0;
  return vec4(0.0, 0.0, 0.0, covered ? stored : 0.0);
}

vec4 paperColor(vec2 source) {
  bool covered = true;
  vec3 normal = vec3(0.0, 0.0, uProjectionProfile[0].w);
  if (uProfileCount > 1.5) {
    float x = dot(source - uCurlSpace.xy, uCurlSpace.zw);
    if (x < uProjectionProfile[0].x || x > uProjectionProfile[23].x) {
      covered = false;
    }
    vec3 projection = projectionAt(x);
    source += uCurlSpace.zw * (projection.x - x);
    if (source.x < 0.0 || source.y < 0.0 ||
        source.x > uSheetSize.x || source.y > uSheetSize.y) {
      covered = false;
    }
    normal = normalize(vec3(uCurlSpace.zw * projection.y, projection.z));
  }
  vec2 uv = source / uSheetSize;
  if (uMirror > 0.5) uv.x = 1.0 - uv.x;
  vec4 front = sample565(texture(uFront, nearestUV(uv, uFrontSize)));
  vec4 color;
  if (normal.z > 0.1) {
    color = halfRound(front);
  } else {
    vec4 background = sample565(uHasBackground > 0.5
        ? texture(uBackground, nearestUV(uv, uBackgroundSize)) : uPaperColor);
    vec4 mixed = front * 0.05 + background * 0.95;
    // 原 Adreno GLSL 在混色写回时向零截断，最后光照乘法按最近偶数取整。
    vec3 stored = vec3(halfTrunc(mixed.r), halfTrunc(mixed.g), halfTrunc(mixed.b));
    color = halfRound(vec4(stored * (0.5 + abs(normal.z) * 0.5), mixed.a));
  }
  return covered ? color : vec4(0.0);
}

void main() {
  vec2 source = FlutterFragCoord().xy;
  if (uProfileCount < 0.0) {
    fragColor = shadowColor(source);
  } else {
    fragColor = paperColor(source);
  }
}
