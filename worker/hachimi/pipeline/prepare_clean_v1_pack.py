"""Đóng gói Kaggle clean-v1 chỉ sau khi mọi shard đã khóa provenance."""
from __future__ import annotations

import hashlib
import json
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from kaggle_train import (
    MODEL_ID, MODEL_REVISION,
    assert_no_leakage, combine_clean_shards, load_clean_shard,
)


ROOT = Path(__file__).resolve().parent
EXPERIMENTS = ROOT.parent / "experiments"
sys.path.insert(0, str(ROOT.parent))
PACK = EXPERIMENTS / "hachimi-clean-v1-kaggle.zip"
CORE_GOLD = ROOT / "prepared_v1" / "core_gold.jsonl"
GAME_TRAIN = ROOT / "dataset" / "train_game_english_approved.jsonl"
DB_GAME_TRAIN = ROOT / "dataset" / "train_db_game_litrpg_approved.jsonl"
EVAL_60 = ROOT / "dataset" / "eval_reference_60.jsonl"
EVAL_GAME = ROOT / "dataset" / "eval_game_english_locked.jsonl"
EVAL_CHAPTERS = EXPERIMENTS / "hachimi_vnext_e_fullchapters.jsonl"
README = ROOT / "CLEAN_V1_PACK_README.md"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _locked_game_eval(path: Path) -> list[dict]:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not rows or any(row.get("status") != "locked_eval_reference" or not row.get("zh") or not row.get("reference_vi") for row in rows):
        raise ValueError(f"{path.name} phải chỉ có game eval status=locked_eval_reference, đủ zh/reference_vi")
    return rows


def _eval_manifest(eval_60: Path, chapters: Path, game_eval: Path) -> dict:
    from experiments.validate_hachimi_eval_suite import validate
    return validate(eval_60, chapters, game_eval)


def _locked_chapter_bytes(path: Path) -> bytes:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    keep = [{key: row[key] for key in ("novel_id", "title_zh", "title_vi", "chapter_index", "chapter_title_zh", "source_zh")} for row in rows]
    if len(keep) != 6 or len({row["source_zh"] for row in keep}) != 6:
        raise ValueError("Fullchapter source phải có đúng 6 nguồn Trung không trùng")
    return "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in keep).encode("utf-8")


def build(root: Path, pack: Path, chapter_source: Path = EVAL_CHAPTERS) -> dict:
    paths = {
        "core_gold_240.jsonl": root / CORE_GOLD.relative_to(ROOT),
        "train_game_english_approved.jsonl": root / GAME_TRAIN.relative_to(ROOT),
        "train_db_game_litrpg_approved.jsonl": root / DB_GAME_TRAIN.relative_to(ROOT),
        "eval_reference_60.jsonl": root / EVAL_60.relative_to(ROOT),
        "eval_game_english_locked.jsonl": root / EVAL_GAME.relative_to(ROOT),
        "README.md": root / README.relative_to(ROOT),
    }
    missing = [name for name, path in paths.items() if not path.is_file()]
    if not chapter_source.is_file():
        missing.append("hachimi_vnext_e_fullchapters.jsonl")
    if missing:
        raise FileNotFoundError(f"Chưa đóng gói: thiếu shard/README bắt buộc: {', '.join(missing)}")
    gold = load_clean_shard(paths["core_gold_240.jsonl"], require_approved=True)
    if len(gold) != 240:
        raise ValueError(f"core_gold_240.jsonl phải đúng 240 cặp, hiện {len(gold)}")
    game = load_clean_shard(paths["train_game_english_approved.jsonl"], require_approved=True)
    if not game:
        raise ValueError("Game train chưa có status=approved; không tạo ZIP")
    db_game = load_clean_shard(paths["train_db_game_litrpg_approved.jsonl"], require_approved=True)
    if not db_game:
        raise ValueError("DB game/LitRPG train chưa có status=approved; không tạo ZIP")
    _locked_game_eval(paths["eval_game_english_locked.jsonl"])
    clean_gold, clean_replay = combine_clean_shards([gold, game, db_game], [])
    chapter_bytes = _locked_chapter_bytes(chapter_source)
    assert_no_leakage([*clean_gold, *clean_replay], [
        paths["eval_reference_60.jsonl"], chapter_source, paths["eval_game_english_locked.jsonl"],
    ])
    manifest = _eval_manifest(paths["eval_reference_60.jsonl"], chapter_source, paths["eval_game_english_locked.jsonl"])
    manifest["chapters"] = {"path": "eval_fullchapters_6_locked.jsonl", "sha256": hashlib.sha256(chapter_bytes).hexdigest(), "rows": 6}
    manifest["train"] = {
        "base_model": MODEL_ID,
        "base_model_revision": MODEL_REVISION,
        "remote_teacher_replay_rows": 0,
        "seed": 20260719,
        "core_gold": {"sha256": _sha256(paths["core_gold_240.jsonl"]), "rows": len(gold), "weight": 3},
        "game_gold": {"sha256": _sha256(paths["train_game_english_approved.jsonl"]), "rows": len(game), "weight": 3},
        "db_game_gold": {"sha256": _sha256(paths["train_db_game_litrpg_approved.jsonl"]), "rows": len(db_game), "weight": 3},
    }
    manifest_path = root / "eval_manifest_clean_v1.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        with zipfile.ZipFile(pack, "w", zipfile.ZIP_DEFLATED) as archive:
            for name in ("kaggle_train.py", "text_clean.py"):
                archive.write(root / name, name)
            for name in ("core_gold_240.jsonl", "train_game_english_approved.jsonl", "train_db_game_litrpg_approved.jsonl", "eval_reference_60.jsonl", "eval_game_english_locked.jsonl", "README.md"):
                archive.write(paths[name], name)
            archive.writestr("eval_fullchapters_6_locked.jsonl", chapter_bytes)
            archive.write(manifest_path, "eval_manifest_clean_v1.json")
    finally:
        manifest_path.unlink(missing_ok=True)
    return {"pack": str(pack), "sha256": _sha256(pack), "manifest": manifest}


