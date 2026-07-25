# Nghiên cứu tối ưu Hachimi v-next E

Ngày: 2026-07-24. Phạm vi: nghiên cứu và chuẩn bị train; không sửa production.

## Phát hiện mới

### 1. Thước đo quote cũ thiếu dấu ASCII

Hàm cũ chỉ đếm `“…”`, `「…」`, `『…』`, bỏ qua `"..."`. Sau khi tính cả dấu
ASCII, eval 60 của current có 6 lỗi quote và D có 5; trên sáu chương dài cả hai
cùng có 4 đoạn lệch. Vì vậy D không làm quote xấu hơn như kết luận ban đầu.

### 2. Train và inference đang lệch độ dài ngữ cảnh

Trainer nhận tối đa 448 token, nhưng `_Engine._split_source()` hiện cắt câu quanh
90 token (`hachimi_max_len // 2`) trước khi dịch. Model vì thế không được nhìn
toàn bộ nhiều mẫu ngữ cảnh dài mà nó đã học.

Kết quả trên 60 cảnh khóa:

| Cấu hình | Similarity | Đại từ hiện đại | Đệm | Quote lỗi |
|---|---:|---:|---:|---:|
| current, chia 90 | 0,7107 | 15 | 2 | 6 |
| B, chia 90 | 0,7149 | 15 | 1 | 6 |
| B, giữ tối đa 448 | 0,7200 | 17 | 1 | 0 |
| D, chia 90 | 0,7160 | 15 | 1 | 5 |
| D, giữ tối đa 448 | 0,7199 | 18 | 1 | 0 |

Giữ ngữ cảnh dài sửa rõ cấu trúc và dấu thoại, nhưng làm đại từ hiện đại tăng.
Do đó không nên chỉ đổi split production; cần train E với regularizer xưng hô rồi
đánh giá lại cả hai chế độ.

### 3. Replay D không tuân thủ hoàn toàn văn phong `ta–ngươi`

Loader cũ bỏ phần lời thoại trước khi kiểm tra register. Cách này vẫn cho phép
`tôi`, `bạn`, `cậu`, `cháu` nằm trong lời thoại. Cổng nghiêm cho E kiểm tra toàn
bộ target, đồng thời vẫn giữ cổng lời kể cũ:

- 5.000 cặp lịch sử ban đầu;
- còn 4.804 sau khi loại register hiện đại, trùng gold/eval và dòng không an toàn;
- thêm 180 booster nhỏ, cân bằng 60 `hắn`, 60 `nàng`, 60 `ta`;
- 240 gold đã duyệt lặp 3 lần;
- tổng 5.704 lượt train.

Booster chỉ chiếm khoảng 3,2%, dùng làm regularizer; không lặp toàn bộ 1.200 câu
và không trộn `register_gold` lỗi như manifest cũ.

## Cơ sở nghiên cứu

- Nối các câu liên tiếp là cách đơn giản và cạnh tranh để đưa ngữ cảnh vào NMT,
  nhưng ngữ cảnh dài có thể làm attention phân tâm; focused concatenation dùng
  loss giảm trọng số phần context để giữ trọng tâm câu hiện tại:
  https://aclanthology.org/2022.wmt-1.77/
- Đánh giá context-aware NMT cần nhìn riêng hiện tượng đại từ và mạch lạc, vì điểm
  tổng hợp có thể không phản ánh các cải thiện hoặc regression này:
  https://aclanthology.org/2020.wmt-1.71/
- MarianMT là encoder–decoder Transformer 6 tầng với positional embedding tĩnh;
  fine-tune checkpoint sẵn có rẻ hơn train mới từ đầu:
  https://huggingface.co/docs/transformers/model_doc/marian
- CTranslate2 cho phép điều khiển `max_input_length`, `max_decoding_length` và
  target prefix; đủ để thử cửa sổ 448 mà chưa cần đổi kiến trúc:
  https://opennmt.net/CTranslate2/python/ctranslate2.Translator.html

## Recipe E

Train lại từ `ngocdang83/HachimiMT-60-zh-vi`:

```bash
python kaggle_train.py \
  --gold gold_approved_vnext.jsonl \
  --eval eval_reference_60.jsonl \
  --extra-replay replay_strict_vnext_e.jsonl \
  --extra-replay-limit 20000 \
  --pro-limit 0 --replay-limit 0 \
  --gold-repeat 3 --epochs 1 --lr 1e-5 \
  --output-dir /kaggle/working/hachimi-vnext-e \
  --export-ct2
```

## Cổng chấp nhận

Không chọn E chỉ vì similarity cao hơn:

1. Eval 60, chia 90: modern ≤ 15, quote lỗi ≤ 5, similarity ≥ 0,7160.
2. Eval 60, giữ 448: modern ≤ 15, quote lỗi = 0, similarity ≥ 0,7199.
3. Sáu chương dài: modern ≤ 39, đoạn lệch quote ≤ 4, Hán sót ≤ 21.
4. Đọc tay truyện 32: không tăng lỗi chủ thể; `玛利亚`, chức danh–tên và dãy số
   phải ổn hơn current/D.

Nếu E không qua, không tăng epoch hoặc booster. Khi đó cần tạo gold mới có mục
tiêu từ chính các đoạn lỗi ngữ cảnh, thay vì tiếp tục điều chỉnh trọng số.
