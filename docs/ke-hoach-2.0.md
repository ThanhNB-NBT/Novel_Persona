# Kế hoạch Gác Truyện 2.0

Chốt với user 24/09/2026: làm hết các giai đoạn dưới. Tu Tiên: **làm thật** Động Phủ / Bí Cảnh /
Thành Tựu (qua RPC server) và **mở rộng cấp bậc Tiên cao hơn** Hư Vô Đại Đạo Tổ.
Các câu user chưa trả lời riêng → theo đề xuất: sửa bản dịch = **nhấn giữ**; gộp "theo dõi" +
"đang đọc" thành một Tủ truyện; Tu Tiên **giữ ô giữa** thanh tab.

Nguồn phát hiện: rà app thật trên AVD `gac_truyen` (bản 1.0.31) + đọc code.

## Tiến độ

- [x] GĐ0 Dọn nền
- [x] GĐ1 Trình đọc
- [x] GĐ2 Gộp Tủ truyện
- [x] GĐ3 Tu Tiên thật + mở rộng cấp bậc (backend + app)
- [x] GĐ4 Điều hướng + lần đầu dùng
- [x] GĐ5 Dọn chữ & dữ liệu hiển thị
- [x] GĐ6 Phát hành 2.0.0+33 — đã bump version + màn Có gì mới; CHƯA tag/push (user quyết)

## GĐ0 — Dọn nền (không đổi hành vi)

- Tách `_editForm` (reader.dart ~919–1362) ra `screens/reader/reader_edit_form.dart`;
  tách pager (`_buildPager`, `_pagerEdge`) ra `reader_pager.dart`. reader.dart 1509 dòng, hotspot #2.
- Hàm định dạng số dùng chung (lỗi `3800.2/giây` vs `669,8M` ở Tu Tiên) — tìm hàm format có sẵn trước.
- Kiểm: `flutter test test/reader_text_test.dart test/search_and_reader_tap_test.dart`.

## GĐ1 — Trình đọc

- Chạm nội dung = bật/tắt thanh công cụ (cả chế độ cuộn). Hiện `_onTapWord` (reader.dart:186) mở
  form sửa + bàn phím cho MỌI user đăng nhập.
- Nhấn giữ vào từ = mở form sửa (giữ nguyên logic chọn cụm tên riêng `nameRunBounds`).
- Nút **mục lục** trên thanh trên → bottom sheet danh sách chương (`chapterListProvider`), cuộn sẵn
  tới chương đang đọc.
- Trang truyện, tab "Danh sách chương": tự cuộn tới chương đang đọc (đang mở ở chương 1).

## GĐ2 — Gộp Tủ truyện

Hiện trạng: tab Tủ truyện = `readingProvider` (bảng `reading_progress`); nút "+" ở trang truyện và
màn Yêu cầu truyện ghi bảng `library` mà **không màn nào hiển thị** (`libraryProvider` không ai watch).
Backend có vẻ dùng `library` cho lazy TOC (migration 033/035) — đọc lại trước khi đổi.

- Tủ truyện = hợp của `library` ∪ truyện có `reading_progress`. Truyện theo dõi chưa đọc hiện "Chưa đọc".
- Nút "+" → "Theo dõi" / "Đang theo dõi" (có chữ, không chỉ icon). Đọc truyện lần đầu = tự theo dõi?
  → quyết khi làm: đơn giản nhất là giữ hai nguồn, Tủ = hợp hai nguồn.
- Xoá khỏi tủ = xoá cả hai (library + reading_progress) — `removeReading` ở data/library.dart.
- Dòng truyện kèm tiến độ dịch ("đang dịch 12/40") lấy từ dữ liệu màn Hàng đợi.
- Huy hiệu chuông: đếm số DÒNG thông báo (theo truyện), không đếm chương (hiện 99+ mà mở ra 1 dòng).

## GĐ3 — Tu Tiên thật + mở rộng cấp bậc

Hiện trạng (sheets_tu_tien.dart): `_harvestQi` (Động Phủ), `_explore` (Bí Cảnh) chỉ hiện SnackBar
"+X tu vi" rồi invalidate — **không RPC**. Thành Tựu lưu `prefs` cục bộ, 6 mục, không thưởng gì.
Đọc `Novel_Backend/docs/tu-tien.md` trước; migration tiếp theo là **124**.
DB tự host trên box: áp migration bằng psql trong container `supabase-db` (không `db push`) —
**hỏi user trước khi áp lên DB thật**; thử trước trong `BEGIN … ROLLBACK`.

