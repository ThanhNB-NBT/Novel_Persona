# Hệ thống Tu Tiên — thiết kế & quy ước (nguồn sự thật duy nhất)

> Tài liệu này để MỌI phiên làm việc (Claude, ChatGPT/Codex, người) đọc trước khi
> đụng vào hệ Tu Tiên. Đổi thiết kế → SỬA FILE NÀY TRONG CÙNG COMMIT.
> Cập nhật lần cuối: 2026-07-13.

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
| `user_cultivation` | 1 dòng/user: realm, stage, exp, **elements[] (bộ hệ cố định), variant (dị/thiên căn), linh_can (nay = mức luyện căn/refine)**, race, gender, tien_tier, **halos[] + halo_worn (trận pháp hào quang hậu phi thăng)**, buff, equip_* |
| `user_cult_items` | Kho đồ (user_id, item_id, qty) |
| `user_cult_collection` | Lịch sử vật phẩm từng sở hữu; trigger từ kho, không mất khi qty về 0 |
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
| `danduoc` | tiêu hao | `{"kind":"linhcan"\|"buff"\|"hothan"\|"element", ...}` — `linhcan`(Tẩy Tủy Đan)=+refine CHỈ tăng tốc; `element`(Chuyển Linh Đan)=tráo lại BỘ HỆ giữ nguyên SỐ hệ (dị/thiên căn không tráo được) | không |
| `linhthach` | tiêu hao | `{"kind":"stone","pct":N,"hours":H}` (cộng dồn với đan) | không |

Thêm vật phẩm mới = 1 migration INSERT `cult_items` (idempotent `on conflict (code) do nothing`),
KHÔNG cần sửa app — client render động từ catalog. Sprite (`pixel`) phải tồn tại
trong `_sprites` (pixel.dart), không có thì fallback 'pill' xấu.

### Công thức (SQL là chuẩn, Dart chỉ mirror để HIỂN THỊ)

- **Linh căn** (migration 067): `elements[]` là BỘ HỆ ngũ hành CỐ ĐỊNH trời định
  (`cult_assign_root`, tạp phổ biến, dị/thiên căn 2%). Tên bậc = số hệ (5 Ngũ Hành Tạp →
  1 Đơn, ít hệ = thuần = nhanh) hoặc tên `variant` (thien/hon/kiem/loi/bang/phong/am).
  Tốc độ linh căn = `cult_linhcan_mult(elements, variant)` × `(1 + 0.1×(linh_can−1))`
  (refine từ Tẩy Tủy Đan). Hợp hệ ×1.3 nếu công pháp trùng 1 hệ trong bộ / 'all' /
  chủ nhân Hỗn Độn căn. Đổi `elements` KHÔNG đổi tốc trực tiếp — tốc theo SỐ hệ.
- Tốc độ tu: `cult_base_rate()` — công pháp(grade) × hợp hệ 1.3 × **linh căn (mult×refine)**
  × tộc Ma 1.10 × **buff cấp Tiên (1+0.2×tien_tier)** × buff đan/linh thạch/pháp bảo.
- Chỉ số: `cult_stats()` — nền ×1.12/tầng **× buff cấp Tiên (1+0.15×tien_tier)** + trang bị;
  tộc Yêu ×1.3 atk/hp, Linh ×1.3 thần thức.
- Đột phá: `85 − 8×(realm−1) + đan hộ thân + pháp chú`, kẹp [10,100]; fail −30% exp
  (Linh tộc mất nửa), Nhân +5%, Ma −5%.
- **Tâm Ma** (migration 054, CHỈ đại cảnh giới stage 9→realm+1): server tính 1 lần từ
  5 chỉ số — mức vũ trang `(atk+def+hp+agi có đồ)/(87×base tay không)` + thần thức
  (Linh tộc ×1.3), nền 35% kẹp [15,90]. Thắng → `+15%` đột phá & giảm NỬA tổn thất;
  thua → đột phá thường, KHÔNG khóa tiến trình. Hằng số là heuristic, chỉnh trong 054.
