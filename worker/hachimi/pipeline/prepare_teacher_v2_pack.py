"""Đóng gói teacher replay đã sàng lọc cùng 323 gold đã khóa."""

from __future__ import annotations

import hashlib
import json
import tempfile
import zipfile
from pathlib import Path

from kaggle_train import (
    MODEL_ID,
    MODEL_REVISION,
    assert_no_leakage,
    combine_clean_shards,
    load_clean_shard,
)
from prepare_clean_v1_pack import _locked_chapter_bytes


ROOT = Path(__file__).resolve().parent
HUB = ROOT.parent
DATA = HUB / "data"
PACK = HUB / "packs" / "hachimi-teacher-v2-kaggle.zip"
CORE = DATA / "gold" / "core_gold.jsonl"
GAME_GOLD = DATA / "gold" / "train_game_english_approved.jsonl"
DB_GAME_GOLD = DATA / "gold" / "train_db_game_litrpg_approved.jsonl"
GENERAL = DATA / "replay" / "general_candidate.jsonl"
GAME_REPLAY = DATA / "replay" / "game_high_confidence_candidate.jsonl"
EVAL = DATA / "eval_locked" / "eval_reference_60.jsonl"
EVAL_GAME = DATA / "eval_locked" / "eval_game_english_locked.jsonl"
EVAL_CHAPTERS = DATA / "eval_locked" / "hachimi_vnext_e_fullchapters.jsonl"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def candidate_bytes(path: Path, category: str) -> bytes:
    rows = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        row = json.loads(line)
        if (
            row.get("status") != "candidate_teacher"
            or not row.get("zh")
            or not row.get("vi")
            or not row.get("source_hash")
            or not row.get("provenance")
        ):
            raise ValueError(f"{path}:{number} không phải teacher candidate đủ provenance")
        rows.append({
            **row,
            "status": "approved_replay",
            "source": f"screened_teacher_{category}",
            "category": category,
        })
    if not rows:
        raise ValueError(f"{path} rỗng")
    return "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows).encode("utf-8")


def readme(total: int) -> str:
    return f"""# Hachimi teacher v2 — Kaggle

Teacher replay là dữ liệu Gemini Pro/Flash đã sàng lọc, trọng số 1; không phải
human gold. Chỉ 323 gold đã duyệt được lặp 3 lần. Tổng lượt train: {total}.

```bash
pip -q install "transformers==4.48.3" "datasets==3.3.2" "accelerate==1.3.0" sentencepiece ctranslate2
accelerate launch --num_processes=2 --multi_gpu kaggle_train.py \\
  --clean-gold core_gold_240.jsonl --clean-gold train_game_english_approved.jsonl \\
  --clean-gold train_db_game_litrpg_approved.jsonl \\
  --clean-replay teacher_general_pro_10000.jsonl \\
  --clean-replay teacher_game_screened.jsonl \\
  --eval eval_reference_60.jsonl --eval-chapters eval_fullchapters_6_locked.jsonl \\
  --eval-chapters eval_game_english_locked.jsonl --pro-limit 0 --replay-limit 0 \\
  --gold-repeat 3 --epochs 1 --lr 1e-5 \\
  --output-dir /kaggle/working/hachimi-teacher-v2 --export-ct2
```
"""


def build() -> dict:
    required = (
        ROOT / "kaggle_train.py", ROOT / "text_clean.py", CORE, GAME_GOLD,
        DB_GAME_GOLD, GENERAL, GAME_REPLAY, EVAL, EVAL_GAME, EVAL_CHAPTERS,
    )
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"Thiếu input bắt buộc: {', '.join(missing)}")

    general_bytes = candidate_bytes(GENERAL, "teacher_general")
    game_bytes = candidate_bytes(GAME_REPLAY, "teacher_game")
    chapter_bytes = _locked_chapter_bytes(EVAL_CHAPTERS)
    with tempfile.TemporaryDirectory() as directory:
        temp = Path(directory)
        general_path = temp / "teacher_general_pro_10000.jsonl"
        game_path = temp / "teacher_game_screened.jsonl"
        general_path.write_bytes(general_bytes)
        game_path.write_bytes(game_bytes)
        gold_shards = [
            load_clean_shard(CORE, require_approved=True),
            load_clean_shard(GAME_GOLD, require_approved=True),
            load_clean_shard(DB_GAME_GOLD, require_approved=True),
        ]
        replay_shards = [
            load_clean_shard(general_path, require_approved=False),
            load_clean_shard(game_path, require_approved=False),
        ]
        gold, replay = combine_clean_shards(gold_shards, replay_shards)
        assert_no_leakage([*gold, *replay], [EVAL, EVAL_GAME, EVAL_CHAPTERS])
        if len(gold) != 323 or len(replay) != 10_067:
            raise ValueError(f"Quy mô đã đổi: gold={len(gold)}, replay={len(replay)}")
        total = len(replay) + len(gold) * 3
        manifest = {
            "status": "ready_for_kaggle_train",
            "base_model": MODEL_ID,
            "base_model_revision": MODEL_REVISION,
            "teacher_dataset": "ngocdang83/tran-vi-teacher",
            "teacher_dataset_revision": "63525802de537b11eb28aacbe1d2a23769548758",
            "gold": {"rows": len(gold), "weight": 3},
            "replay": {
                "general_pro": 10_000,
                "game_screened": 67,
                "weight": 1,
            },
            "total_rows": total,
            "eval_rows": 60,
            "eval_game_rows": sum(bool(line.strip()) for line in EVAL_GAME.read_text(encoding="utf-8").splitlines()),
            "eval_fullchapters": 6,
            "leakage": 0,
            "teacher_general_sha256": digest(general_bytes),
            "teacher_game_sha256": digest(game_bytes),
        }
        manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        with zipfile.ZipFile(PACK, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.write(ROOT / "kaggle_train.py", "kaggle_train.py")
            archive.write(ROOT / "text_clean.py", "text_clean.py")
            archive.write(CORE, "core_gold_240.jsonl")
            archive.write(GAME_GOLD, "train_game_english_approved.jsonl")
            archive.write(DB_GAME_GOLD, "train_db_game_litrpg_approved.jsonl")
            archive.writestr("teacher_general_pro_10000.jsonl", general_bytes)
            archive.writestr("teacher_game_screened.jsonl", game_bytes)
            archive.write(EVAL, "eval_reference_60.jsonl")
            archive.write(EVAL_GAME, "eval_game_english_locked.jsonl")
            archive.writestr("eval_fullchapters_6_locked.jsonl", chapter_bytes)
            archive.writestr("README.md", readme(total))
            archive.writestr("training_manifest.json", manifest_bytes)
    return {**manifest, "pack": str(PACK), "pack_sha256": digest(PACK.read_bytes())}


def self_check() -> None:
    result = build()
    assert result["total_rows"] == 11_036
    assert result["leakage"] == 0
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    self_check()
