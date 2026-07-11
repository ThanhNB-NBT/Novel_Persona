#version 460 core
#include <flutter/runtime_effect.glsl>

// Hiệu ứng năng lượng thủ tục cho cảnh Độ Kiếp / đại cảnh giới (nấc 2).
// Phủ ADDITIVE (BlendMode.plus) lên hiệu ứng CustomPainter nấc 1 → bloom + godray.
// Chỉ sinh hình, không cần texture nguồn → tự chứa, chạy trên GPU điện thoại.

precision highp float;

uniform vec2 uSize;    // kích thước vùng vẽ (px)
uniform float uT;      // tiến trình 0..1
uniform vec3 uColor;   // màu cảnh giới (0..1)
uniform vec2 uCenter;  // tâm hiệu ứng (px)

out vec4 fragColor;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 d = fc - uCenter;
  float r = length(d);
  float ang = atan(d.y, d.x);
  float t = clamp(uT, 0.0, 1.0);
  float fade = 1.0 - t;

  // lõi sáng trắng-nóng, phình rồi tắt
  float core = exp(-r / (36.0 + 240.0 * t)) * fade * 1.5;

  // vòng xung kích (annulus) nở ra
  float ringR = 24.0 + t * 340.0;
  float ring = exp(-pow((r - ringR) / (16.0 + 34.0 * t), 2.0)) * fade * 1.1;

  // godray: tia góc phóng ra, thưa/dày tất định theo hash
  float seed = floor((ang + 3.14159) / 6.28318 * 32.0);
  float streak = 0.5 + 0.5 * sin(ang * 32.0 + hash(seed) * 12.0);
  streak = pow(streak, 8.0);
  float rayFall = exp(-r / (140.0 + 300.0 * t)) * smoothstep(0.0, 40.0, r);
  float rays = streak * rayFall * fade * 1.2;

  float glow = core + ring + rays;
  vec3 col = uColor * glow + vec3(1.0) * pow(core, 2.2) * 0.7;

  fragColor = vec4(col, clamp(glow, 0.0, 1.0));
}