- **Cấp bậc Tiên hậu Phi Thăng** (migration 064): sau `ascended_at`, `cult_tick` BỎ trần
  Độ Kiếp, đổi sang trần `cult_tien_req(tien_tier)` (= đỉnh Độ Kiếp × 1.6^(tier+1)); đầy
  bar → RPC `cult_ascend_tier` thăng 1 bậc (`tien_tier`++), exp về 0, KHÔNG Tâm Ma/phạt.
  7 bậc: Tiên Nhân(0)→Địa Tiên→Thiên Tiên→Kim Tiên→Thái Ất Kim Tiên→Đại La Kim Tiên→
  Đạo Tổ(6, `cult_tien_max`). `cult_state` hậu phi thăng trả `req`=mốc bậc kế + `tien_tier`.
  Từ **067**: mỗi lần Độ Thiên Kiếp có **Tâm Ma** (chỉ số/trang bị càng mạnh, cơ hội càng
  cao; thắng → thăng bậc exp về 0; thua → giữ bậc, hao 20% tiên nguyên) + buff thật theo
  bậc (rate ×1.2/bậc, chỉ số ×1.15/bậc). Nút "Độ Thiên Kiếp"; snackbar báo thắng/thua.
- **Cơ duyên**: chương có quà ⇔ `md5(uid:novel:index)[0..6] % 100 < 50` (~50% chương).
  Rơi đồ: `select * from cult_items order by random() limit 1` — đều tăm tắp.
- **Trận pháp hào quang** (migration 068, CHỈ hậu Phi Thăng): cosmetic đội THẲNG lên nhân
  vật, KHÔNG nằm ô trang bị, không ảnh hưởng chỉ số. `halos[]` sở hữu + `halo_worn` đang
  đội. Rơi kèm cơ duyên: `cult_claim_gift` khi `ascended_at` có → 30% bổ sung 1 trận CHƯA
  sở hữu (đội luôn nếu chưa đội gì), trả field `halo`. `cult_wear_halo(code|null)` đội/cởi
  (validate `cult_halo_codes()`, phải sở hữu hoặc admin). `cult_admin_grant_halos()` (admin,
  dev) nhận trọn bộ. 6 trận: thai_duong/luc_du/huyen_tuyet/bach_ngan/hoang_kim/huyet_long.
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
| Bậc tiên hậu phi thăng (7 bậc) | `cult_tien_max` (064) | `tienTierNames`/`tienDaoTitles` — app/lib/cultivation.dart (test `scene_render_test.dart`) |
| Tên bậc linh căn (số hệ + dị căn) | `cult_linhcan_mult`/`cult_assign_root` (067) | `rootName`/`linhCanVariants` — app/lib/cultivation.dart; hợp hệ theo `elements` |

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
- `app/assets/cult_halo/{code}.webp` — 6 trận pháp hào quang hậu Phi Thăng (đội sau lưng);
  code khớp `tienHalos` (cultivation.dart) + `cult_halo_codes()` (068). Ảnh gốc để ngoài repo.
- `app/assets/cult_fx/heart_demon.webp` — linh thể Tâm Ma riêng, thay biểu tượng lá bùa dùng lại.

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

Hậu Phi Thăng, `_SkyPainter` nhận `tienTier` (0..6; -1 = chưa phi thăng) → vẽ **hào quang
cõi tiên** sau đầu (`_drawTienCorona`): đĩa vàng ấm + tia sáng xoay, càng lên bậc càng
nhiều tia + rực. Hero đổi tên cảnh giới → tên bậc tiên, đạo hiệu → `tienDaoTitles`, ẩn pill
tầng; nút đột phá đổi thành "Độ Thiên Kiếp · <bậc kế>", tới Đạo Tổ thì khoá.
`_SkyPainter` cũng nhận `elements` (bộ hệ linh căn) → `_drawElementWisps`: mỗi hệ một đốm
màu (`_elemAura`) bay vòng quanh eo — tạp 5 hệ = 5 dải ngũ sắc, đơn hệ = 1 dải thuần.
**Trận pháp hào quang** (068): `_SkyPainter.haloImg` = `assets/cult_halo/{halo_worn}.webp`
(decode trong `_AnimatedCultivator._loadIcons`) → vẽ vòng LỚN gần kín khung, xoay chậm +
thở nhẹ, ở lớp SÂU NHẤT (sau cả nhân vật). Picker `_HaloSheet` (nút góc trái hero khi đã
phi thăng / admin bản dev): user thường thấy trận đã sở hữu, admin thấy trọn bộ + "Nhận
hết". Ảnh nguồn xoá phông bằng luminance+chroma→alpha, lật đối xứng bỏ 'ấn' góc, mặt nạ tròn.

