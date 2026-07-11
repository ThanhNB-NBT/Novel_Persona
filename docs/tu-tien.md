# Hệ thống Tu Tiên — thiết kế & quy ước (nguồn sự thật duy nhất)

> Tài liệu này để MỌI phiên làm việc (Claude, ChatGPT/Codex, người) đọc trước khi
> đụng vào hệ Tu Tiên. Đổi thiết kế → SỬA FILE NÀY TRONG CÙNG COMMIT.
> Cập nhật lần cuối: 2026-07-11.

## 1. Tư tưởng chung

- **Game treo (idle) gắn với việc ĐỌC truyện**: đọc → nhận cơ duyên (vật phẩm) → tu vi
  tăng dần theo thời gian thực → lên tầng/đột phá. Không PvP, không pay.
- **Server là chuẩn**: mọi ghi qua RPC `SECURITY DEFINER` (Postgres, migration 039+).
  Client chỉ SELECT dòng của mình + gọi RPC. KHÔNG BAO GIỜ tin số client gửi lên.
- **Tick lười**: exp không có cron — `cult_tick()` tính bù thời gian trôi mỗi khi user
  gọi RPC bất kỳ (kẹp 48h offline, trần "bình cảnh" theo tầng).
- **Thiên Đạo sủng nhi** (từ migration 049): mọi phần thưởng THUẦN NGẪU NHIÊN,
  không khoá theo cảnh giới, không bảng trọng số. Luyện Khí tầng 1 vẫn có thể
  nhặt Tiên phẩm. Vui là chính.

## 2. Dữ liệu (Supabase)

| Bảng | Vai trò |
|---|---|
| `cult_items` | Catalog vật phẩm (seed trong migration). Cột `weight` KHÔNG còn dùng từ 049. |
| `user_cultivation` | 1 dòng/user: realm, stage, exp, linh_can, element, race, gender, buff, equip_* |
| `user_cult_items` | Kho đồ (user_id, item_id, qty) |
| `cult_claims` | Chương đã nhận quà (PK chặn nhận trùng) |

RPC (đều `to authenticated`): `cult_state()` · `cult_claim_gift(novel, index)` ·
`cult_use_item(id)` · `cult_equip(id)` · `cult_advance()` · `cult_set_avatar(race, gender)`.

### Loại vật phẩm & quy ước `effect` (jsonb)

| type | slot | effect | hiển thị trên nhân vật |
|---|---|---|---|
| `congphap` | equip_congphap | `{}` hệ số theo grade ×1.5→×24; có thể kèm `"element":"hoa"` (hợp linh căn ×1.3) | hiệu ứng aura bay quanh (map theo `code` trong `_auraFor`, cultivation.dart) |
| `vukhi` | equip_vukhi | `{"atk":N}` | sprite BAY QUANH người, quỹ đạo Lissajous (không tròn đều) |
| `phapbao` | equip_phapbao | `{"rate_pct":N}`; nếu là VÒNG SÁNG thêm `"halo":"nguyet"\|"tinh"\|"loi"\|"kim"` | halo: thay vòng sáng sau đầu bằng kiểu tương ứng |
| `phapchu` | equip_phapchu | `{"bt_pct":N}` (+đột phá) | không |
| `yphuc` | equip_yphuc | `{"def":N,"hp":N}` | KHÔNG hiển thị (đã chốt: giáp/giày không vẽ) |
| `giay` | equip_giay | `{"agi":N}` | không |
| `danduoc` | tiêu hao | `{"kind":"linhcan"\|"buff"\|"hothan"\|"element", ...}` | không |
| `linhthach` | tiêu hao | `{"kind":"stone","pct":N,"hours":H}` (cộng dồn với đan) | không |

Thêm vật phẩm mới = 1 migration INSERT `cult_items` (idempotent `on conflict (code) do nothing`),
KHÔNG cần sửa app — client render động từ catalog. Sprite (`pixel`) phải tồn tại
trong `_sprites` (pixel.dart), không có thì fallback 'pill' xấu.

### Công thức (SQL là chuẩn, Dart chỉ mirror để HIỂN THỊ)

- Tốc độ tu: `cult_base_rate()` — nền theo realm × hệ số công pháp (grade) × hợp hệ 1.3
  × buff đan × linh thạch × passive tộc.
