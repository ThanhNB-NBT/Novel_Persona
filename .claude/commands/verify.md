---
description: Kiểm chứng mọi thứ đã sửa theo AGENTS.md luật #1 (Dart analyze + Python compile + test liên quan)
allowed-tools: Bash, Read, Glob
---

Kiểm chứng các file đang sửa dở trong cây làm việc. **Không commit** — chỉ báo cáo.

File đang sửa (đã tracked + chưa tracked):
!`git -C "$CLAUDE_PROJECT_DIR" status --porcelain`

Làm theo đúng thứ tự sau, bỏ qua bước nào không có file tương ứng:

1. **Dart** — với mọi file `.dart` đã sửa dưới `app/`:
   `cd app && ~/flutter/bin/cache/dart-sdk/bin/dart analyze --fatal-infos <các file>`
   Yêu cầu: 0 lỗi, 0 warning mới.

2. **Python** — với mọi file `.py` đã sửa:
   `python3 -m py_compile <các file>`

3. **Test liên quan** — nếu file đã sửa có test tương ứng trong `app/test/` hoặc `worker/test/`,
   chạy đúng những test đó (`cd app && ~/flutter/bin/flutter test test/<ten>_test.dart`).
   Đừng chạy cả bộ test nếu chỉ sửa một chỗ.

4. **Nhìn bằng mắt** — nếu có sửa painter/sprite/màn hình, chạy render test rồi Read file PNG
   sinh ra trong `app/build/` để tự nhìn. Không được bỏ bước này bằng lý do "test pass".

5. Nếu có migration mới trong `supabase/migrations/`: đọc lại, xác nhận idempotent, và
   **nhắc user** tự chạy `supabase db push --linked` — không tự chạy.

Cuối cùng báo cáo gọn: mỗi bước PASS/FAIL/BỎ QUA + lý do. Có FAIL thì nói rõ file và lỗi,
đừng tự ý sửa trừ khi user bảo.