Quy ước màu: KHÔNG hardcode màu cảnh giới — dùng `gradeColor((realm+1)~/2)`;
màu hiệu ứng theo `_auraFor(cpCode)`. Nền thẻ/section theo ColorScheme app.

**Soi hình khi sửa painter** (không cần điện thoại):
```
cd app && flutter test test/scene_render_test.dart
# → build/scene_preview.png — MỞ RA NHÌN trước khi commit
cd app && flutter test test/burst_render_test.dart
# → build/burst_preview.png — filmstrip hiệu ứng đột phá/lên tầng (_BurstPainter)
```
Hiệu ứng đột phá (`_BurstPainter`, dialog `_AdvanceFxDialog`): đại cảnh giới là state machine
4 pha tách biệt: **Tâm Ma (~2,2s) → tụ mây đen (~1,4s) → `tribulation_sequence.webp`
giáng 3 đạo thẳng vào nhân vật (~5,4s) → mới hiện kết quả**. Trong pha mây/lôi chỉ hiện
nhân vật chịu kiếp; chữ và nút thành/bại bị ẩn hoàn toàn. Lên tầng = bản ~1,25s
(linh văn xoay + sóng tu vi + tia + haptic nhẹ).
Preview tĩnh qua widget public `BurstPreview(t, color, ok, loi, major)`.
**Kiếp lôi động**: `tribulation_sequence.webp` chứa cả timeline ba đạo lôi, sinh từ nguồn
blue-white plasma riêng rồi đóng gói WebP động; mỗi dialog nạp một bản byte mới để tránh Flutter
cache trạng thái đã phát xong. `fx_lightning.json` chỉ chạy nhanh sau khi thành công như sét tàn dư,
không dùng làm thân kiếp lôi. Painter không vẽ tia sét, vòng trắng hay vòng cung tím.
**Nấc 2 (chỉ major)**: fragment shader `shaders/breakthrough.frag` (godray+bloom
thủ tục) phủ ADDITIVE lên trên, nạp async qua `FragmentProgram.fromAsset`; null =
fallback về nấc 1 (thiết bị không hỗ trợ vẫn chạy). Shader chỉ soi được trên máy
thật — render test KHÔNG chạy GPU shader. Compile check: `flutter build bundle`.

**Test bậc trên máy thật** (soi hiệu ứng khỏi cày): sheet admin (nút mờ góc hero) có
mục **DEV chỉ hiện ở kDebugMode** → set nhanh cảnh giới/tầng + đầy tu vi qua RPC
`cult_debug_set` (056, admin-only). Reset tay: `select cult_debug_set(1,1,true)` khi
đăng nhập bằng acc admin, hoặc `update user_cultivation set realm=1,stage=1,exp=0`.

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

Đã có (migration 039→058): exp/realm/stage + đột phá · 8 loại vật phẩm ~100 món ·
ngũ hành linh căn · 5 chỉ số · tộc/giới tính + ảnh nhân vật · cơ duyên 50% uniform ·
hero stage + thẻ tilt + đĩa dock bát quái · **Tâm Ma khi đại cảnh giới (054)** ·
**Luyện hóa đồ trùng → tu vi (053)** · **Bộ sưu tập ghi nhận đồ từng sở hữu (057)** ·
**ảnh riêng cho nhóm vật phẩm cấp cao (058)** ·
**Phi Thăng ở đỉnh Độ Kiếp → danh hiệu Tiên Nhân (055)** ·
**Cấp bậc Tiên hậu Phi Thăng: 7 bậc Tiên Nhân→Đạo Tổ + đạo hiệu cõi tiên + hào quang vàng (064)** ·
**Đại tu linh căn: bộ hệ ngũ hành cố định (elements[]) + dị/thiên căn, refine chỉ tăng tốc,
sương ngũ sắc trên nhân vật; buff thật + Tâm Ma theo cấp Tiên (067)** ·
**Trận pháp hào quang hậu Phi Thăng: 6 trận đội thẳng lên nhân vật, rơi khi đọc, admin dev
chọn (068)**.

Roadmap (chưa làm, làm theo thứ tự user chọn):
- Shop / tiền tệ linh thạch (nguồn: quà trùng → tự bán?).
- Tông môn, xếp hạng (cần chống gian lận — lúc đó mới siết claim theo reading_progress).
- Thành tựu.
- Rig tách layer tóc/tay áo cho idle 2.5D sâu hơn (bộ chibi hiện tại dùng 1 layer/nhân vật).
