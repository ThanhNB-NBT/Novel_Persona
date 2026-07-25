"""Gói train v3 = mix teacher-v2 + booster khoá xưng hô thoại và nghĩa 枪.

Giữ nguyên phần đã chứng minh có lợi ở v2 (10.067 replay teacher đã sàng, 323 gold ×3)
và chỉ thêm một shard gold mới sinh bằng 07_make_booster_v3.py.
"""
from __future__ import annotations

import json
import tempfile
import zipfile
from pathlib import Path

from kaggle_train import MODEL_ID, MODEL_REVISION, assert_no_leakage, combine_clean_shards, load_clean_shard
from prepare_clean_v1_pack import _locked_chapter_bytes
from prepare_teacher_v2_pack import (
    CORE, DB_GAME_GOLD, EVAL, EVAL_CHAPTERS, EVAL_GAME, GAME_GOLD, GAME_REPLAY, GENERAL,
    candidate_bytes, digest,
)


ROOT = Path(__file__).resolve().parent
DATA = ROOT.parent / "data"
BOOSTER = DATA / "gold" / "booster_v3.jsonl"
RHYTHM = DATA / "gold" / "rhythm_labeled_all_approved.jsonl"
GENERAL_SCREENED = DATA / "replay" / "general_candidate_rhythm_screened.jsonl"
PACK = ROOT.parent / "packs" / "hachimi-teacher-v3-kaggle.zip"


def rhythm_bytes() -> bytes:
    """Gold nhịp câu do thầy viết, nạp ở slot replay (trọng số 1) vì không phải người duyệt."""
    rows = [json.loads(line) for line in RHYTHM.read_text(encoding="utf-8").splitlines() if line.strip()]
    return "".join(
        json.dumps({"zh": row["zh"], "vi": row["vi"], "status": "approved_replay",
                    "source": "codex_rhythm_gold", "novel_id": row.get("novel_id"),
                    "chapter_index": row.get("chapter_index")}, ensure_ascii=False) + "\n"
        for row in rows
    ).encode("utf-8")


def readme(total: int, booster: int) -> str:
    return f"""# Hachimi teacher v3 — Kaggle

Ba thay đổi so với v2:

1. **Gold nhịp câu** (`rhythm_gold.jsonl`): dòng nguồn có chuỗi phẩy dài, thầy viết lại để
   ngắt thành câu tiếng Việt (tỷ lệ câu VI/dấu 。 = 2,30; tham chiếu 2,06). Nạp ở slot
   replay trọng số 1 vì là bản máy đã qua cổng, không phải người duyệt.
2. **Replay đã sàng nhịp**: bỏ khỏi teacher replay các dòng nguồn có ≥3 dấu phẩy mà đích
   vẫn gói thành một câu — chính chúng dạy model dịch 1:1 theo dấu câu tiếng Trung.
3. **Booster** {booster} câu: khoá xưng hô trong lời thoại + 枪 = thương/súng.

Gold lặp 3 lần, replay trọng số 1. Tổng lượt train: {total}.

```bash
pip -q install "transformers==4.48.3" "datasets==3.3.2" "accelerate==1.3.0" sentencepiece ctranslate2
accelerate launch --num_processes=2 --multi_gpu kaggle_train.py \\
  --clean-gold core_gold_240.jsonl --clean-gold train_game_english_approved.jsonl \\
  --clean-gold train_db_game_litrpg_approved.jsonl --clean-gold booster_v3.jsonl \\
  --clean-replay teacher_general_screened.jsonl \\
  --clean-replay teacher_game_screened.jsonl \\
  --clean-replay rhythm_gold.jsonl \\
  --eval eval_reference_60.jsonl --eval-chapters eval_fullchapters_6_locked.jsonl \\
  --eval-chapters eval_game_english_locked.jsonl --pro-limit 0 --replay-limit 0 \\
  --gold-repeat 3 --epochs 1 --lr 1e-5 \\
  --output-dir /kaggle/working/hachimi-teacher-v3 --export-ct2
```

Đo lại bằng `python -m experiments.evaluate_hachimi_teacher_v2` sau khi tải model về:
mục tiêu là giữ similarity/quote của v2 và kéo cột "đại từ hiện đại" xuống ≤ current.
"""


def build() -> dict:
    general_bytes = candidate_bytes(GENERAL_SCREENED, "teacher_general")
    game_bytes = candidate_bytes(GAME_REPLAY, "teacher_game")
    rhythm = rhythm_bytes()
    chapter_bytes = _locked_chapter_bytes(EVAL_CHAPTERS)
    with tempfile.TemporaryDirectory() as directory:
        temp = Path(directory)
        general_path = temp / "teacher_general_screened.jsonl"
        game_path = temp / "teacher_game_screened.jsonl"
        rhythm_path = temp / "rhythm_gold.jsonl"
        general_path.write_bytes(general_bytes)
        game_path.write_bytes(game_bytes)
        rhythm_path.write_bytes(rhythm)
        gold_shards = [
            load_clean_shard(path, require_approved=True)
            for path in (CORE, GAME_GOLD, DB_GAME_GOLD, BOOSTER)
        ]
        replay_shards = [
            load_clean_shard(general_path, require_approved=False),
            load_clean_shard(game_path, require_approved=False),
            load_clean_shard(rhythm_path, require_approved=False),
        ]
        gold, replay = combine_clean_shards(gold_shards, replay_shards)
        assert_no_leakage([*gold, *replay], [EVAL, EVAL_GAME, EVAL_CHAPTERS])
        booster_rows = len(gold_shards[-1])
        total = len(replay) + len(gold) * 3
        manifest = {
            "status": "ready_for_kaggle_train",
            "base_model": MODEL_ID,
            "base_model_revision": MODEL_REVISION,
            "teacher_dataset": "ngocdang83/tran-vi-teacher",
            "teacher_dataset_revision": "63525802de537b11eb28aacbe1d2a23769548758",
            "gold": {"rows": len(gold), "weight": 3, "booster_rows": booster_rows},
            "replay": {"rows": len(replay), "weight": 1},
            "total_rows": total,
            "leakage": 0,
            "booster_sha256": digest(BOOSTER.read_bytes()),
        }
        with zipfile.ZipFile(PACK, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.write(ROOT / "kaggle_train.py", "kaggle_train.py")
            archive.write(ROOT / "text_clean.py", "text_clean.py")
            archive.write(CORE, "core_gold_240.jsonl")
            archive.write(GAME_GOLD, "train_game_english_approved.jsonl")
            archive.write(DB_GAME_GOLD, "train_db_game_litrpg_approved.jsonl")
            archive.write(BOOSTER, "booster_v3.jsonl")
            archive.writestr("teacher_general_screened.jsonl", general_bytes)
            archive.writestr("teacher_game_screened.jsonl", game_bytes)
            archive.writestr("rhythm_gold.jsonl", rhythm)
            archive.write(EVAL, "eval_reference_60.jsonl")
            archive.write(EVAL_GAME, "eval_game_english_locked.jsonl")
            archive.writestr("eval_fullchapters_6_locked.jsonl", chapter_bytes)
            archive.writestr("README.md", readme(total, booster_rows))
            archive.writestr("training_manifest.json", (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return {**manifest, "pack": str(PACK), "pack_sha256": digest(PACK.read_bytes())}


if __name__ == "__main__":
    result = build()
    assert result["leakage"] == 0
    print(json.dumps(result, ensure_ascii=False, indent=2))
