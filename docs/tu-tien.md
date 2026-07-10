# Hệ thống Tu Tiên — thiết kế & quy ước (nguồn sự thật duy nhất)

> Tài liệu này để MỌI phiên làm việc (Claude, ChatGPT/Codex, người) đọc trước khi
> đụng vào hệ Tu Tiên. Đổi thiết kế → SỬA FILE NÀY TRONG CÙNG COMMIT.
> Cập nhật lần cuối: 2026-07-10.

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
- **Cơ duyên**: chương có quà ⇔ `md5(uid:novel:index)[0..6] % 100 < 50` (~50% chương).
  Rơi đồ: `select * from cult_items order by random() limit 1` — đều tăm tắp.

### ⚠️ Các cặp MIRROR SQL ↔ Dart — sửa một là PHẢI sửa hai

| Logic | SQL | Dart |
|---|---|---|
| Chương có quà (50%) | `cult_gift_at` (049) | `giftAt` — app/lib/cultivation.dart |
| Hash vị trí quà trong chương | như trên | `giftHash` (cùng file) |
| Tỷ lệ đột phá hiển thị | `cult_advance` | `_RealmCard.chance` — cultivation.dart màn hình |
| Hệ số công pháp ×1.5→×24 | `cult_mult` | `_cpMult` + `_EquipRow._bonus` |

## 3. Lớp hình ảnh (client-only, không đụng DB)

File map:
- `app/lib/screens/cultivation/cultivation.dart` — màn hình + các painter cảnh.
- `app/lib/screens/cultivation/pixel.dart` — sprite 12×12 + palette phẩm + `paintOrbitSprite`.
- `app/assets/cultivators/{human|fox|demon|spirit}_{male|female}.webp` — ảnh nhân vật
  (CHỈ webp được bundle; PNG là file gốc không ship — bug 1.0.2 vì trỏ .png).

Bố cục cảnh `_AnimatedCultivator` (canvas 150×145, loop 4s), vẽ theo thứ tự:
1. `_SkyPainter` (nền): sao (realm 5+) → **vòng sáng sau ĐẦU** (halo — kiểu theo pháp bảo
   vòng đang đeo, mặc định vòng trơn màu cảnh giới, tâm đặt TRÙNG ĐẦU nhân vật) →
   **trận pháp dưới chân** (ellipse xoay chậm màu công pháp) → quầng thở → sương trôi
   → đom đóm linh khí bay lên.
2. Ảnh nhân vật chibi tu tiên (Image.asset, ~104×128, hạ thấp để đầu lọt tâm halo):
   nét viền đậm, mảng màu ít, toàn thân nhỏ gọn; mỗi tộc/giới có bộ WebP riêng. Ảnh
   nhấp nhô ±4px, trôi ngang/nhún tỉ lệ/nghiêng rất nhẹ để có idle 2.5D; aura và vũ khí
   tiếp tục ở lớp trước. Đây không phải rig 3D — muốn tóc/tay áo chuyển động độc lập cần
   bộ asset tách layer riêng.
3. `_AuraPainter` (trước): hiệu ứng công pháp (qi/ice/wind/earth/sword/gold/star/fire/leaf)
   + **vũ khí đang đeo bay quanh** (`paintOrbitSprite`, quỹ đạo bán kính dao động).

Quy ước màu: KHÔNG hardcode màu cảnh giới — dùng `gradeColor((realm+1)~/2)`;
màu hiệu ứng theo `_auraFor(cpCode)`. Nền thẻ/section theo ColorScheme app.

**Soi hình khi sửa painter** (không cần điện thoại):
```
cd app && flutter test test/scene_render_test.dart
# → build/scene_preview.png — MỞ RA NHÌN trước khi commit
```

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

Đã có (migration 039→049): exp/realm/stage + đột phá · 8 loại vật phẩm ~100 món ·
ngũ hành linh căn · 5 chỉ số · tộc/giới tính + ảnh nhân vật · cơ duyên 50% uniform ·
hero stage + thẻ tilt + đĩa dock bát quái.

Roadmap (chưa làm, làm theo thứ tự user chọn):
- Combat tâm ma khi độ kiếp (dùng atk/def/hp/agi/thần thức — hiện stats chỉ để ngắm).
- Shop / tiền tệ linh thạch (nguồn: quà trùng → tự bán?).
- Tông môn, xếp hạng (cần chống gian lận — lúc đó mới siết claim theo reading_progress).
- Thành tựu.
- Rig tách layer tóc/tay áo cho idle 2.5D sâu hơn (bộ chibi hiện tại dùng 1 layer/nhân vật).