def self_check() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "dataset").mkdir()
        (root / "prepared_v1").mkdir()
        shutil.copy2(ROOT / "kaggle_train.py", root / "kaggle_train.py")
        shutil.copy2(ROOT / "text_clean.py", root / "text_clean.py")
        (root / "CLEAN_V1_PACK_README.md").write_text("test\n", encoding="utf-8")
        gold = [{"zh": f"甲{i}", "vi": "Ất", "status": "approved"} for i in range(240)]
        game = [{"zh": "丙", "vi": "Đinh", "status": "approved"}]
        db_game = [{"zh": "丁", "vi": "Mậu", "status": "approved"}]
        categories = ("semantic_context", "dialogue_register", "domain_terms", "number_negation", "quote_author", "natural_vi")
        eval_60 = [{"zh": f"戊{i}", "reference_vi": "Kỷ", "status": "locked_eval_reference", "eval_category": categories[i // 10]} for i in range(60)]
        chapters = [{"source_zh": f"Canh{i}", "novel_id": i + 1, "chapter_index": 1, "title_zh": "T", "title_vi": "T", "chapter_title_zh": "C", "outputs": {"ignored": True}} for i in range(6)]
        game_eval = [{"zh": "Tân", "reference_vi": "Nhâm", "status": "locked_eval_reference"}]
        (root / "prepared_v1" / "core_gold.jsonl").write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in gold), encoding="utf-8")
        for name, rows in (("train_game_english_approved.jsonl", game), ("train_db_game_litrpg_approved.jsonl", db_game), ("eval_reference_60.jsonl", eval_60), ("eval_game_english_locked.jsonl", game_eval)):
            (root / "dataset" / name).write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
        import sys
        sys.path.insert(0, str(ROOT.parent))
        chapter_source = root / "chapters_source.jsonl"
        chapter_source.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in chapters), encoding="utf-8")
        result = build(root, root / "pack.zip", chapter_source)
        with zipfile.ZipFile(root / "pack.zip") as archive:
            locked = [json.loads(line) for line in archive.read("eval_fullchapters_6_locked.jsonl").decode("utf-8").splitlines()]
        assert len(locked) == 6 and len({row["source_zh"] for row in locked}) == 6
        assert all("outputs" not in row for row in locked)
        assert result["manifest"]["chapters"]["sha256"] == hashlib.sha256(_locked_chapter_bytes(chapter_source)).hexdigest()
        overlap = root / "overlap.jsonl"
        overlap.write_text('{"zh":"甲0","reference_vi":"A","novel_id":99,"chapter_index":1}\n', encoding="utf-8")
        try:
            assert_no_leakage([{**gold[0], "source_hash": hashlib.sha256("甲0".encode("utf-8")).hexdigest(), "group": (None, None)}], [overlap])
            raise AssertionError("phải chặn overlap nguồn Trung")
        except ValueError:
            pass


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
        print("OK")
    else:
        try:
            print(json.dumps(build(ROOT, PACK), ensure_ascii=False, indent=2))
        except (FileNotFoundError, ValueError) as exc:
            raise SystemExit(str(exc)) from exc
