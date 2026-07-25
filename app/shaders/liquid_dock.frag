#version 460 core
#include <flutter/runtime_effect.glsl>

// Vũng LINH DỊCH trong dock 5 tab. Vẽ thẳng lên canvas (Paint..shader) chứ KHÔNG
// qua ImageFilter.shader — đường đó chỉ chạy trên Impeller và hỏng thì im lặng.
//  · mặt vũng đọng ở đáy dock, gợn sóng liên tục
//  · mặt nước dâng thành gò dưới tab đang chọn (thay cho "ô chạy")
//  · giọt Tu Tiên ở giữa: méo theo sóng + 3 vệ tinh quay quanh
//  · tất cả hoà vào nhau bằng smooth-min → gooey thật (metaball)
//  · đổ bóng/highlight theo pháp tuyến bề mặt → chất thuỷ tinh dày

precision highp float;

uniform vec2 uSize;
uniform float uT;      // 0..2π, tuần hoàn (hệ số thời gian phải là số nguyên)
uniform float uSelX;   // tâm tab đang chọn (px)
uniform float uCent;   // 1 = tab giữa (Tu Tiên) đang được chọn
uniform float uFlow;   // 0..1: đang chảy sang tab khác
uniform vec3 uColor;   // màu linh dịch
uniform float uAlpha;  // độ đặc trong lòng vũng
uniform float uSplash; // 1 = vừa chạm, tắt dần về 0
uniform float uSplashX; // nơi ngón tay chạm (px)

out vec4 fragColor;

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// SDF của toàn khối lỏng tại p (px). Âm = bên trong.
float field(vec2 p) {
  // 1. mặt vũng: sóng nền + gò dâng dưới tab đang chọn (chảy thì gò cao hơn)
  float wave = 1.4 * sin(p.x * 0.055 + uT * 2.0)
             + 0.9 * sin(p.x * 0.090 - uT * 3.0);
  // mực nước nền thấp (0.82) để chữ các tab KHÔNG bị cắt ngang; chỉ gò dưới tab
  // đang chọn mới dâng cao ôm lấy icon → vẫn đủ làm chỉ báo tab
  float k = (p.x - uSelX) / 28.0;
  float hump = (30.0 + 8.0 * uFlow) * exp(-k * k);

  // sóng lan từ chỗ vừa chạm: vòng gợn chạy ra hai bên rồi tắt
  float dx = abs(p.x - uSplashX);
  float ripple = 7.0 * uSplash * cos(dx * 0.13 - (1.0 - uSplash) * 14.0)
                 * exp(-dx * 0.018);

  float d = (uSize.y * 0.82 - hump + wave - ripple) - p.y;

  // hai giọt bắn lên từ chỗ chạm rồi rơi xuống theo parabol
  float fly = 1.0 - uSplash;              // 0 lúc bắn → 1 lúc tắt
  float up = 26.0 * fly * (1.0 - fly) * 4.0;
  for (int i = 0; i < 2; i++) {
    float dir = (i == 0) ? -1.0 : 1.0;
    vec2 c = vec2(uSplashX + dir * 16.0 * fly, uSize.y * 0.82 - up);
    d = smin(d, length(p - c) - 4.5 * uSplash, 6.0);
  }

  // 2. giọt Tu Tiên giữa dock: bán kính méo theo hai sóng lệch pha
  vec2 q = p - vec2(uSize.x * 0.5, uSize.y * 0.5);
  float ang = atan(q.y, q.x);
  float wob = 0.08 + 0.06 * uCent;
  float rad = 14.0 + 3.0 * uCent;
  float r = rad * (1.0 + wob * sin(3.0 * ang + uT * 2.0)
                       + wob * 0.7 * sin(5.0 * ang - uT * 3.0));
  d = smin(d, length(q) - r, 10.0);

  // 3. ba vệ tinh quay quanh giọt; được chọn thì quỹ đạo co lại, dính vào thân
  float orb = rad + mix(8.0, 3.0, uCent);
  for (int i = 0; i < 3; i++) {
    float a = uT * (1.0 + uCent) + float(i) * 2.0944;
    vec2 o = vec2(cos(a), sin(a)) * (orb + 2.0 * sin(uT * 2.0 + float(i)));
    d = smin(d, length(q - o) - (3.4 + uCent), 5.0);
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

  // pháp tuyến bề mặt = gradient SDF (sai phân hữu hạn)
  const float e = 1.5;
  vec2 n = normalize(vec2(field(p + vec2(e, 0.0)) - field(p - vec2(e, 0.0)),
                          field(p + vec2(0.0, e)) - field(p - vec2(0.0, e)))
                     + vec2(0.0001));

  // dày ở giữa, mỏng ở mép → chất lỏng có khối, không phải mảng màu bẹt
  float body = smoothstep(0.0, -12.0, d);
  vec3 col = uColor * (0.85 + 0.35 * body);

  // ĐƯỜNG MẶT THOÁNG: dải sáng mảnh bám đúng mặt trên khối lỏng. Thiếu nó thì
  // mắt đọc vũng nước thành mảng sương, không ra chất lỏng.
  float top = max(-n.y, 0.0);
  float film = exp(-abs(d) * 1.7) * pow(top, 1.5);
  col += film * 0.9;
  col += top * pow(1.0 - body, 2.0) * 0.45;

  float a = uAlpha * (0.55 + 0.45 * body) * inside;
  a = min(a + film * 0.75 + exp(-abs(d) * 0.6) * 0.20 * inside, 1.0);

  fragColor = vec4(clamp(col, 0.0, 1.0) * a, a); // Flutter cần premultiplied
}
