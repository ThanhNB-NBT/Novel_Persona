# PLAN — App "NEO" (giao diện tương lai, hoàn toàn mới)

> Đưa file này cho Claude ở session mới: "Đọc PLAN_APP_NEO.md rồi làm Phase 1."

## 0. Đề bài

Tạo **app Flutter thứ 2** trong repo, cùng chức năng với app hiện tại (`app/`)
nhưng **UI hoàn toàn mới, không kế thừa bất kỳ style nào** của "Thanh Tân/Dạ Lam".
Hướng thẩm mỹ: đột phá, sci-fi, hiệu ứng đặc biệt, cảm giác "wow" ngay màn đầu.
Người dùng đã trao toàn quyền thiết kế — không cần hỏi lại về style.

## 1. Vị trí & cách tách

- Tạo project mới: `E:\Novel_Project\app_neo\` (`flutter create app_neo --org com.thanhnb.novel --project-name novel_neo`).
- `applicationId` khác app cũ → cài song song trên cùng máy Android.
- **KHÔNG copy code UI** từ `app/lib/screens` hay `app/lib/widgets.dart`, `app/lib/theme.dart`.
- **ĐƯỢC copy nguyên** các file không-UI (đây là "chức năng"):
  - `app/lib/data.dart` — models + Supabase queries + providers (Riverpod)
  - `app/lib/offline.dart` — sqflite đọc offline
  - `app/lib/notify.dart` — local notifications
  - `app/lib/errorlog.dart` — log lỗi
  - Cấu hình Supabase URL/anon key lấy trong `app/lib/main.dart`.
- Dependencies giữ nguyên bộ: supabase_flutter, flutter_riverpod, go_router,
  shared_preferences, flutter_local_notifications, sqflite (+ffi), path, google_fonts.
- KHÔNG dựng flavor trong app cũ — 2 project tách hẳn cho sạch.

## 2. Chức năng phải giữ đủ (map từ app cũ)

| App cũ (`app/lib/screens/`) | Chức năng | NEO phải có |
|---|---|---|
| `shell.dart` | khung 4 tab điều hướng | có, nhưng navigation kiểu mới (xem §3) |
| `explore/home.dart`, `section.dart` | trang khám phá, section truyện | ✅ |
| `explore/search.dart`, `filter.dart` | tìm kiếm + lọc | ✅ |
| `novel/novel_detail.dart` | chi tiết truyện, danh sách chương, theo dõi | ✅ |
| `novel/glossary.dart` | glossary Hán-Việt | ✅ |
| `reader/reader.dart` | đọc chương, sửa dịch (glossary suggest + auto-patch), tiến độ dịch realtime | ✅ — màn quan trọng nhất |
| `reader/reader_settings.dart` | font/cỡ chữ/nền đọc | ✅ |
| `library/library.dart` | tủ truyện đang theo dõi | ✅ |
| `library/offline_library.dart` | truyện tải offline | ✅ |
| `library/queue.dart` | hàng đợi job dịch/crawl + trạng thái worker | ✅ |
| `account/login.dart`, `edit_profile.dart`, `settings.dart` | auth Supabase, hồ sơ, cài đặt | ✅ |
| `admin/admin.dart`, `errors.dart` | admin panel (chỉ hiện khi `is_admin`) | ✅ |

Bẫy đã biết: supabase-dart `.order()` mặc định **DESCENDING** — xem app cũ khi port query.

## 3. Concept thiết kế — "NEO TERMINAL" (đã chốt, cứ thế làm)

Tông: **dark-first sci-fi HUD** — như đọc truyện trên kính holographic của phi thuyền.

- **Nền**: đen sâu `#05070D`, texture noise/grain nhẹ + grid mờ kiểu blueprint.
- **Accent**: cyan điện `#00E5FF` + tím plasma `#7C4DFF`, dùng dạng **glow** (neon), gradient chỉ ở viền/hairline, không đổ khối.
- **Chữ**: display = font mono-tech (Space Grotesk / JetBrains Mono qua google_fonts); body đọc truyện vẫn phải là serif/sans dễ đọc lâu (Noto Serif) — sci-fi ở khung, không hành hạ mắt người đọc.
- **Hình khối**: góc vát (clipped corners / hexagon), hairline border phát sáng, KHÔNG bo tròn mềm (đó là app cũ).
- **Hiệu ứng bắt buộc** (dùng `dart:ui` FragmentShader + Animation, không thêm package nặng):
  1. Boot sequence khi mở app: scanline quét + logo glitch ~1s.
  2. Chuyển trang kiểu "materialize": fade + scanline thay vì slide mặc định.
  3. Card truyện: viền glow chạy quanh khi nhấn giữ; parallax nhẹ theo scroll.
  4. Reader: khi chương đang dịch realtime, chữ hiện dần kiểu "decrypt" (ký tự nhiễu → rõ dần).
  5. Progress/loading: thanh HUD dạng segment + số % kiểu terminal, không dùng CircularProgressIndicator mặc định.
- **Navigation**: bỏ BottomNavigationBar thường — thanh dock HUD nổi, icon phát sáng khi active, haptic khi chuyển tab.
- **Chế độ sáng**: có nhưng làm sau cùng (Phase 5) — bản "hologram trắng" cùng ngôn ngữ thiết kế.
- Hiệu ứng phải tôn trọng `MediaQuery.disableAnimations` và có đường tắt tắt bớt trên máy yếu.

## 4. Phases (mỗi phase build chạy được)

1. **Skeleton**: tạo project, copy data/offline/notify/errorlog, cấu hình Supabase, theme NEO (màu/chữ/shape tokens trong `lib/neo_theme.dart`), shell + dock HUD + boot sequence, đăng nhập. → chạy được, login được.
2. **Explore + Novel detail + Search/filter**: duyệt và xem truyện.
3. **Reader**: đọc chương + settings + hiệu ứng decrypt + sửa dịch (port logic từ app cũ, UI mới) + realtime progress.
4. **Library + Queue + Offline**: tủ truyện, hàng đợi, tải offline.
5. **Account + Admin + light mode + polish hiệu ứng** (shader tinh chỉnh, haptics, empty states).

## 5. Nguyên tắc khi code

- Skill `flutter-novel-ui` là của app CŨ — **không áp dụng** cho app_neo (trừ phần convention Riverpod/go_router/Supabase thì vẫn theo).
- Logic nghiệp vụ: đọc file gốc trong `app/lib/` làm chuẩn, chỉ viết lại phần widget.
- Ưu tiên ít file: `neo_theme.dart`, `neo_widgets.dart` (dock, card, HUD progress, scanline), rồi mỗi màn 1 file như app cũ.
- Shader: tối đa 2 file `.frag` (scanline/glow) trong `shaders/`, khai báo trong pubspec.
- Commit sau mỗi phase.
