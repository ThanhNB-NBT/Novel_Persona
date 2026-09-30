#version 460 core
#include <flutter/runtime_effect.glsl>

// Tâm Ma 3D: khối ma khí THỂ TÍCH (ray-march qua nhiễu 3D) xoáy quanh trục đứng,
// lõi phát sáng chiếu xuyên khói + vành đai khí nghiêng như đĩa bồi tụ. Máy quay lắc
// nhẹ quanh khối → thấy rõ chiều sâu. Vẽ 2 lượt: sau mặt quỷ (uFront=0, có lõi) và
// trước mặt quỷ (uFront=1, khói mỏng) → khói/đai khí cuốn TRƯỚC và SAU ảnh.

precision highp float;

uniform vec2 uSize;
uniform vec2 uCenter;  // tâm khối (px, toạ độ cục bộ)
uniform float uRadius; // bán kính khối (px)
uniform float uTime;   // giây
uniform float uV;      // tiến trình pha Tâm Ma 0..1
uniform float uWin;    // 1 = áp chế được (tím, co lại), 0 = tâm ma trỗi dậy (đỏ, bùng)
uniform float uFront;  // 0 = nửa sau, 1 = nửa trước

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
  for (int i = 0; i < 3; i++) {
    s += a * noise(p);
    p = p * 2.03 + vec3(1.7, 9.2, 3.1);
    a *= 0.5;
  }
  return s;
}

mat2 rot(float a) {
  float c = cos(a), s = sin(a);
  return mat2(c, -s, s, c);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 uv = (fc - uCenter) / uRadius; // khối nằm trong |uv| < ~1.1
  uv.y = -uv.y;

  float win = uWin;
  float intro = smoothstep(0.0, 0.25, uV);
  float settle = smoothstep(0.55, 1.0, uV);
  // áp chế: co khối + lõi chuyển trắng; trỗi dậy: phình + dày khói
  float R = mix(0.35, 1.0, intro) * mix(1.0 + 0.2 * settle, 1.0 - 0.4 * settle, win);
  float dens = mix(1.0 + 0.6 * settle, 1.0 - 0.55 * settle, win);
  float spin = mix(1.9, 1.0, win);

  // máy quay quỹ đạo lắc nhẹ + nghiêng xuống
  float yaw = 0.45 * sin(uTime * 0.9);
  float pitch = 0.32 + 0.08 * sin(uTime * 0.7);
  vec3 ro = vec3(0.0, 0.0, -3.2);
  vec3 rd = normalize(vec3(uv * 0.62, 1.9));
  ro.yz *= rot(pitch); rd.yz *= rot(pitch);
  ro.xz *= rot(yaw);   rd.xz *= rot(yaw);

  // giao cầu bao
  float bR = 1.35 * max(R, 0.6);
  float b = dot(ro, rd);
  float c = dot(ro, ro) - bR * bR;
  float h = b * b - c;
  if (h <= 0.0) { fragColor = vec4(0.0); return; }
  h = sqrt(h);
  float t0 = -b - h, t1 = -b + h;
  // tách nửa trước/sau theo mặt phẳng vuông góc tia qua tâm
  float tm = -b;
  if (uFront > 0.5) t1 = tm; else t0 = tm;

  vec3 smokeCol = mix(vec3(0.34, 0.03, 0.05), vec3(0.20, 0.06, 0.42), win);
  vec3 coreCol  = mix(vec3(1.0, 0.28, 0.12), vec3(0.72, 0.52, 1.0), win);
  coreCol = mix(coreCol, vec3(1.0, 0.95, 1.0), settle * win);
  float flick = 0.85 + 0.15 * sin(uTime * 23.0) * sin(uTime * 7.3) * (1.0 - win);

  const int STEPS = 22;
  float dt = (t1 - t0) / float(STEPS);
  float T = 1.0;
  vec3 col = vec3(0.0);
  float frontThin = mix(1.0, 0.45, uFront);
  for (int i = 0; i < STEPS; i++) {
    vec3 p = ro + rd * (t0 + (float(i) + 0.5) * dt);
    float r = length(p);
    // xoáy: góc quay tăng về gần trục + theo độ cao → dải khói cuộn xoắn
    vec3 q = p;
    float rr = length(q.xz);
    q.xz *= rot(uTime * spin + 1.6 / (0.4 + rr) + q.y * 1.2);
    float n = fbm(q * 2.1 + vec3(0.0, -uTime * 0.8, 0.0));
    float shell = 1.0 - r / R;
    float d = clamp(n * 1.5 - 0.5 + shell * 0.9, 0.0, 1.0) * smoothstep(-0.1, 0.25, shell);
    // đai khí nghiêng (torus) ngoài khối
    float tor = length(vec2(rr - 0.95 * R, p.y + 0.15 * sin(atan(p.z, p.x) * 3.0 + uTime * 2.0)));
    d += smoothstep(0.22 * R, 0.0, tor) * (0.4 + 0.9 * n);
    d *= dens * frontThin;
    if (d > 0.001) {
      float light = exp(-r * 2.6 / max(R, 0.3)) * 3.2 * flick;
      // vân khói: dải n cao sáng, khe n thấp tối → nhìn ra khối cuộn thay vì cục mờ
      float vein = n * n * 2.2;
      vec3 e = smokeCol * (0.25 + vein) + coreCol * light * (0.4 + vein);
      float a = d * dt * 4.5;
      col += T * e * a;
      T *= exp(-a * 1.5);
      if (T < 0.02) break;
    }
  }

  // lõi rực (chỉ lượt sau): nhìn qua khói
  if (uFront < 0.5) {
    float g = length(uv) / max(R, 0.3);
    float core = exp(-g * 5.0) * 1.3 * flick * intro;
    col += coreCol * core * T;
  }

  col = 1.0 - exp(-col * 1.3);
  float alpha = clamp(1.0 - T, 0.0, 1.0);
  fragColor = vec4(col, max(alpha, 0.0));
}
