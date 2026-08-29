---
description: Viết spec ngắn gọn cho một feature từ mô tả tự nhiên
---

Viết spec cho feature: $ARGUMENTS

Tạo file `docs/specs/<ten-feature>.md` với cấu trúc sau, viết bằng tiếng Việt, ngắn gọn — chỉ điền phần thực sự có nội dung:

```markdown
# Spec: [Tên feature]
**Ngày**: [hôm nay] | **Trạng thái**: Draft

## User Stories (theo độ ưu tiên)
### P1 - [tiêu đề]
[mô tả journey ngắn]
- **Given** ... **When** ... **Then** ...
(P2, P3 nếu có — mỗi story phải test độc lập được)

## Yêu cầu chức năng
- FR-1: Hệ thống PHẢI ...
(đánh dấu [CẦN LÀM RÕ: câu hỏi] nếu mơ hồ thay vì tự đoán)

## Ngoài phạm vi
- ...

## Tiêu chí thành công
- Đo được, không nói công nghệ (vd: "user dịch xong 1 chương < 30s")
```

Quy tắc: KHÔNG nói về tech stack/implementation trong spec. Nếu có quá 3 điểm [CẦN LÀM RÕ], hỏi user trước khi viết tiếp.
