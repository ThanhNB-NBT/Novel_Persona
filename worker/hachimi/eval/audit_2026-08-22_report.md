# Audit chất lượng dịch v5 — 48 chương mở đầu × 10 thể loại (22/08/2026)

## Đánh giá CHẤT LƯỢNG DỊCH tổng thể

### Số liệu cơ học (48/48 chương)

| Chỉ số | Kết quả | Ghi chú |
|---|---|---|
| LaBSE trung vị | **0.807** | toàn bộ ≥0.718, trên gate 0.70 — không có chương nào sập ngữ nghĩa |
| **Nhân đôi câu khi sinh** | **8/48 chương (17%)** | zh sạch ⇒ lỗi của model lúc decode, không phải crawler |
| Ngày tháng xáo trộn | 3 case/48 chương mở đầu, ≥1 lệch | hiếm nhưng nhìn rất xấu khi gặp |
| Rò chữ Hán vào bản Việt | 0 | sạch |

LaBSE theo nhóm: võng du 0.843 · tiên hiệp 0.833 · kiếm hiệp/vô hạn/ngôn tình ~0.815-0.817 ·
huyền nghi/huyền huyễn ~0.804-0.809 · xuyên không 0.786 · đô thị 0.784 · khoa huyễn 0.783.
(Lưu ý: LaBSE đo khớp ngữ nghĩa, KHÔNG bắt được lỗi jargon — xem dưới.)

### Đọc tay — phát hiện định tính

1. **Lỗi nhân đôi (17%) là hỏng hóc rõ nhất**: câu thoại bị lặp nguyên đoạn giữa chừng
   (vd Mộ Chi: "...được không a, ca ca `ca sẽ hù dọa trẻ con, gia gia lại không có ở đây...`"
   — phần trong ngoặc lặp lại). Trước giờ nghi ngờ chưa xác nhận — **giờ xác nhận rồi**,
   tần suất 1/6 chương. Khắc phục được ở tầng decode (`no_repeat_ngram_size`/
   `repetition_penalty` trong hachimi_engine) hoặc hậu kiểm trùng lặp.
2. **Jargon võng du sai cả ở chương điểm cao nhất**: "2服" → "**mặc áo 2**" (đúng ra là
   "máy chủ 2"), 公测 → "Công trắc" (open beta). LaBSE không thấy vì ngữ nghĩa tổng vẫn khớp.
3. **Sai sắc thái từ**: 怜爱 (dễ thương) → "đáng thương"; 过家家 (chơi nhà búp bê) →
   "chơi game gia đình".
4. **Hoán đổi địa giới hành chính**: 山东临沂市沂南县 → "huyện Nghi Nam, **thành phố Sơn Đông**"
   (tỉnh/thành phố bị đảo).
5. Giọng xưng hô cổ phong (ta/ngươi/gia gia/ca ca) **nhất quán** — điểm mạnh giữ được.

### Bảng tổng hợp theo thể loại

| Nhóm | n | LaBSE median | Nhân đôi | Ghi chú đọc tay |
|---|---|---|---|---|
| võng du | 6 | 0.843 | 2 | jargon game sai (服=máy chủ) dù điểm cao nhất |
| tiên hiệp | 6 | 0.833 | 1 | ổn nhất về giọng |
| kiếm hiệp | 5 | 0.817 | 1 | |
| vô hạn | 5 | 0.817 | 0 | |
| ngôn tình | 3 | 0.815 | 0 | |
| huyền huyễn | 3* | 0.809 | 1 | *bucket lớn nhưng mẫu sâu bị hạn chế R2 |
| huyền nghi | 6 | 0.804 | 2 | có case nhân đôi thoại |
| xuyên không | 5 | 0.786 | 0 | |
| đô thị | 3 | 0.784 | 1 | |
| khoa huyễn | 6 | 0.783 | 1 | có case ngày tháng lệch |

### Thứ tự ưu tiên sửa (cập nhật sau audit)

1. **Chặn nhân đôi câu (17%)** — bật `no_repeat_ngram_size`/`repetition_penalty` lúc decode
   + hậu kiểm trùng chuỗi dài trong finalize_chapter_job; lợi ích phủ mọi thể loại
2. **DictDis bổ sung 班 (ca làm/lớp, 25 lần/48 chương)** + term võng du còn thiếu (服=máy chủ)
3. Booster ngày tháng (hiếm nhưng rẻ) + tên nhất quán
4. Thành ngữ/jargon: oversample từ kaihe

---

## Phụ lục: quét lỗi ngày tháng theo thể loại (regex hai phía)

| Nhóm | Cặp chương | Case ngày | Đúng | Lệch |
|---|---|---|---|---|
| khoa_huyen | 6 | 2 | 1 | 1 |
| vong_du | 6 | 1 | 1 | 0 |
| **TỔNG** | 48 | 3 | 2 | 1 |

- `khoa_huyen` cần `4 tháng 4 năm 2030` ← thấy: (không render đúng)
- Bộ mẫu: `audit_pairs_2026-08-22.jsonl` (local, không vào git theo chính sách jsonl)