Migration 124 (một file, idempotent):
- Cột `user_cultivation.last_harvest_at timestamptz`, `explore_at jsonb default '{}'`.
- `cult_harvest()`: gọi `cult_tick` trước; hồi 4h; thưởng = `cult_base_rate() × 1800` (30 phút tu),
  kẹp trần bình cảnh như tick. Trả `{gain, next_at}`.
- `cult_explore(code text)`: bảng bí cảnh cố định trong hàm (u_minh r1 / van_kiem r3 / thai_hu r5 /
  chu_thien r9=Độ Kiếp — sửa lệch hiện tại minRealm 8 mà nhãn ghi "Cần Độ Kiếp"); hồi 1 lần/ngày/bí cảnh;
  thưởng tu vi theo base_rate × hệ số bí cảnh + 25% rơi 1 vật phẩm ngẫu nhiên (dùng lại cách rơi của
  `cult_claim_gift`). Server tự kiểm realm, không tin client.
- Bảng `user_cult_achievements(user_id, code, claimed_at)` PK (user_id, code), RLS đọc dòng mình.
  `cult_achievements()` trả danh sách + đạt/chưa (tính server từ realm, ascended_at, tien_tier,
  count cult_claims, count user_cult_collection); `cult_claim_achievement(code)` kiểm đạt → thưởng
  1 lần. Mốc: cảnh giới (Trúc Cơ…Độ Kiếp, Phi Thăng), bậc Tiên (kể cả bậc mới), số chương nhận quà
  (100/1000/5000), bộ sưu tập (25/50/100 món).
- **Mở rộng cấp bậc Tiên** 10 → 15 bậc (tien_tier 10..14), cung "Siêu Thoát":
  10 Siêu Thoát Giả · 11 Vĩnh Hằng Chúa Tể · 12 Nguyên Sơ Thủy Tổ · 13 Vô Lượng Đạo Chủ ·
  14 Vô Thượng Chí Tôn (tên đề xuất — user duyệt). Đổi `cult_tien_max()` → 14; `cult_tien_req`
  giữ công thức 1.6^(tier+1) (tự kéo dài). Kiểm mọi chỗ index theo tien_tier (painter, halo,
  buff 1+0.2×tier) không tràn mảng.

App (mirror): `tienTierNames`/`tienDaoTitles` thêm 5 bậc; sheets gọi RPC thật, hiện đếm ngược hồi;
Thành Tựu đọc từ server (bỏ prefs `achieve_claimed_*`). Test mirror: cập nhật `cult_mirror_test` /
`scene_render_test` cho tier 14. Cập nhật `docs/tu-tien.md` (bảng mirror + roadmap) cùng commit backend.
Kèm: túi đồ đè thanh trạng thái (thêm nền vùng status bar); sắp xếp theo độ hiếm + luyện hóa hàng loạt
(`cult_recycle` từng món lặp — cân nhắc RPC `cult_recycle_all(grade_max)`).

## GĐ4 — Điều hướng & lần đầu dùng

- Tab: Tủ truyện · Khám phá · Tu Tiên (giữa) · **Tôi**. Bỏ Hàng đợi (màn giữ route, vào từ Quản trị).
  → **Đã làm khác (24/09):** 4 tab thì không có ô giữa, mà dock vẽ cho 5 ô với Tu Tiên ở ô 2.
  Chốt 5 ô: Tủ truyện · Khám phá · Tu Tiên · **Thông báo** (chuông từ header Tủ truyện xuống, có
  huy hiệu) · **Tôi**. Hàng đợi còn route `/queue`, vào từ Tôi → Thư viện (cho mọi user, không chỉ admin).
  "Tôi" = Cài đặt hiện tại (hồ sơ, chuỗi ngày, giao diện, offline, quản trị) + yêu cầu truyện.
- Quyền thông báo: bỏ xin lúc khởi động; xin khi theo dõi truyện đầu tiên, kèm câu giải thích.
- Chưa đăng nhập: tab khoá hiện trạng thái trống có giải thích + nút Đăng nhập (không nhảy thẳng).
- Đăng nhập xong → mở Tủ truyện (shell.dart `_i` chỉ set lúc initState).

## GĐ5 — Dọn chữ & dữ liệu hiển thị

