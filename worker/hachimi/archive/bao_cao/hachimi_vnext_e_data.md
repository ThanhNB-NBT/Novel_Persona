# Dữ liệu ứng viên Hachimi v-next E

Đây là artifact nghiên cứu; chưa train và không thay model production.

- Gold đã duyệt: 240 cặp, dự kiến lặp 3 lần.
- Eval khóa: 60 cặp, không nằm trong train.
- Replay lịch sử giữ lại: 4804 cặp; loại 196 dòng do trùng holdout hoặc không qua cổng văn phong nghiêm.
- Booster nhỏ: 180 cặp; cân bằng {'他': 60, '她': 60, '我': 60}.
- Tổng replay E: 4984; tổng lượt train dự kiến: 5704.

Recipe: train từ base Hachimi, 1 epoch, learning rate `1e-5`; đánh giá bằng chiến lược giữ nguyên dòng tối đa 448 token và output tối đa 448.

Không dùng `register_gold`, `train_gold_vnext`, booster 1.200 dòng nguyên khối hoặc replay ngoài miền.
