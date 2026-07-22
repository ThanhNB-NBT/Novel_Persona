# Fine-tune HachimiMT-60 theo giọng cổ phong

`review_gold.jsonl` là đề xuất từ lỗi benchmark, **chưa được dùng để train**.
Chỉ các dòng đã được duyệt và đổi trạng thái thành `approved` mới được chép vào
`approved_gold.jsonl` để Kaggle nhận.

Tập Mistral đã restore trong `dataset_game/` không dùng làm nhãn train. Chỉ có
thể tái dùng phần Trung để tìm ví dụ mới; nhãn Việt chứa nhiều lỗi đã xác nhận.

Quy ước gold cổ phong: không dùng đại từ `y`; nam hoặc chưa xác định dùng
`hắn`, nữ dùng `nàng`; hội thoại cổ phong dùng `ta` / `ngươi` khi phù hợp.

## Kaggle — 2x T4 (recommended)

1. Trên Hugging Face, chấp nhận điều khoản của
   [`ngocdang83/tran-vi-teacher`](https://huggingface.co/datasets/ngocdang83/tran-vi-teacher)
   rồi thêm `HF_TOKEN` vào Kaggle Secrets.
2. Upload thư mục này thành Kaggle Dataset, kèm `approved_gold.jsonl` sau khi
   review. Nếu dùng extra replay, upload thêm `dataset_game/train_v2.jsonl`.
3. Bật **Internet**, **GPU T4 x2**, rồi chạy:

```bash
!pip -q install "transformers==4.48.3" "datasets==3.3.2" "accelerate==1.3.0" sentencepiece ctranslate2

# Chạy DDP trên 2 GPU T4
!accelerate launch --num_processes=2 --multi_gpu \
  /kaggle/input/hachimi-cophong/kaggle_train.py \
  --gold /kaggle/input/hachimi-cophong/approved_gold.jsonl \
  --extra-replay /kaggle/input/hachimi-cophong/train_v2.jsonl \
  --extra-replay-limit 20000 \
  --output-dir /kaggle/working/hachimi-60-cophong \
  --export-ct2
```

### Tham số mặc định (tối ưu cho 2x T4 16GB)

| Tham số | Giá trị | Ghi chú |
|---------|---------|----------|
| per-device-batch | 8 | T4 dư sức cho model 60M |
| grad-accum | 4 | Effective batch = 8×4×2 GPU = 64 |
| lr | 3e-5 | Cosine schedule |
| epochs | 3 | Đủ cho 5k gold + 53k replay |
| gold-repeat | 5 | 5000×5 = 25k gold-weighted |
| warmup-ratio | 0.05 | Ổn định đầu training |
| weight-decay | 0.01 | Chống overfit |

### Training mix

- **Pro** (9k): hàng chất lượng cao nhất từ corpus gốc
- **Replay** (24k): xác định từ phần còn lại, chống quên
- **Extra replay** (20k): từ `train_v2.jsonl`, mở rộng coverage
- **Gold** (5000×5 = 25k): câu đã được human review, trọng số cao
- **Tổng**: ~78k rows

### Nếu chỉ có 1x T4

```bash
!python /kaggle/input/hachimi-cophong/kaggle_train.py \
  --gold /kaggle/input/hachimi-cophong/approved_gold.jsonl \
  --per-device-batch 4 --grad-accum 8 \
  --output-dir /kaggle/working/hachimi-60-cophong \
  --export-ct2
```

Tập train gồm các hàng `pro` của corpus gốc (chất lượng teacher cao nhất),
replay xác định được từ phần còn lại, và gold đã duyệt được lặp lại để có trọng số.
Script dừng ngay nếu gold rỗng hoặc còn trạng thái chưa duyệt.
