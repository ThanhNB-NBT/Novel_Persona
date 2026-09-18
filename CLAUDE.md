# Novel Persona (Gác Truyện) — chỉ dẫn cho Claude Code

Repo này **chỉ chứa app Flutter** (`app/`) + CI phát hành. Backend (worker crawl/dịch, schema
Supabase, migration, hạ tầng) nằm ở repo riêng `Novel_Backend` (máy này: `D:\code\Novel_Backend`).

## Bất di bất dịch (vi phạm = làm lại)

1. **Không commit khi chưa kiểm chứng.** `cd app && flutter analyze <file đã sửa>` → 0 lỗi, 0 warning,
   0 info mới (CI chạy `--fatal-infos --fatal-warnings`, lọt một info là PR đỏ).
   Sửa painter/sprite/màn hình: chạy render test rồi **mở PNG nhìn bằng mắt** (xem "Kiểm chứng").
   Logic không tầm thường mới → để lại 1 test chạy được trong `app/test/`.
2. **Không tự tag/release/push.** Release = user quyết (xem "Phát hành").
3. **Asset:** ảnh ship là `.webp`. PNG chỉ được phép ở `app/assets/icon/` (nguồn cho
   `flutter_launcher_icons` + logo GT). Đuôi file trong code phải khớp file thật.
4. **Commit message tiếng Việt KHÔNG dấu**, ngắn, nói CÁI GÌ + VÌ SAO. Chat/docs/comment viết
   tiếng Việt **có dấu** (UTF-8). Tên biến/hàm và log tiếng Anh.
5. **Không thêm dependency mới** khi vài dòng hoặc thứ đã có trong `pubspec.yaml` làm được.
6. **Không đổi đường dẫn repo GitHub** (`ThanhNB-NBT/Novel_Persona`) — `app/lib/update.dart` dò
   bản mới qua Releases của chính repo này; đổi là mọi bản đã cài mất kênh cập nhật.

Hook tự kiểm — hook chặn thì đọc lý do, đừng tìm đường vòng:
- Luật #1 (analyze sau mỗi lần sửa `.dart`): hook **global** `~/.claude/hooks/lang-dart.sh`.
- Luật #3, #4 + bí mật trong commit: hook **repo** `.claude/hooks/commit-guard.sh` và global `secret-guard.sh`.

## Trước khi đụng vào

- **Định vị code:** repo có `.codegraph/` → `codegraph_explore` / `codegraph explore "<symbol>"` trước grep.
- **UI** (`app/lib/screens/**`, `app/lib/widgets/**`, `theme.dart`): dùng skill `flutter-novel-ui`.
- **Lỗi layout** (overflow, unbounded): skill `flutter-fix-layout-issues`. **Lỗi runtime**: `dart-fix-runtime-errors`.
- **Hệ Tu Tiên** (`app/lib/cultivation.dart`, `screens/cultivation/`): nhiều hàm **mirror y hệt SQL**
  ở backend (`cult_gift_at`, `cult_advance`, `cult_tien_max`, `cult_halo_codes`…). Đọc
  `D:\code\Novel_Backend\docs\tu-tien.md` trước. Đổi công thức một đầu → **phải** đổi đầu kia
  (migration mới ở repo backend) và báo user, vì lệch là hiển thị sai tỷ lệ cho người chơi.
- **Đổi RPC/bảng Supabase app gọi tới:** schema nằm ở backend — kiểm tên hàm/cột trong
  `Novel_Backend/supabase/migrations/` thay vì đoán.

## Kiến trúc (bám theo cái đang có)

- State **Riverpod 3**, điều hướng **go_router** (routes ở `app/lib/main.dart`), backend **Supabase**.
- `app/lib/data.dart` và `app/lib/widgets.dart` là **barrel** — logic thật nằm trong `data/*.dart`
  (client `sb`, `prefs`, `typedef Rec` ở `data/core.dart`) và `widgets/*.dart`.
- Model = `Map` (`Rec`), **không** codegen/freezed/build_runner/json_serializable. Skill ngoài bảo
  sinh `fromJson`/`toJson` hay tách layer kiến trúc mới → bỏ qua, luật repo thắng.
- Màu lấy từ `ColorScheme` (`app/lib/theme.dart`), không hardcode `Color(0x…)` trong screen.
  Reader là ngoại lệ: dùng `col.bg/col.fg` của `reader_settings.dart`.
- RLS: client chỉ đọc dòng của mình, mọi ghi qua RPC SECURITY DEFINER. Màn cá nhân đọc bảng có
  policy admin-đọc-tất-cả phải lọc thẳng `.eq('user_id', uid)`.
- Đọc offline: `sqflite` (mobile) + `sqflite_common_ffi` (desktop khi dev) — `app/lib/offline.dart`.

## Gotcha

- `.order()` của supabase-dart **mặc định giảm dần** — muốn tăng phải `ascending: true`.
- Sau `await`, kiểm `if (!context.mounted) return;` trước khi dùng `context`.
- Bốn `--dart-define` bắt buộc: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ENDPOINT_CONFIG_URL`,
  `ENDPOINT_ALLOWED_HOSTS`. Dev đọc từ `app/.env` (gitignore — không commit, không in ra log).
- `assets/hanviet.tsv` đồng bộ tay từ `Novel_Backend/worker/novelworker/data/` — đừng sửa tay ở đây.
- Comment trong barrel còn ghi `package:gac_truyen/…` nhưng tên package thật là `novel_reader`.
- Máy này (Windows 11): `flutter` ở `C:\dev\flutter` (trong PATH, 3.47.x — CI ghim 3.47.2),
  `python` 3.12 — **không** dùng `python3` (stub Microsoft Store). Hook `.sh` chạy qua Git Bash.

## Kiểm chứng

- Nhanh trước commit: `/verify` (analyze file đã sửa + test liên quan, không commit).
- Test đúng file: `cd app && flutter test test/<ten>_test.dart` — đừng chạy cả bộ khi chỉ sửa một chỗ.
- Soi UI không cần máy: widget test render PNG, mẫu `app/test/scene_render_test.dart`
  → `app/build/scene_preview.png`, rồi **Read file PNG** để tự nhìn. "Test pass" không thay được bước này.
- Có Dart MCP server (`dart`): `analyze_files`, `run_tests`, `hot_reload`, `get_runtime_errors`,
  `widget_inspector` khi app đang chạy qua `flutter run`.
- Chạy app thật: `cd app && flutter run -d <device> --dart-define-from-file=.env`
  (Wi-Fi debug: `app/ANDROID_WIFI_DEBUG.md`; iOS: `app/IPHONE.md`).

## Phát hành (chỉ khi user bảo)

Tăng `version:` trong `app/pubspec.yaml` → tag `vX.Y.Z` → push tag. CI
(`.github/workflows/android-release.yml`) analyze, build APK (ký bằng keystore trong Secrets) + IPA,
tạo Release và **tự xoá bản cũ, chỉ giữ 2** (`GIU_LAI`). PR/push `main` chạy `pr-check.yml`
(analyze + toàn bộ test).
