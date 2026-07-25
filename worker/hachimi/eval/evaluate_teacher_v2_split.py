"""Đo lại lệch đơn vị train–inference cho ứng viên teacher-v2 trên 60 cảnh khóa.

Vòng A/B (24/07) kết luận engine chia nguồn ở 90 token trong khi gold train ở cảnh dài
là lệch đơn vị. teacher-v2 là ứng viên đầu tiên vượt current về similarity nên đo lại
xem nới đơn vị dịch có còn kèm hồi quy quote/xưng hô như hồi đó không.
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

from novelworker.translator.text_clean import clean_source

from audit_hachimi_base_longform import metrics, pipeline
from evaluate_hachimi_split_strategies import CURRENT, StrategyEngine
from eval_common import EVAL, MODELS_DIR, balanced_quotes, load_terms, similarity


V2 = MODELS_DIR / "hachimi-teacher-v2"
OUTPUT_MD = Path(__file__).with_name("hachimi_teacher_v2_split_eval.md")


def main() -> None:
    rows = [json.loads(line) for line in EVAL.read_text(encoding="utf-8").splitlines() if line.strip()]
    strategies = {
        "current_split90": StrategyEngine(CURRENT, "current"),
        "v2_split90": StrategyEngine(V2, "current"),
        "v2_packed160": StrategyEngine(V2, "packed160"),
        "v2_direct448out448": StrategyEngine(V2, "direct448out448"),
    }
    terms = {novel_id: load_terms(novel_id) for novel_id in {row["novel_id"] for row in rows}}
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    detail = []
    for index, row in enumerate(rows, start=1):
        source = clean_source(row["zh"])
        outputs = {}
        for name, engine in strategies.items():
            raw, restored = pipeline(engine, source, terms[row["novel_id"]])
            counts = metrics(source, raw, restored)
            outputs[name] = restored
            summary[name]["similarity"] += similarity(row["reference_vi"], restored)
            summary[name]["han"] += counts["pipeline_han"]
            summary[name]["modern_pronouns"] += counts["pipeline_modern_pronouns"]
            summary[name]["quote_fail"] += not balanced_quotes(restored)
            # Nhịp câu: tham chiếu ngắt thành nhiều câu, model hay giữ một chuỗi phẩy dài.
            summary[name]["sentences"] += restored.count(".") + restored.count("!") + restored.count("?")
        summary["reference"]["sentences"] += (
            row["reference_vi"].count(".") + row["reference_vi"].count("!") + row["reference_vi"].count("?")
        )
        detail.append({**row, "source_clean": source, "outputs": outputs})
        print(f"[{index}/{len(rows)}] {row['eval_category']}", flush=True)

    lines = [
        "# teacher-v2 — chiến lược chia nguồn trên 60 cảnh khóa",
        "",
        "| Chiến lược | Similarity TB | Hán sót | Đại từ hiện đại | Quote lỗi | Câu/cảnh |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for name in strategies:
        item = summary[name]
        lines.append(
            f"| `{name}` | {item['similarity'] / len(rows):.4f} | {int(item['han'])} | "
            f"{int(item['modern_pronouns'])} | {int(item['quote_fail'])} | "
            f"{item['sentences'] / len(rows):.1f} |"
        )
    lines.append(f"| `tham chiếu` | — | — | — | — | {summary['reference']['sentences'] / len(rows):.1f} |")
    for index, row in enumerate(detail, start=1):
        lines.extend(["", f"## {index}. {row['eval_category']} — novel {row['novel_id']}", "",
                      f"- ZH: {row['source_clean']}", f"- Tham chiếu: {row['reference_vi']}"])
        lines += [f"- {name}: {row['outputs'][name]}" for name in strategies]
    OUTPUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines[:9]))
    print(f"Đã ghi {OUTPUT_MD}")


if __name__ == "__main__":
    main()
