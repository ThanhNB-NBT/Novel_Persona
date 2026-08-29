# Gác Truyện — chỉ dẫn cho Claude Code

Luật đầy đủ nằm ở [AGENTS.md](AGENTS.md) (dùng chung với Codex). **Đọc nó trước khi sửa bất cứ gì.**
Dưới đây là bản rút gọn để không phải mở file mới nhớ ra.

## Bất di bất dịch (vi phạm = làm lại)

1. **Không commit khi chưa kiểm chứng.** Dart: `dart analyze` file đã sửa → 0 lỗi/warning mới.
   Python worker: `python3 -m py_compile` + chạy thử hàm nếu chạm mạng/LLM.
   Sửa painter/sprite/màn hình: chạy render test rồi **mở PNG nhìn bằng mắt**.
2. **Không tự tag/release/push DB.** Migration mới = file `supabase/migrations/0xx_*.sql`;
   `supabase db push --linked` phải hỏi user.
3. **Không sửa migration đã push** — viết migration mới đè lên (`create or replace`).
4. **Asset:** chỉ `.webp` được khai trong pubspec và ship. PNG gốc không commit.
5. **Commit message tiếng Việt KHÔNG dấu**, ngắn, nói CÁI GÌ + VÌ SAO.
   Chat/docs/comment thì viết tiếng Việt **có dấu**. Tên biến/hàm và log tiếng Anh.
6. **Không thêm dependency mới** khi vài dòng hoặc thứ đã cài làm được.

Hook tự kiểm các luật này — hook chặn thì đọc lý do, đừng tìm cách đi vòng:
- Luật #1 (compile/analyze) do hook **global** `~/.claude/hooks/lang-*.sh` lo, áp cho mọi project.
- Luật #3, #4, #5 do hook **repo** `.claude/hooks/{migration,commit}-guard.sh` lo.

## Trước khi đụng vào

- **UI Flutter** (`app/lib/screens`, `app/lib/widgets`): dùng skill `flutter-novel-ui`.
- **Hệ Tu Tiên**: đọc `docs/tu-tien.md` — có các cặp mirror SQL↔Dart, sửa một đầu phải sửa đầu kia.
- **Crawler đa nguồn**: `docs/crawl-multisource.md`.
- **Chất lượng dịch Hachimi**: `worker/hachimi/eval/` — xem `hachimi_eval_locked.md` trước khi đo lại.

## Gotcha

- `app/`: model = `Map` (`Rec`), **không** thêm codegen/freezed. Màu lấy từ `app/lib/theme.dart`, đừng hardcode.
- `worker/` chạy Docker trên box nhà, deploy bằng **rsync** chứ không phải `git pull`.
- RLS: client chỉ đọc dòng của mình, mọi ghi qua RPC SECURITY DEFINER.
- Toolchain máy này: `~/flutter/bin/flutter`, `python3` hệ thống (không có `.venv` trong repo).

## Kiểm chứng nhanh

Chạy `/verify` để kiểm cả Dart lẫn Python theo đúng luật #1 trước khi commit.
