"""So sánh Hachimi gốc, model production và ứng viên teacher-v2 trên eval đã khóa.

Chạy hai tập: 60 cảnh tham chiếu (có glossary approved từ DB) và 36 câu game tiếng
Anh đã khóa (không glossary). Chỉ đọc DB.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

from novelworker.translator.hachimi_engine import _Engine
from novelworker.translator.text_clean import clean_source

from audit_hachimi_base_longform import metrics, pipeline, translate_block
from eval_common import EVAL, EVAL_GAME, MODELS_DIR, balanced_quotes, load_terms, similarity


OUTPUT_JSONL = Path(__file__).with_name("hachimi_eval_locked.jsonl")
OUTPUT_MD = Path(__file__).with_name("hachimi_eval_locked.md")
# Sau khi chốt v4 (25/07) các bản cũ đã xoá; `hachimi-ct2` là bản đang mount trên VPS.
# Thêm model mới thì tải về worker/models/<tên> rồi khai một dòng ở đây.
MODELS = {
    "current": MODELS_DIR / "hachimi-ct2",
    "teacher_v4": MODELS_DIR / "hachimi-teacher-v4",
}
KEYS = ("similarity", "sentences", "han", "modern_pronouns", "padding")


def sentences(text: str) -> int:
    """Nhịp câu — chỉ số quyết định của vòng v3 (xem docs/hachimi_rhythm_research.md)."""
    return len([part for part in re.split(r"(?<=[.!?…])\s+", text) if part.strip()])


def score(source: str, raw: str, restored: str, reference: str) -> dict:
    counts = metrics(source, raw, restored)
    return {
        "pipeline": restored,
        "similarity": round(similarity(reference, restored), 4),
        "sentences": sentences(restored),
        "han": counts["pipeline_han"],
        "modern_pronouns": counts["pipeline_modern_pronouns"],
        "padding": counts["pipeline_padding"],
        "quotes_balanced": balanced_quotes(restored),
        "digits_match": re.findall(r"\d+", source) == re.findall(r"\d+", restored),
        "length_ratio": round(len(restored) / max(1, len(source)), 3),
    }


def accumulate(summary: dict[str, float], item: dict) -> None:
    for key in KEYS:
        summary[key] += item[key]
    summary["quote_fail"] += not item["quotes_balanced"]
    summary["digit_fail"] += not item["digits_match"]


def table(title: str, summary: dict[str, dict[str, float]], total: int, reference_sentences: float = 0) -> list[str]:
    lines = [
        f"## {title} ({total} câu)",
        "",
        "| Model | Similarity TB | Câu/cảnh | Hán sót | Đại từ hiện đại | Đệm thừa | Quote lỗi | Số lỗi |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in MODELS:
        item = summary[name]
        lines.append(
            f"| `{name}` | {item['similarity'] / total:.4f} | {item['sentences'] / total:.1f} | "
            f"{int(item['han'])} | {int(item['modern_pronouns'])} | {int(item['padding'])} | "
            f"{int(item['quote_fail'])} | {int(item['digit_fail'])} |"
        )
    if reference_sentences:
        lines.append(f"| `tham chiếu` | — | {reference_sentences / total:.1f} | — | — | — | — | — |")
    return lines + [""]


def run_reference(engines: dict[str, _Engine]) -> tuple[list[dict], dict, int]:
    rows = [
        json.loads(line)
        for line in EVAL.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    terms_by_novel = {novel_id: load_terms(novel_id) for novel_id in {row["novel_id"] for row in rows}}
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    results = []
    for index, row in enumerate(rows, start=1):
        source = clean_source(row["zh"])
        outputs = {}
        for name, engine in engines.items():
            raw, restored = pipeline(engine, source, terms_by_novel[row["novel_id"]])
            outputs[name] = score(source, raw, restored, row["reference_vi"])
            accumulate(summary[name], outputs[name])
        results.append({
            "set": "reference_60",
            "eval_category": row["eval_category"],
            "novel_id": row["novel_id"],
            "source_clean": source,
            "reference_vi": row["reference_vi"],
            "outputs": outputs,
        })
        print(f"[60 cảnh {index}/{len(rows)}] {row['eval_category']}", flush=True)
    summary["reference"]["sentences"] = sum(sentences(row["reference_vi"]) for row in rows)
    return results, summary, len(rows)


def run_game(engines: dict[str, _Engine]) -> tuple[list[dict], dict, int]:
    rows = [
        json.loads(line)
        for line in EVAL_GAME.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    results = []
    for index, row in enumerate(rows, start=1):
        source = clean_source(row["zh"])
        outputs = {}
        for name, engine in engines.items():
            raw = translate_block(engine, source)
            outputs[name] = score(source, raw, raw, row["reference_vi"])
            accumulate(summary[name], outputs[name])
        results.append({
            "set": "game_english",
            "eval_category": row["eval_category"],
            "source_clean": source,
            "reference_vi": row["reference_vi"],
            "outputs": outputs,
        })
        print(f"[game {index}/{len(rows)}]", flush=True)
    return results, summary, len(rows)


def self_check() -> None:
    item = score("甲乙 20", "tôi\n20", "ta 20", "ta 20")
    assert item["similarity"] == 1.0 and item["modern_pronouns"] == 0 and item["digits_match"]
    assert not score("甲 5", "x", "x 6", "x")["digits_match"]
    print("evaluate_hachimi_teacher_v2 OK")


def main() -> None:
    engines = {name: _Engine(str(path)) for name, path in MODELS.items()}
    ref_rows, ref_summary, ref_total = run_reference(engines)
    game_rows, game_summary, game_total = run_game(engines)
    results = ref_rows + game_rows
    OUTPUT_JSONL.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in results),
        encoding="utf-8",
    )
    lines = [
        "# Hachimi — so sánh các bản trên eval đã khóa",
        "",
        "> `similarity` chỉ là chỉ báo ký tự để hỗ trợ đọc tay, không thay cho đánh giá nghĩa.",
        "> Tập 60 cảnh chạy qua pipeline production (termguard + glossary approved); tập game",
        "> là raw model, không glossary.",
        "",
    ]
    lines += table("60 cảnh tham chiếu", ref_summary, ref_total, ref_summary["reference"]["sentences"])
    lines += table("Game tiếng Anh đã khóa", game_summary, game_total)
    for index, row in enumerate(results, start=1):
        lines.extend([
            f"## {index}. [{row['set']}] {row['eval_category']}",
            "",
            f"- ZH: {row['source_clean']}",
            f"- Tham chiếu: {row['reference_vi']}",
        ])
        for name in MODELS:
            item = row["outputs"][name]
            lines.append(
                f"- {name}: {item['pipeline']} "
                f"`sim={item['similarity']:.4f}; han={item['han']}; "
                f"modern={item['modern_pronouns']}; quote={item['quotes_balanced']}; "
                f"digits={item['digits_match']}`"
            )
        lines.append("")
    OUTPUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(table("60 cảnh tham chiếu", ref_summary, ref_total)))
    print("\n".join(table("Game tiếng Anh đã khóa", game_summary, game_total)))
    print(f"Đã ghi {OUTPUT_JSONL} và {OUTPUT_MD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    self_check() if args.self_check else main()
