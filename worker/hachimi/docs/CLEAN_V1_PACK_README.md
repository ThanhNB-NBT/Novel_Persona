# Clean v1 — Kaggle

Pack này chỉ nhận shard đã khóa; không chứa review pool, quarantine hoặc external accepted rỗng. `core_gold_240.jsonl` trong ZIP là bản đổi tên từ `prepared_v1/core_gold.jsonl`; không tạo bản sao data mới trong repo.

```bash
pip -q install "transformers==4.48.3" "datasets==3.3.2" "accelerate==1.3.0" sentencepiece ctranslate2
accelerate launch --num_processes=2 --multi_gpu kaggle_train.py \
  --clean-gold core_gold_240.jsonl --clean-gold train_game_english_approved.jsonl \
  --clean-gold train_db_game_litrpg_approved.jsonl \
  --eval eval_reference_60.jsonl --eval-chapters eval_fullchapters_6_locked.jsonl \
  --eval-chapters eval_game_english_locked.jsonl --pro-limit 0 --replay-limit 0 \
  --gold-repeat 3 --epochs 1 --lr 1e-5 \
  --output-dir /kaggle/working/hachimi-clean-v1 --export-ct2
```

Model nền là `ngocdang83/HachimiMT-60-zh-vi`. CT2 hiện tại chỉ là baseline eval; không phải resume checkpoint.

`eval_fullchapters_6_locked.jsonl` là sáu chương nguồn Trung khóa để eval định tính, không phải train input.