- Chỉ số: `cult_stats()` — nền ×1.12/tầng + trang bị; tộc Yêu ×1.3 atk/hp, Linh ×1.3 thần thức.
- Đột phá: `85 − 8×(realm−1) + đan hộ thân + pháp chú`, kẹp [10,100]; fail −30% exp
  (Linh tộc mất nửa), Nhân +5%, Ma −5%.
- **Tâm Ma** (migration 054, CHỈ đại cảnh giới stage 9→realm+1): server tính 1 lần từ
  5 chỉ số — mức vũ trang `(atk+def+hp+agi có đồ)/(87×base tay không)` + thần thức
  (Linh tộc ×1.3), nền 35% kẹp [15,90]. Thắng → `+15%` đột phá & giảm NỬA tổn thất;
  thua → đột phá thường, KHÔNG khóa tiến trình. Hằng số là heuristic, chỉnh trong 054.
- **Cơ duyên**: chương có quà ⇔ `md5(uid:novel:index)[0..6] % 100 < 50` (~50% chương).
  Rơi đồ: `select * from cult_items order by random() limit 1` — đều tăm tắp.
- **Đan/linh thạch tăng tốc (`buff`/`stone`)**: `cult_use_item` (migration 052) TỪ CHỐI
  nếu đang có buff cùng loại MẠNH HƠN còn hạn (dùng `>` → cùng mức vẫn làm mới được).
  Không tiêu mất món khi bị từ chối (raise → rollback). Tránh bấm nhầm đè +300% bằng +30%.

### ⚠️ Các cặp MIRROR SQL ↔ Dart — sửa một là PHẢI sửa hai

| Logic | SQL | Dart |
|---|---|---|
| Chương có quà (50%) | `cult_gift_at` (049) | `giftAt` — app/lib/cultivation.dart |
| Hash vị trí quà trong chương | như trên | `giftHash` (cùng file) |
| Tỷ lệ đột phá hiển thị (có +5/−5 tộc) | `cult_advance` (044) | `cultBreakthroughChance` — app/lib/cultivation.dart (có test `cult_chance_test.dart`) |
| Hệ số công pháp ×1.5→×24 | `cult_mult` | `_cpMult` + `_EquipRow._bonus` |

## 3. Lớp hình ảnh (client-only, không đụng DB)

File map:
- `app/lib/screens/cultivation/cultivation.dart` — màn hình + các painter cảnh.
- `app/lib/screens/cultivation/pixel.dart` — sprite 12×12 + palette phẩm + `paintOrbitSprite`.
- `app/assets/cultivators/{human|fox|demon|spirit}_{male|female}.webp` — ảnh nhân vật
  (CHỈ webp được bundle; PNG là file gốc không ship — bug 1.0.2 vì trỏ .png).
- `app/assets/cult_items/*.webp` — 27 minh hoạ vật phẩm theo `pixel` key trong catalog;
  một hình dùng lại cho mọi item cùng key, còn phẩm cấp thể hiện bằng viền/màu UI.
- `app/assets/cult_fx/sword_wheel.webp` — kiếm luân ngũ sắc sau đầu, xoay trực tiếp như một ảnh
  có nền trong suốt; không dựng lại bằng nét Canvas đơn giản.

Bố cục cảnh `_AnimatedCultivator` (canvas 150×145, loop 4s), vẽ theo thứ tự:
1. `_SkyPainter` (nền): sao (realm 5+) → **kiếm luân ngũ sắc sau ĐẦU** (5 kiếm neo theo
   đỉnh ngũ giác, quay thành quỹ đạo tròn; pháp bảo Lôi quay nhanh hơn) → bóng chân tự nhiên → quầng thở → sương trôi
   → đom đóm linh khí bay lên.
2. Ảnh nhân vật chibi tu tiên (Image.asset, ~104×128, hạ thấp để đầu lọt tâm halo):
   nét viền đậm, mảng màu ít, toàn thân nhỏ gọn; mỗi tộc/giới có bộ WebP riêng. Ảnh
   nhấp nhô ±4px, trôi ngang/nhún tỉ lệ/nghiêng rất nhẹ để có idle 2.5D; aura và vũ khí
   tiếp tục ở lớp trước. Đây không phải rig 3D — muốn tóc/tay áo chuyển động độc lập cần
   bộ asset tách layer riêng.
3. `_AuraPainter` (trước): hiệu ứng công pháp (qi/ice/wind/earth/sword/gold/star/fire/leaf)
   + **vũ khí đang đeo bay quanh** (`paintOrbitSprite`, quỹ đạo bán kính dao động).
