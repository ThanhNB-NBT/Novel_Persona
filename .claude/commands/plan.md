---
description: Lập plan kỹ thuật từ một spec đã có
---

Lập plan kỹ thuật cho: $ARGUMENTS (nếu là tên feature, đọc spec tương ứng trong `docs/specs/`)

Đọc spec + code hiện có liên quan trước. Rồi ghi tiếp vào cuối file spec đó (hoặc trả lời trực tiếp nếu nhỏ):

```markdown
## Plan kỹ thuật
**Ảnh hưởng**: [file/module nào sẽ sửa hoặc thêm — liệt kê đường dẫn cụ thể]

### Quyết định thiết kế
- [Quyết định]: [lý do 1 dòng, phương án bị loại nếu đáng nói]

### Data model / API (nếu có)
- Bảng/cột mới, migration, endpoint...

### Rủi ro
- [rủi ro] → [cách né]
```

Quy tắc: tận dụng tối đa code/pattern sẵn có trong repo, không đề xuất dependency mới nếu vài dòng code là xong. Plan phải ngắn hơn spec.
