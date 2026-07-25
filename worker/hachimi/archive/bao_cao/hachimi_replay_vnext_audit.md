# Replay Hachimi v-next — kết luận về `train_v2`

**Không dùng `dataset/train_v2.jsonl` làm replay cho vòng train này.**

Thử lọc toàn bộ 87.338 dòng bằng cổng cơ học (Unicode, artefact, trùng/xung đột,
rò eval/gold, giới hạn SentencePiece 448 token và xưng hô hiện đại) vẫn để lọt
những cặp lệch dòng hoàn toàn. Trong 20.000 cặp ứng viên sau lọc:

- 29 dòng có dấu thoại lẻ và 7 dòng có tỷ lệ độ dài bất thường;
- đọc 36 dòng trên thấy ít nhất 6 cặp ZH/VI không cùng nội dung;
- mẫu ngẫu nhiên còn có thuật ngữ sai và câu Việt kém tự nhiên như
  `气运子 → tử khí vận tử`, dù cặp vẫn căn đúng dòng.

Đây là lỗi ngữ nghĩa/alignment, không thể sửa an toàn bằng regex. Manifest thử
nghiệm 20.000 dòng đã bị xóa để tránh vô tình đưa vào train.

Replay v-next dùng corpus gốc do `kaggle_train.py::load_replay()` tải trực tiếp,
không truyền `--extra-replay dataset/train_v2.jsonl`. Lời tác giả vẫn được giữ;
không dùng từ khóa lời tác giả làm điều kiện loại.