- Ẩn "Mã truyện #…" và mã nguồn thô (`xslou`, `ptwxz`…) với user thường; nguồn → tên hiển thị
  (cột mới ở `sources` hoặc map phía app — chọn cái ít đụng nhất).
- Thể loại: chuẩn hoá hoa/thường, gộp trùng, dịch mục còn tiếng Trung (`科幻小说`) — migration backend.
  → **Đã làm (24/09):** không cần migration — chạy `worker/backfill_genres.py` có sẵn trên DB thật
  (8.707 truyện, 211 → 138 nhãn, 0 nhãn chữ Trung; sao lưu bảng `_bak_genres_20260924`). Gốc rễ còn
  lại: crawler ghi `genres_zh` thô, chỉ map khi dịch metadata → tách task riêng.
  Nguồn: map phía app `sourceLabel()` (data/novels.dart), mã truyện chỉ admin thấy.
- Khám phá: giữ băng chuyền, bỏ thẻ lớn trùng trong "Mới cập nhật", một kiểu nút "Đọc ngay".

## GĐ6 — Phát hành

- Màn "Có gì mới ở 2.0" hiện 1 lần (dùng cơ chế hỏi-1-lần-mỗi-version của update.dart).
- `version: 2.0.0+33`. User tự tag.

## Kiểm chứng mỗi giai đoạn

`flutter analyze` file sửa (0 info) → test liên quan → màn đổi: render test hoặc chạy AVD + screencap
nhìn bằng mắt. Không commit khi chưa qua. Commit tiếng Việt không dấu.

## GĐ7 — Nâng giao diện (user yêu cầu 24/09, CHƯA chốt hướng)

User nhận xét GĐ0–6 chỉ tăng trải nghiệm, không nâng diện mạo. Chưa tag 2.0 → gộp vào 2.0.
Cách làm: dựng bản mẫu (render PNG / trang xem trước) 2–3 màn cho user chọn hướng TRƯỚC khi code.
Ứng viên (từ ảnh rà app):
1. Tủ truyện: thẻ lớn "Đọc tiếp" (bìa mờ làm nền) cho truyện gần nhất; còn lại chọn lưới/danh sách.
2. Trang truyện: header cao tràn viền, màu chủ đạo lấy từ bìa; chỉ số gom thành hàng chip.
3. Trình đọc: thanh trên/dưới đẹp hơn, thanh tiến độ chương kéo được, theme đọc mới (giấy cũ, mực đêm), chuyển chương có hiệu ứng.
4. Khám phá: thống nhất nhịp (bo góc, khoảng cách, cỡ tiêu đề mục).
5. Tu Tiên: thẻ Động Phủ/Bí Cảnh/Thành Tựu theo chất liệu giấy-lụa-triện hợp nền thủy mặc.
6. Toàn app: soi dark mode, minh hoạ trạng thái trống, hiệu ứng chuyển màn đồng bộ.
**Chốt 24/09: làm CẢ 6, kết hợp phong cách** theo luật chia vai:
- KHUNG (dock, header, danh sách, nút, chip) = hiện đại tối giản: khoảng thở rộng, bo góc thống nhất
  (token chung trong theme.dart), một màu nhấn, sans. Không rải hoạ tiết cổ lên khung.
- NỘI DUNG/CẢM XÚC = cổ phong có chủ đích:
  - Tu Tiên cổ phong đậm: thẻ giấy lụa, triện đỏ, viền vân mây (hợp nền thủy mặc có sẵn).
  - Trình đọc: theme "Giấy cũ" (chữ có chân) + "Mực đêm".
  - Chữ ký thương hiệu: dấu triện nhỏ cạnh tiêu đề mục (SectionHeader/PageHeader) — dùng NHẤT QUÁN.
  - Trang truyện: màu chủ đạo trích từ bìa (hiện đại, mỗi truyện một sắc).
Thứ tự: (a) token thiết kế + triện dùng chung → (b) dựng mẫu PNG 3 màn (Tủ truyện, Trang truyện,
thẻ Tu Tiên) cho user duyệt → (c) áp 6 màn → (d) soi dark mode + text scale 200% → commit từng màn.
Ràng buộc: không thêm dependency (trích màu bìa tự viết, không dùng palette_generator nếu chưa có
trong pubspec — kiểm trước); ảnh/hoạ tiết mới phải .webp; render test mỗi màn đổi.
