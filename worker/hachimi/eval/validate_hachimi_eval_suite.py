"""Khóa manifest eval trước khi chạy model; không gọi DB hay model."""
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path


REQUIRED_CATEGORIES = {
    "semantic_context", "dialogue_register", "domain_terms",
    "number_negation", "quote_author", "natural_vi",
}


def source_hash(row: dict) -> str:
    source = str(row.get("zh") or row.get("source_zh") or "").strip()
    if not source:
        raise ValueError("Thiếu zh/source_zh")
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _manifest(path: Path, rows: list[dict]) -> dict:
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "rows": len(rows)}


def validate(eval_60: Path, chapters: Path, game_eval: Path | None = None) -> dict:
    rows = read_jsonl(eval_60)
    chapter_rows = read_jsonl(chapters)
    if len(rows) != 60 or len(chapter_rows) != 6:
        raise ValueError(f"Eval phải có 60 cảnh và 6 chương, hiện là {len(rows)} / {len(chapter_rows)}")
    if any(row.get("status") != "locked_eval_reference" or not row.get("reference_vi") for row in rows):
        raise ValueError("Eval 60 phải có status=locked_eval_reference và reference_vi")
    counts = {category: sum(row.get("eval_category") == category for row in rows) for category in REQUIRED_CATEGORIES}
    if any(count != 10 for count in counts.values()):
        raise ValueError(f"Eval 60 cần đúng 10 mỗi category: {counts}")
    if any(not row.get("novel_id") or row.get("chapter_index") is None for row in chapter_rows):
        raise ValueError("Mỗi chương khóa phải có novel_id và chapter_index")
    game_rows = read_jsonl(game_eval) if game_eval else []
    if any(row.get("status") != "locked_eval_reference" or not row.get("reference_vi") for row in game_rows):
        raise ValueError("--game-eval phải là reference đã khóa có status=locked_eval_reference")
    all_rows = [*rows, *chapter_rows, *game_rows]
    hashes = [source_hash(row) for row in all_rows]
    if len(hashes) != len(set(hashes)):
        raise ValueError("Eval có leakage nội bộ theo hash nguồn Trung")
    return {
        "eval_60": _manifest(eval_60, rows),
        "chapters": _manifest(chapters, chapter_rows),
        "game_eval": _manifest(game_eval, game_rows) if game_eval else None,
        "categories": counts,
        "source_hashes": hashes,
    }


def self_check() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        eval_path, chapter_path, game_path = root / "eval.jsonl", root / "chapters.jsonl", root / "game.jsonl"
        categories = sorted(REQUIRED_CATEGORIES)
        eval_rows = [{"zh": f"甲{i}", "reference_vi": "A", "status": "locked_eval_reference", "eval_category": categories[i // 10]} for i in range(60)]
        chapter_rows = [{"source_zh": f"乙{i}", "novel_id": i + 1, "chapter_index": 1} for i in range(6)]
        game_rows = [{"zh": "丙", "reference_vi": "C", "status": "locked_eval_reference"}]
        eval_path.write_text("".join(json.dumps(row) + "\n" for row in eval_rows), encoding="utf-8")
        chapter_path.write_text("".join(json.dumps(row) + "\n" for row in chapter_rows), encoding="utf-8")
        game_path.write_text("".join(json.dumps(row) + "\n" for row in game_rows), encoding="utf-8")
        assert validate(eval_path, chapter_path, game_path)["eval_60"]["rows"] == 60


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--eval-60", type=Path)
    parser.add_argument("--chapters", type=Path)
    parser.add_argument("--game-eval", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
        print("OK")
    else:
        if not args.eval_60 or not args.chapters or not args.output:
            raise SystemExit("Cần --eval-60 --chapters --output")
        args.output.write_text(json.dumps(validate(args.eval_60, args.chapters, args.game_eval), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
