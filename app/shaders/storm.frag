#version 460 core
#include <flutter/runtime_effect.glsl>

// Trần mây kiếp 3D: nhìn từ dưới lên một lớp mây THỂ TÍCH (ray-march qua nhiễu 3D)
// có phối cảnh — mây gần to và rõ trên đỉnh màn, xa dần nhỏ lại về đường chân trời.
// Tia sét là nguồn sáng NẰM TRONG mây: khi đánh, khối mây quanh gốc sét bừng sáng
// và ánh sáng tán xạ ra xung quanh (chỗ mây dày tối hơn, mép mây rực hơn).

precision highp float;

uniform vec2 uSize;
uniform float uTime;   // giây
uniform float uEnv;    // độ hiện trời kiếp 0..1
uniform float uFlash;  // cường độ cú đánh 0..1
uniform float uFlashX; // gốc sét trên màn (px)
uniform float uSheet;  // chớp ẩn trong mây 0..1
uniform vec2 uSheetAt; // vị trí chớp ẩn (px)

out vec4 fragColor;

float hash(vec3 p) {
  p = fract(p * 0.3183099 + 0.1);
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
                 mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
                 mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
             f.z);
}

float fbm(vec3 p) {
  float a = 0.5, s = 0.0;
  for (int i = 0; i < 4; i++) {
    s += a * noise(p);
    p = p * 2.02 + vec3(3.1, 1.7, 5.3);
    a *= 0.5;
  }
  return s;
}

const float BASE = 1.0; // đáy mây
const float TOP = 2.4;  // đỉnh mây

// điểm màn hình → hướng tia (máy quay ngửa lên)
vec3 ray(vec2 px) {
  vec2 uv = (px - vec2(uSize.x * 0.5, 0.0)) / uSize.y;
  return normalize(vec3(uv.x * 1.1, 0.42 - uv.y, 1.0));
}

// nguồn sáng thế giới: chiếu điểm màn hình lên giữa lớp mây
vec3 lightAt(vec2 px) {
  vec3 d = ray(px);
  return d * ((BASE + 0.35) / max(d.y, 0.08));
}

float density(vec3 p) {
  vec3 q = p * 0.55 + vec3(uTime * 0.08, 0.0, uTime * 0.05);
  float n = fbm(q);
  // cuộn: mây dày ở giữa lớp, mỏng ở đáy/đỉnh
  float h = (p.y - BASE) / (TOP - BASE);
  float prof = smoothstep(0.0, 0.25, h) * smoothstep(1.0, 0.55, h);
  return clamp((n - 0.32) * 3.0, 0.0, 1.0) * prof;
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec3 rd = ray(fc);
  if (rd.y < 0.06 || uEnv <= 0.0) { fragColor = vec4(0.0); return; }

  float t0 = BASE / rd.y;
  float t1 = min(TOP / rd.y, t0 + 5.0);
  const int STEPS = 14;
  float dt = (t1 - t0) / float(STEPS);

  vec3 L1 = lightAt(vec2(uFlashX, uSize.y * 0.02));
  vec3 L2 = lightAt(uSheetAt);

  float T = 1.0;
  vec3 col = vec3(0.0);
  // lệch điểm bắt đầu theo hash pixel → bớt vân sọc do ít bước
  float jit = hash(vec3(fc, uTime));
  for (int i = 0; i < STEPS; i++) {
    vec3 p = rd * (t0 + (float(i) + jit) * dt);
    float d = density(p);
    if (d > 0.002) {
      // ánh sáng trong mây: suy giảm theo khoảng cách tới nguồn (tán xạ thể tích)
      float l1 = uFlash * 3.2 / (1.0 + dot(p - L1, p - L1) * 1.6);
      float l2 = uSheet * 2.6 / (1.0 + dot(p - L2, p - L2) * 2.4);
      // phía dưới mây (đáy) nhận ánh sáng đất lờ mờ, phía trên tối hẳn
      float h = (p.y - BASE) / (TOP - BASE);
      vec3 amb = mix(vec3(0.20, 0.22, 0.34), vec3(0.05, 0.05, 0.10), h);
      // lõi mây dày tự che bóng → tối hơn, mép mỏng rực hơn (giả tán xạ, không march phụ)
      float edge = 1.0 - 0.7 * d;
      vec3 e = amb + (vec3(0.62, 0.72, 1.0) * l1 + vec3(0.55, 0.6, 1.0) * l2) * edge;
      float a = d * dt * 1.8;
      col += T * e * a;
      T *= exp(-a * 1.6);
      if (T < 0.03) break;
    }
  }
  // xa dần về chân trời: mờ vào nền tối
  float far = smoothstep(0.06, 0.2, rd.y);
  float alpha = (1.0 - T) * far * uEnv;
  col = 1.0 - exp(-col * 1.4); // tone-map: sáng mạnh vẫn giữ vân mây, không cháy trắng
  fragColor = vec4(col * far * uEnv, alpha);
}
