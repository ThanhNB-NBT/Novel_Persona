---
description: Chia spec/plan thành danh sách task triển khai theo thứ tự
---

Chia nhỏ thành tasks cho: $ARGUMENTS (đọc spec/plan tương ứng trong `docs/specs/` nếu có)

Ghi tiếp vào cuối file spec (hoặc trả lời trực tiếp):

```markdown
## Tasks
### Nền tảng (chặn các phần sau)
- [ ] T1: [việc cụ thể + file đích]

### P1 - [tên user story]
- [ ] T2: ...
- [ ] T3: Kiểm chứng: [cách verify P1 chạy được]

### P2 - ...
```

Quy tắc: mỗi task đủ cụ thể để làm không cần hỏi lại (có tên file). Nhóm theo user story để làm xong P1 là có MVP chạy được. Mỗi story kết thúc bằng 1 task kiểm chứng. Không tạo task "viết docs/refactor cho đẹp" trừ khi spec yêu cầu.
