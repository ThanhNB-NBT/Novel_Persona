# Hachimi v-next F — gói Kaggle

Candidate F fine-tune trực tiếp từ `ngocdang83/HachimiMT-60-zh-vi`; chưa thay model production.

Gói này chỉ chứa 240 gold đã duyệt, 60 eval khóa và trainer. Replay được stream trên Kaggle
từ `ngocdang83/tran-vi-teacher`, nên không thể vô tình trộn replay D/E vào train.

## Cổng dữ liệu

- Gold không chạy cổng văn phong vì đã duyệt tay, nhưng vẫn chặn Hán trong VI, mojibake và quote lệch.
- Replay phải có nguồn Trung thật, nguồn/đích không mojibake, nguồn/đích quote cân; target không Hán,
  số giữ nguyên, tỷ lệ độ dài 0,25–4,
  không mojibake và không có `tôi/mình/bạn/cậu/cháu/anh ta/cô ta/cô ấy/cậu ta/ông ta/bà ta`, kể cả thoại.
- Loader chặn nguồn Trung trùng/xung đột và không cho replay đè gold hoặc eval.

## Kaggle

Bật Internet và GPU. `HF_TOKEN` chỉ cần thêm vào Kaggle Secrets nếu Hugging Face báo dataset
yêu cầu xác thực hoặc bị gated; dataset công khai chạy không cần token.

```bash
pip -q install "transformers==4.48.3" "datasets==3.3.2" \
  "accelerate==1.3.0" sentencepiece ctranslate2

python kaggle_train.py --self-check

python kaggle_train.py \
  --gold gold_approved_vnext.jsonl \
  --eval eval_reference_60.jsonl \
  --pro-limit 0 --replay-limit 20000 \
  --gold-repeat 3 --epochs 1 --lr 1e-5 \
  --output-dir /kaggle/working/hachimi-vnext-f --export-ct2
```

Không truyền `--extra-replay`. Không dùng historical replay D/E, `train_v2`,
`register_gold`, booster, moa, kaihe, VnAPE hoặc VietPhrase.

Sau train, chỉ tải `ct2-int8_float32/` và `training_mix.json` để đánh giá local.
