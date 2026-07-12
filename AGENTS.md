# Quy tắc cho AI coding agent (Claude, ChatGPT/Codex) — repo Gác Truyện

Đọc file này TRƯỚC khi sửa bất cứ gì. Vi phạm mục "Bất di bất dịch" = làm lại.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues for this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Use the single-context domain-doc layout. See `docs/agents/domain.md`.

## Bất di bất dịch

1. **KHÔNG commit khi chưa kiểm chứng.** Tối thiểu:
   - Dart: `cd app && flutter analyze <các file đã sửa>` → 0 lỗi, 0 warning mới.
   - Sửa painter/sprite/màn hình: chạy render test rồi MỞ PNG NHÌN BẰNG MẮT
     (`flutter test test/scene_render_test.dart` → `app/build/scene_preview.png`).
   - Python worker: `python -m py_compile <file>` + chạy thử hàm đổi nếu chạm mạng/LLM.
   - Logic không tầm thường mới → để lại 1 test/self-check chạy được.
2. **KHÔNG tự tag/release/push DB** trừ khi user bảo. Migration mới chỉ tạo file
   `supabase/migrations/0xx_*.sql` (số tiếp theo, idempotent khi có thể) — việc
   `supabase db push --linked` hỏi user trước.
3. **KHÔNG sửa migration đã push.** Muốn đổi → migration mới đè (create or replace).
4. **Asset ảnh:** chỉ `.webp` được khai trong pubspec và ship; PNG gốc KHÔNG commit.
   Code trỏ asset phải khớp đuôi file (đã dính bug .png/.webp một lần).
5. Commit message tiếng Việt không dấu, ngắn, nói CÁI GÌ + VÌ SAO.

## Trước khi làm việc với hệ Tu Tiên

Đọc `docs/tu-tien.md` — thiết kế + công thức + các cặp mirror SQL↔Dart
(sửa một đầu là PHẢI sửa đầu kia). Đổi thiết kế → cập nhật doc cùng commit.

## Bản đồ repo (đọc thêm khi cần)

- `app/` Flutter (Riverpod + go_router + Supabase). UI theo `app/lib/theme.dart`
  + widget chung `app/lib/widgets.dart`; đừng hardcode màu, lấy từ ColorScheme.
  Model = `Map` (`Rec`), KHÔNG thêm codegen/freezed.
- `worker/` Python crawler+translator, chạy Docker trên VPS (deploy từ `main`).
  Sửa worker → nhắc user rebuild VPS (git pull + compose build).
- `supabase/migrations/` schema + RPC. RLS: client chỉ đọc dòng của mình,
  mọi ghi qua RPC SECURITY DEFINER.
- `docs/` thiết kế: `ke-hoach.md` (tổng), `crawl-multisource.md` (nguồn),
  `tu-tien.md` (game Tu Tiên), `todo-handoff.md` (việc treo).

## Build & thử

- Chạy app thật: `cd app && flutter run -d <android> --dart-define-from-file=.env`
  (bản debug là app RIÊNG `.dev`, cài song song bản release — cứ thoải mái).
- Release = user quyết: tăng `version:` pubspec → tag `vX.Y.Z` → push → CI tự
  build APK+IPA lên GitHub Releases. KHÔNG làm hộ khi chưa được bảo.
- Soi UI không cần máy: viết widget test render PNG (mẫu: `app/test/scene_render_test.dart`).
