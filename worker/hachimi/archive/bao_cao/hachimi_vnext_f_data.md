# Dữ liệu ứng viên Hachimi v-next F

F là một phép thử mới từ base `ngocdang83/HachimiMT-60-zh-vi`, không resume D/E.

## Thành phần train

- Gold: 240 cặp `gold_approved_vnext.jsonl`, đã duyệt thủ công, lặp 3 lần = 720 lượt.
- Replay: tối đa 20.000 cặp stream trực tiếp từ `ngocdang83/tran-vi-teacher` qua cổng nghiêm toàn target.
- Holdout: 60 cặp `eval_reference_60.jsonl`, bị chặn khỏi mọi replay.
- Tổng tối đa: 20.720 lượt train.

## Nguồn bị loại có chủ đích

- `approved_gold.jsonl`/historical replay D/E: provenance lịch sử, đã cho regression xưng hô.
- `train_v2`, `register_gold`, booster: chưa đủ độ tin cậy hoặc synthetic; không dùng để che lỗi data gốc.
- moa, kaihe, VnAPE, VietPhrase: khác miền/phong cách hoặc không có provenance tương đương corpus gốc.

## Cổng replay

Cổng chạy ngay trong `kaggle_train.py` trên cặp `ZH → VI` đã stream: ZH phải có ít nhất một
chữ Hán, ZH/VI không mojibake và quote cân; VI không còn Hán, dãy số ZH/VI khớp, tỷ lệ ký tự
bỏ trắng nằm trong 0,25–4 và cấm register hiện đại cả trong thoại. Cổng này cố tình nghiêm hơn
gold: gold chỉ kiểm tra cấu trúc vì đã duyệt nghĩa/văn phong bằng tay.

Kết quả train F chỉ được xét nếu qua eval 60, đánh giá rộng và sáu chương dài; chưa có
quyền thay model production.
