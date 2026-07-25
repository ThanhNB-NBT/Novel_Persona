# Pilot fine-tune HachimiMT v-next

Đây là nhánh thí nghiệm, chưa thay model production.

## Dữ liệu được phép dùng

- `dataset/gold_approved_vnext.jsonl`: 240 cặp đã đọc và duyệt thủ công.
- `dataset/eval_reference_60.jsonl`: 60 cảnh khóa, chỉ dùng đánh giá.
- Replay chuẩn: `ngocdang83/tran-vi-teacher`.
- `approved_gold.jsonl`: replay lịch sử cục bộ, không phải gold người duyệt.

Không dùng `train_gold_vnext.jsonl`, `register_gold.jsonl`, `booster.jsonl` hoặc
`train_v2.jsonl` trong vòng này.

## Kiểm tra trước khi train

```bash
python kaggle_train.py --self-check
```

Trainer bắt buộc có cả `--gold` và `--eval`, chặn ZH trùng giữa hai tập, loại
duplicate/xung đột trong replay và không random-split dòng train làm eval.

## Kaggle — hai ứng viên A/B

Chấp nhận điều khoản của
[`ngocdang83/tran-vi-teacher`](https://huggingface.co/datasets/ngocdang83/tran-vi-teacher),
thêm `HF_TOKEN` vào Kaggle Secrets, bật Internet và GPU:

```bash
pip -q install "transformers==4.48.3" "datasets==3.3.2" \
  "accelerate==1.3.0" sentencepiece ctranslate2

python kaggle_train.py \
  --gold gold_approved_vnext.jsonl \
  --eval eval_reference_60.jsonl \
  --gold-repeat 1 --epochs 1 --lr 1e-5 \
  --output-dir /kaggle/working/hachimi-vnext-a --export-ct2

python kaggle_train.py \
  --gold gold_approved_vnext.jsonl \
  --eval eval_reference_60.jsonl \
  --gold-repeat 3 --epochs 1 --lr 1e-5 \
  --output-dir /kaggle/working/hachimi-vnext-b --export-ct2
```

Không tăng `gold-repeat` hoặc số epoch trước khi A/B qua tập 60 cảnh và pilot
toàn chương. Kết quả local hiện tại nằm trong `runs/`; xem
`../experiments/hachimi_vnext_ab_conclusion.md`.

## Ứng viên D — tái sử dụng dữ liệu lịch sử

Sau khi B chỉ cải thiện nhẹ và replay ngoài miền của C làm tăng lỗi xưng hô,
vòng kế tiếp dùng 240 gold đã duyệt lặp 3 lần cùng replay lịch sử cục bộ. Loader
tự loại trùng với gold/eval, xung đột cùng nguồn Trung và câu không qua cổng
xưng hô; hiện còn 4.948/5.000 cặp replay, tổng 5.668 lượt train.

Thư mục `_kaggle_upload/` đã có đủ năm file cần tải lên Kaggle:
`kaggle_train.py`, `text_clean.py`, `gold_approved_vnext.jsonl`,
`eval_reference_60.jsonl` và `historical_replay.jsonl`.

```bash
python kaggle_train.py --self-check

python kaggle_train.py \
  --gold gold_approved_vnext.jsonl \
  --eval eval_reference_60.jsonl \
  --extra-replay historical_replay.jsonl --extra-replay-limit 20000 \
  --pro-limit 0 --replay-limit 0 \
  --gold-repeat 3 --epochs 1 --lr 1e-5 \
  --output-dir /kaggle/working/hachimi-vnext-d --export-ct2
```

Không đưa `register_gold`, `booster`, `train_gold_vnext` hoặc replay ngoài miền
của ứng viên C vào vòng D.

## Ứng viên E — replay nghiêm + regularizer xưng hô

D cải thiện cấu trúc nhưng làm `tôi/mình` tăng trên chương dài. E giữ 4.804 replay
lịch sử qua cổng văn phong nghiêm, thêm 180 booster cân bằng `hắn/nàng/ta`, cùng
240 gold lặp 3 lần. Gói tải Kaggle:
`../experiments/hachimi-vnext-e-kaggle.zip`.

```bash
python kaggle_train.py \
  --gold gold_approved_vnext.jsonl \
  --eval eval_reference_60.jsonl \
  --extra-replay replay_strict_vnext_e.jsonl \
  --extra-replay-limit 20000 \
  --pro-limit 0 --replay-limit 0 \
  --gold-repeat 3 --epochs 1 --lr 1e-5 \
  --output-dir /kaggle/working/hachimi-vnext-e --export-ct2
```

Đánh giá E ở cả split production hiện tại và chế độ giữ dòng tối đa 448 token;
không đổi split production trước khi E qua cổng xưng hô và sáu chương dài.
