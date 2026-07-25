# Vì sao tham chiếu đọc mượt mà model đọc vấp — đo trên 60 cảnh khóa (25/07)

## 1. Model không mất nội dung, nó mất NHỊP CÂU

Cùng 60 cảnh, so bản dịch với tham chiếu (`experiments/hachimi_teacher_v2_eval.jsonl`):

| | câu/cảnh | dấu phẩy mỗi câu | câu dài nhất (ký tự) | cảnh có câu >200 ký tự | ký tự/cảnh |
|---|---:|---:|---:|---:|---:|
| tham chiếu | **4,3** | **0,93** | **140** | **5/60** | 371 |
| base | 2,7 | 2,96 | 231 | 32/60 | 387 |
| current | 2,7 | 3,08 | 227 | 31/60 | 386 |
| teacher_v2 | 2,9 | 2,71 | 217 | 28/60 | 386 |

Độ dài tổng gần như bằng nhau (386 vs 371) ⇒ **không phải mất ý**. Model gói cùng lượng
chữ vào **một nửa số câu với gấp ba dấu phẩy**: nửa số cảnh có một câu dài trên 200 ký tự.
Đó chính là cảm giác "đọc thấy lỗi" dù không chỉ ra được lỗi từ vựng.

## 2. Nguồn gốc: dữ liệu train dạy dịch 1:1 theo dấu câu tiếng Trung

Chỉ số quyết định = **số câu tiếng Việt trên mỗi dấu 。 của nguồn**:

| Tập | dòng | ký tự/dòng | câu VI / dấu 。 ZH |
|---|---:|---:|---:|
| tham chiếu 60 (Codex soát) | 60 | 371 | **2,06** |
| raw_vi 60 (production cũ) | 60 | 387 | 1,06 |
| core_gold 240 (đã duyệt) | 240 | 262 | 1,64 |
| **teacher replay 10.000** | 10.000 | 107 | **1,01** |
| game replay 67 | 67 | 159 | 1,07 |

Phân bố trong 10k replay: **9.677 dòng dịch 1:1**, chỉ 309 dòng có tách câu. Trong 2.351
dòng nguồn có từ 3 dấu phẩy trở lên — đúng loại câu cần tách — chỉ **6,2%** được tách.

Replay chiếm 10.067/13.052 lượt train (77%) và dạy đúng thói quen gương chiếu dấu câu
tiếng Trung. 240–323 gold có nhịp tốt hơn (1,64) nhưng quá nhỏ để bẻ phân bố.

## 3. Đã loại giả thuyết "lỗi do engine cắt câu ở 90 token"

Kết luận vòng A/B (24/07) nghi lệch đơn vị train–inference. Đo lại trên teacher-v2
(`experiments/hachimi_teacher_v2_split_eval.md`):

| Chiến lược | Similarity | Đại từ hiện đại | Quote lỗi | câu/cảnh |
|---|---:|---:|---:|---:|
| current, cắt 90 | 0,7107 | 15 | 6 | 3,7 |
| v2, cắt 90 (production) | 0,7213 | 25 | 1 | 3,8 |
| v2, gom mệnh đề 160 | 0,7175 | 29 | 2 | 4,2 |
| v2, nguồn 448 / đích 448 | 0,7223 | 28 | **0** | 3,8 |
| tham chiếu | — | — | — | **5,3** |

Cho model nhìn trọn câu dài **không** làm nó ngắt câu thêm (3,8 → 3,8) và chỉ được
+0,001 similarity, đổi lại tăng đại từ hiện đại. ⇒ **Không phải lỗi splitter. Đừng đổi
splitter production.** Model không tách câu vì chưa từng được dạy tách.

## 4. Việc phải làm — data, không phải knob

1. **Gold nhịp câu ở cấp cảnh, có volume**: khai thác dòng nguồn có ≥3 dấu phẩy, dài
   150–400 ký tự từ kho chương đã dịch, cho Codex (chính nguồn đã tạo 60 tham chiếu mà
   user chấm là đọc ổn) viết lại đúng ba ràng buộc: giữ xưng hô ta/ngươi/hắn, **tách
   chuỗi phẩy thành câu tiếng Việt tự nhiên**, giữ nguyên tên riêng và số.
2. **Cổng nghiệm thu mới, khác các vòng trước**: ngoài Hán/quote/số/register, thêm cổng
   `câu VI / dấu 。 ZH ≥ 1,5` — loại thẳng bản teacher nào dịch gương 1:1. Không có cổng
   này thì thầy sẽ trả về đúng thứ replay đang có.
3. **Cân lại tỷ trọng**: replay 10k chỉ nên giữ vai chống quên. Gold nhịp câu cần đạt
   ~1.000–3.000 dòng (×3) mới đủ sức bẻ phân bố; 240 gold ×3 đã chứng minh là không đủ.
4. Giữ booster xưng hô/枪 của `07_make_booster_v3.py` — nó vá lỗi khác, không thay thế
   được mục 1.

Không nên: tăng epoch/gold-repeat (vòng B đã chứng minh loss đẹp hơn nhưng lỗi nghĩa
còn nguyên), đổi base to hơn (đã đo, chậm 10× và kém thuật ngữ tu tiên).
