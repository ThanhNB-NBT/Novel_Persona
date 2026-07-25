"""Cùng một model, chọn trong n-best thay vì luôn lấy giả thuyết xác suất cao nhất.

Beam search đang chạy beam=4, tức CT2 đã tính sẵn 4 giả thuyết rồi vứt 3. Thí nghiệm này
lấy cả 4 và chọn bằng chính các cổng chất lượng của dự án (xưng hô, Hán sót, số, ngoặc
kép, nhịp câu) — không đổi model, không đổi prompt, gần như không tốn thêm thời gian.
"""
from __future__ import annotations

import argparse
import json
import time
from collections import defaultdict
from pathlib import Path

from novelworker.translator.hachimi_engine import _Engine
from novelworker.translator.text_clean import clean_source

from audit_hachimi_base_longform import metrics, pipeline
from eval_common import EVAL, MODELS_DIR, balanced_quotes, production_terms, similarity
from evaluate_hachimi_teacher_v2 import sentences


VARIANTS = {  # tên: (beam, nbest)
    "beam4_nbest1": (4, 1),
    "beam4_nbest4": (4, 4),
    "beam6_nbest6": (6, 6),
    "beam8_nbest8": (8, 8),
}
MODEL_DIR = MODELS_DIR / "hachimi-teacher-v4"
OUTPUT_MD = Path(__file__).with_name("hachimi_nbest_eval.md")


def main(limit: int) -> None:
    rows = [json.loads(line) for line in EVAL.read_text(encoding="utf-8").splitlines() if line.strip()][:limit]
    terms = {novel_id: production_terms(novel_id) for novel_id in {row["novel_id"] for row in rows}}
    engines = {name: _Engine(str(MODEL_DIR), nbest=nbest, beam=beam) for name, (beam, nbest) in VARIANTS.items()}
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    detail = []
    for index, row in enumerate(rows, start=1):
        source = clean_source(row["zh"])
        outputs = {}
        for name, engine in engines.items():
            started = time.perf_counter()
            _, vi = pipeline(engine, source, terms[row["novel_id"]])
            counts = metrics(source, vi, vi)
            outputs[name] = vi
            summary[name]["similarity"] += similarity(row["reference_vi"], vi)
            summary[name]["sentences"] += sentences(vi)
            summary[name]["han"] += counts["pipeline_han"]
            summary[name]["modern_pronouns"] += counts["pipeline_modern_pronouns"]
            summary[name]["quote_fail"] += not balanced_quotes(vi)
            summary[name]["seconds"] += time.perf_counter() - started
        detail.append({**row, "source_clean": source, "outputs": outputs})
        print(f"[{index}/{len(rows)}] {row['eval_category']}", flush=True)
    lines = [
        f"# Chọn trong n-best — {len(rows)} cảnh khoá, model teacher_v4",
        "",
        "| Biến thể | Similarity TB | Câu/cảnh | Hán sót | Đại từ hiện đại | Quote lỗi | Giây/cảnh |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for name in VARIANTS:
        item = summary[name]
        lines.append(
            f"| `{name}` | {item['similarity'] / len(rows):.4f} | {item['sentences'] / len(rows):.1f} | "
            f"{int(item['han'])} | {int(item['modern_pronouns'])} | {int(item['quote_fail'])} | "
            f"{item['seconds'] / len(rows):.2f} |"
        )
    first, last = list(VARIANTS)[0], list(VARIANTS)[-1]
    changed = [row for row in detail if row["outputs"][first] != row["outputs"][last]]
    lines += ["", f"Số cảnh `{last}` chọn khác `{first}`: **{len(changed)}/{len(rows)}**", ""]
    for row in changed[:10]:
        lines += [f"## {row['eval_category']}", "", f"- ZH: {row['source_clean'][:300]}"]
        lines += [f"- {name}: {row['outputs'][name][:300]}" for name in VARIANTS]
        lines.append("")
    OUTPUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines[:8]))
    print(f"Đã ghi {OUTPUT_MD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=60)
    main(parser.parse_args().limit)
