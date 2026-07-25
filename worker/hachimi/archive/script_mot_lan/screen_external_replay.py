"""Lọc ngữ nghĩa replay ngoài repo bằng chính Hachimi gốc.

Similarity chỉ dùng để loại cặp lệch rõ, không biến dữ liệu ngoài thành gold.
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
from difflib import SequenceMatcher
from pathlib import Path

from novelworker.translator.hachimi_engine import _Engine


def similarity(left: str, right: str) -> float:
    normalize = lambda text: re.sub(r"\s+", "", text).lower()
    return SequenceMatcher(None, normalize(left), normalize(right)).ratio()


def self_check() -> None:
    assert similarity("Ta đi.", "Ta đi!") >= 0.8
    assert similarity("abcdef", "uvwxyz") == 0
    print("screen_external_replay OK")


def main(
    source: Path,
    output: Path,
    report: Path,
    model_dir: Path,
    scan_limit: int,
    keep_limit: int,
    minimum: float,
) -> None:
    rows = [
        json.loads(line)
        for _, line in zip(range(scan_limit), source.open(encoding="utf-8"))
        if line.strip()
    ]
    engine = _Engine(str(model_dir))
    translated: list[str] = []
    for start in range(0, len(rows), 128):
        translated.extend(engine.translate_lines([row["zh"] for row in rows[start:start + 128]]))
        print(f"[{min(start + 128, len(rows))}/{len(rows)}]", flush=True)
    scored = [
        (similarity(row["vi"], model_vi), row, model_vi)
        for row, model_vi in zip(rows, translated)
    ]
    eligible = [item for item in scored if item[0] >= minimum]
    eligible.sort(key=lambda item: item[0], reverse=True)
    selected = eligible[:keep_limit]

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        "".join(
            json.dumps(
                {
                    **row,
                    "base_similarity": round(score, 4),
                    "screen": "hachimi_base_similarity",
                },
                ensure_ascii=False,
            )
            + "\n"
            for score, row, _ in selected
        ),
        encoding="utf-8",
    )
    scores = [score for score, _, _ in scored]
    lines = [
        "# Sàng lọc replay văn học bằng Hachimi gốc",
        "",
        "> Đây chỉ là replay cho pilot. Similarity cao giúp giảm cặp lệch hàng,",
        "> không chứng minh bản dịch đúng hoặc đủ để gọi là gold.",
        "",
        f"- Đã dịch kiểm tra: **{len(rows):,}** cặp.",
        f"- Similarity trung bình: **{statistics.mean(scores):.4f}**.",
        f"- Trung vị: **{statistics.median(scores):.4f}**.",
        f"- Qua ngưỡng `{minimum}`: **{len(eligible):,}**.",
        f"- Giữ cho pilot: **{len(selected):,}**.",
        "",
        "## Mẫu sát ngưỡng",
        "",
    ]
    for score, row, model_vi in sorted(selected, key=lambda item: item[0])[:10]:
        lines += [
            f"### Similarity {score:.4f}",
            f"- ZH: {row['zh']}",
            f"- VI nguồn ngoài: {row['vi']}",
            f"- Hachimi gốc: {model_vi}",
            "",
        ]
    report.write_text("\n".join(lines), encoding="utf-8")
    print(f"scanned={len(rows)} eligible={len(eligible)} selected={len(selected)}")
    print(report)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--model-dir", type=Path)
    parser.add_argument("--scan-limit", type=int, default=5_000)
    parser.add_argument("--keep-limit", type=int, default=2_000)
    parser.add_argument("--minimum", type=float, default=0.6)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
    elif not all((args.source, args.output, args.report, args.model_dir)):
        parser.error("cần --source, --output, --report và --model-dir")
    else:
        main(
            args.source,
            args.output,
            args.report,
            args.model_dir,
            args.scan_limit,
            args.keep_limit,
            args.minimum,
        )
