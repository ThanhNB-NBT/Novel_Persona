---
description: Kiểm chứng mọi thứ đang sửa theo CLAUDE.md luật #1 (flutter analyze + test liên quan + nhìn PNG)
allowed-tools: Bash, Read, Glob
---

Kiểm chứng các file đang sửa dở trong cây làm việc. **Không commit** — chỉ báo cáo.

File đang sửa (đã tracked + chưa tracked):
!`git -C "$CLAUDE_PROJECT_DIR" status --porcelain`

Làm đúng thứ tự, bỏ qua bước nào không có file tương ứng:

1. **Analyze** — mọi file `.dart` đã sửa dưới `app/`:
   `cd app && flutter analyze --fatal-infos --fatal-warnings <các file>` (y như CI).
   Yêu cầu: 0 lỗi, 0 warning, 0 info.

2. **Test liên quan** — file đã sửa có test tương ứng trong `app/test/` (tìm theo tên, hoặc
   `codegraph explore "<symbol>"` để thấy test nào chạm tới) → chạy đúng những test đó:
   `cd app && flutter test test/<ten>_test.dart`. Đổi `pubspec.yaml`/`main.dart`/`data/core.dart`
   thì chạy cả bộ `flutter test`.

3. **Nhìn bằng mắt** — có sửa painter/sprite/màn hình: chạy render test tương ứng
   (`*_render_test.dart`) rồi **Read file PNG** sinh ra trong `app/build/`. Không được bỏ bước này
   bằng lý do "test pass".

4. **Asset** — có ảnh mới dưới `app/assets/`: ship bằng `.webp` (PNG chỉ ở `assets/icon/`), đuôi
   trong code và `pubspec.yaml` khớp file thật.

5. **Mirror Tu Tiên** — có đổi `app/lib/cultivation.dart`: nhắc user hàm SQL tương ứng ở
   `Novel_Backend` cần migration mới đi kèm.

Cuối cùng báo gọn: mỗi bước PASS/FAIL/BỎ QUA + lý do. Có FAIL thì nói rõ file và lỗi, đừng tự sửa
trừ khi user bảo.