4. `_CultivationBackdrop`: sương linh khí, điểm sáng và mây màu cảnh giới phủ cả màn,
   kể cả vùng sau status bar. Nội dung vẫn nằm trong `SafeArea`; status bar trong suốt,
   icon thời gian/pin/sóng sáng để không mất khả năng đọc.

Quy ước màu: KHÔNG hardcode màu cảnh giới — dùng `gradeColor((realm+1)~/2)`;
màu hiệu ứng theo `_auraFor(cpCode)`. Nền thẻ/section theo ColorScheme app.

**Soi hình khi sửa painter** (không cần điện thoại):
```
cd app && flutter test test/scene_render_test.dart
# → build/scene_preview.png — MỞ RA NHÌN trước khi commit
```

**Nền tranh màn Tu Tiên**: `app/assets/bg/cultivation_bg.webp` là bản ban ngày,
`app/assets/bg/cultivation_bg_night.webp` là bản Dạ Lam; app tự chọn theo theme.
Cả hai là tranh thủy mặc dọc, vùng giữa thoáng để đặt nhân vật; code tự về gradient
nếu asset lỗi tải.

**Cơ chế màu vòng/aura** (`_auraFor`): 1. code công pháp có kiểu riêng →
override; 2. hệ trong effect công pháp; 3. hệ LINH CĂN người chơi; 4. màu cảnh
giới (đã lerp trắng/đen theo nền tối/sáng để không chìm vào backdrop cùng màu).

**Frame idle phụ (tùy chọn, code tự nhận)**: đặt cạnh ảnh gốc trong
`app/assets/cultivators/` với hậu tố `_f2`..`_f4` (vd `human_male_f2.webp`)
là nhân vật tự chạy ping-pong 1..n..1 (~2fps), không cần sửa code; frame phải
liền số (thiếu `_f2` thì `_f3` bị bỏ qua). Spec khi nhờ AI vẽ frame phụ:
CÙNG nhân vật/pose/khung hình/kích thước với ảnh gốc, nền trong suốt, chỉ
xê dịch chi tiết nhẹ (vạt áo + tóc lệch 1 nhịp gió, có thể 1 frame nhắm mắt),
xuất webp cùng cỡ.

## 4. Quy trình bắt buộc khi sửa hệ Tu Tiên (người & AI)

1. Đọc file này trước. Đổi thiết kế → cập nhật file này cùng commit.
2. Migration mới = file `supabase/migrations/0xx_ten.sql` số THỨ TỰ tiếp theo,
   idempotent khi có thể; áp bằng `supabase db push --linked`. KHÔNG sửa migration cũ đã push.
3. Sửa cặp mirror SQL↔Dart (bảng ở §2) đủ cả hai đầu.
4. `cd app && flutter analyze <file đã sửa>` — 0 lỗi 0 warning mới.
5. Painter/sprite → chạy render test, MỞ PNG nhìn bằng mắt.
6. KHÔNG commit khi chưa làm bước 4-5. KHÔNG tự tag/release — user quyết.
7. Asset ảnh: chỉ thêm .webp vào pubspec; PNG gốc để ngoài repo.

## 5. Trạng thái & roadmap

Đã có (migration 039→055): exp/realm/stage + đột phá · 8 loại vật phẩm ~100 món ·
ngũ hành linh căn · 5 chỉ số · tộc/giới tính + ảnh nhân vật · cơ duyên 50% uniform ·
hero stage + thẻ tilt + đĩa dock bát quái · **Tâm Ma khi đại cảnh giới (054)** ·
**Luyện hóa đồ trùng → tu vi (053)** · **Bộ sưu tập vật phẩm (UI)** ·
**Phi Thăng ở đỉnh Độ Kiếp → danh hiệu Tiên Nhân (055)**.

Roadmap (chưa làm, làm theo thứ tự user chọn):
- Halo/hiệu ứng nhân vật đặc biệt hậu Phi Thăng (hiện chỉ có danh hiệu chữ).
- "Đã từng thu thập" cho Bộ sưu tập (hiện chỉ tính đồ đang có qty>0 — cần bảng mới).
- Shop / tiền tệ linh thạch (nguồn: quà trùng → tự bán?).
- Tông môn, xếp hạng (cần chống gian lận — lúc đó mới siết claim theo reading_progress).
- Thành tựu.
- Rig tách layer tóc/tay áo cho idle 2.5D sâu hơn (bộ chibi hiện tại dùng 1 layer/nhân vật).
