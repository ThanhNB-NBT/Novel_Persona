# Kết luận Hachimi v-next E và hướng F

## Quyết định

**Không dùng E. Không thay model production.**

E đã được fine-tune trực tiếp từ `ngocdang83/HachimiMT-60-zh-vi`, không phải
resume từ `worker/models/hachimi-ct2`. Vì vậy việc quay lại Hachimi gốc nhưng giữ
mix E sẽ không giải quyết được lỗi.

## Số liệu

### 60 cảnh khóa

| Model | Similarity | Đại từ hiện đại | Quote lỗi | Số lỗi |
|---|---:|---:|---:|---:|
| Current | 0,7107 | 15 | 6 | 0 |
| D | **0,7160** | 15 | **5** | 0 |
| E | 0,7148 | 15 | 6 | 0 |

E không vượt D và trượt cổng quote.

### 60 đoạn ngoài tập khóa, 15 thể loại

| Model | Đại từ hiện đại | Quote lỗi | Số lỗi | Hán sót |
|---|---:|---:|---:|---:|
| Hachimi gốc | 119 | **8** | **6** | 0 |
| Current | **84** | **8** | 8 | 0 |
| D | 108 | 12 | 7 | 0 |
| E | 114 | 11 | 7 | 0 |

Hachimi gốc không tốt hơn current về xưng hô. D/E đều hồi quy so với current;
historical replay của hai vòng này không phải nền dữ liệu phù hợp.

### Sáu chương liên tục

| Model | Đại từ hiện đại | Quote lệch | Số lỗi | Hán sót |
|---|---:|---:|---:|---:|
| Current | **38** | 4 | 3 | 0 |
| D | 50 | 4 | 3 | 0 |
| E | 50 | 4 | 3 | 0 |

E trượt cổng đại từ `≤39`. Đọc tay vẫn thấy các lỗi `Mã Lợi Á/Malia`, sai chủ thể
`mình/hắn/nàng`, `Yah`, biến dạng số, thuật ngữ game trôi và câu dài hiểu sai.

## Candidate F

F vẫn bắt đầu từ Hachimi gốc, nhưng bỏ toàn bộ historical replay D/E:

- 240 gold đã duyệt, lặp 3 lần;
- tối đa 20.000 replay từ chính `ngocdang83/tran-vi-teacher`;
- replay phải có nguồn Trung hợp lệ, không mojibake, quote cân, số khớp, không Hán
  trong đích, tỷ lệ dài hợp lý và không có register hiện đại kể cả trong thoại;
- không dùng `train_v2`, `register_gold`, booster, moa, kaihe, VnAPE hoặc VietPhrase.

Các nguồn tìm được chiều nay không bị bỏ quên: chúng bị loại khỏi F vì đã kiểm chứng
không phải cặp ZH→VI sạch, lệch hàng/thêm bớt ý, hoặc không có giấy phép/provenance
đủ để trộn tự động.

Gói train: `hachimi-vnext-f-kaggle.zip`.

SHA-256:
`38FB3DD67F0503340FC5AE48042B618A34A6262560EA657F417F3E278DDB18AD`.

F chỉ là thí nghiệm kế tiếp. Sau train phải chạy lại đúng ba tầng trên và đọc tay
truyện 32 trước khi cân nhắc thay model.
