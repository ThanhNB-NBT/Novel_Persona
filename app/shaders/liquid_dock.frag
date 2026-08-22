#version 460 core
#include <flutter/runtime_effect.glsl>

// Vũng LINH DỊCH trong dock 5 tab. Vẽ thẳng lên canvas (Paint..shader).
//  · mặt vũng đọng ở đáy dock, gợn sóng liên tục (120fps ultra-fluid)
//  · mặt nước dâng thành gò dưới tab đang chọn, dãn tơ dính khi di chuyển (uFlow)
//  · giọt Tu Tiên ở giữa: méo theo sóng + 3 vệ tinh quay quanh
//  · tất cả hoà vào nhau bằng smooth-min (metaball SDF)
//  · đổ bóng/phản quang viền men (meniscus caustic highlight) chân thật

precision highp float;

uniform vec2 uSize;
uniform float uT;      // 0..2π, tuần hoàn
uniform float uSelX;   // tâm tab đang chọn (px)
uniform float uCent;   // 1 = tab giữa (Tu Tiên) đang được chọn
uniform float uFlow;   // 0..1: độ dãn dính khi đang chuyển giữa các tab
uniform vec3 uColor;   // màu linh dịch
uniform float uAlpha;  // độ đặc trong lòng vũng
uniform float uSplash; // 1 = vừa chạm, tắt dần về 0 theo Ticker 120fps
uniform float uSplashX; // nơi ngón tay chạm (px)

out vec4 fragColor;

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// SDF của toàn khối lỏng tại p (px). Âm = bên trong.
float field(vec2 p) {
  // 1. Mặt nước: sóng êm + gò dâng theo vị trí ngón tay/tab
  float wave = 1.2 * sin(p.x * 0.055 + uT * 2.0)
             + 0.8 * sin(p.x * 0.090 - uT * 3.0);

  // Gò dâng: khi đang kéo (uFlow > 0), gò dãn rộng và nâng cao mô phỏng sức căng bề mặt
  float spread = 28.0 + 12.0 * uFlow;
  float k = (p.x - uSelX) / spread;
  float hump = (28.0 + 10.0 * uFlow) * exp(-k * k);

  // Sóng gợn lan tỏa từ vị trí chạm
  float dx = abs(p.x - uSplashX);
  float ripple = 8.0 * uSplash * cos(dx * 0.15 - (1.0 - uSplash) * 16.0)
                 * exp(-dx * 0.022);

  float d = (uSize.y * 0.82 - hump + wave - ripple) - p.y;

  // Giọt bắn phụ khi chạm (fountain droplets)
  if (uSplash > 0.01) {
    float fly = 1.0 - uSplash;
    float up = 28.0 * fly * (1.0 - fly) * 4.0;
    for (int i = 0; i < 2; i++) {
      float dir = (i == 0) ? -1.0 : 1.0;
      vec2 c = vec2(uSplashX + dir * 18.0 * fly, uSize.y * 0.82 - up);
      d = smin(d, length(p - c) - (4.0 * uSplash), 5.0);
    }
  }

  // 2. Giọt Tu Tiên giữa dock: bán kính co dãn theo sóng
  vec2 q = p - vec2(uSize.x * 0.5, uSize.y * 0.5);
  float ang = atan(q.y, q.x);
  float wob = 0.07 + 0.05 * uCent;
  float rad = 14.0 + 3.5 * uCent;
  float r = rad * (1.0 + wob * sin(3.0 * ang + uT * 2.0)
                       + wob * 0.6 * sin(5.0 * ang - uT * 3.0));
  d = smin(d, length(q) - r, 9.0);

  // 3. Ba vệ tinh linh khí quay quanh giọt
  float orb = rad + mix(8.5, 3.0, uCent);
  for (int i = 0; i < 3; i++) {
    float a = uT * (1.0 + uCent * 0.5) + float(i) * 2.0944;
    vec2 o = vec2(cos(a), sin(a)) * (orb + 2.0 * sin(uT * 2.0 + float(i)));
    d = smin(d, length(q - o) - (3.2 + uCent * 0.8), 4.5);
  }
  return d;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float d = field(p);

  float inside = smoothstep(1.0, -1.0, d);
  if (inside <= 0.001) {
    fragColor = vec4(0.0);
    return;
  }

  // Pháp tuyến bề mặt = gradient SDF
  const float e = 1.2;
  vec2 n = normalize(vec2(field(p + vec2(e, 0.0)) - field(p - vec2(e, 0.0)),
                          field(p + vec2(0.0, e)) - field(p - vec2(0.0, e)))
                     + vec2(0.0001));

  // Khối nước dày ở giữa, trong suốt ở rìa
  float body = smoothstep(0.0, -14.0, d);
  vec3 col = uColor * (0.88 + 0.32 * body);

  // Phản quang men mặt nước (meniscus caustic highlight)
  float top = max(-n.y, 0.0);
  float film = exp(-abs(d) * 1.8) * pow(top, 1.6);
  col += vec3(0.95, 0.98, 1.0) * film * 0.95;
  col += top * pow(1.0 - body, 2.0) * 0.40;

  // Alpha gradient
  float a = uAlpha * (0.55 + 0.45 * body) * inside;
  a = min(a + film * 0.80 + exp(-abs(d) * 0.5) * 0.22 * inside, 1.0);

  fragColor = vec4(clamp(col, 0.0, 1.0) * a, a);
}
