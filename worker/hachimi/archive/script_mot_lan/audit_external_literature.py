"""Kiểm toán corpus văn học Trung–Việt ngoài repo và tạo replay candidate.

Không tự nhập vào manifest train. Cần đọc báo cáo và duyệt provenance trước khi dùng.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path


HAN = re.compile(r"[\u3400-\u9fff]")
MODERN_REGISTER = re.compile(
    r"\b(?:tôi|anh|em|cậu|bạn|mình|anh ấy|cô ấy|cậu ấy)\b",
    re.IGNORECASE,
)
BAD_TEXT = re.compile(r"[\x00\ufffd]")
QUOTE_PAIRS = (("“", "”"), ("「", "」"), ("『", "』"))


def balanced_quotes(text: str) -> bool:
    return (
        all(text.count(left) == text.count(right) for left, right in QUOTE_PAIRS)
        and text.count('"') % 2 == 0
    )


def digits(text: str) -> list[str]:
    return re.findall(r"\d+(?:[.:/]\d+)*", text)


def self_check() -> None:
    assert balanced_quotes("“Ta đi.”")
    assert not balanced_quotes("“Ta đi.")
    assert digits("8:00 đến 10/12") == ["8:00", "10/12"]
    assert MODERN_REGISTER.search("Tôi sẽ đi.")
    assert not MODERN_REGISTER.search("Hắn xem thanh kiếm.")
    print("audit_external_literature OK")


def main(parquet_path: Path, output: Path, report: Path, limit: int) -> None:
    import pyarrow.parquet as pq
    import sentencepiece as spm

    tokenizer = spm.SentencePieceProcessor(
        model_file=str(Path(__file__).parents[1] / "models" / "hachimi-base-download" / "source.spm")
    )
    parquet = pq.ParquetFile(parquet_path)
    vi_by_zh: dict[str, str] = {}
    conflicts: set[str] = set()
    pair_counts: Counter[tuple[str, str]] = Counter()
    totals = Counter()

    for batch in parquet.iter_batches(columns=["zh", "vi"], batch_size=8192):
        for zh_raw, vi_raw in zip(batch.column("zh").to_pylist(), batch.column("vi").to_pylist()):
            zh = str(zh_raw or "").strip()
            vi = str(vi_raw or "").strip()
            totals["rows"] += 1
            if not zh or not vi:
                totals["empty"] += 1
                continue
            pair_counts[(zh, vi)] += 1
            previous = vi_by_zh.get(zh)
            if previous is not None and previous != vi:
                conflicts.add(zh)
            else:
                vi_by_zh[zh] = vi

    candidates: list[tuple[bytes, str, str]] = []
    rejected = Counter()
    examples: dict[str, list[str]] = {}

    def reject(reason: str, zh: str, vi: str) -> None:
        rejected[reason] += 1
        bucket = examples.setdefault(reason, [])
        if len(bucket) < 3:
            bucket.append(f"{zh[:90]} → {vi[:120]}")

    for zh, vi in vi_by_zh.items():
        if zh in conflicts:
            reject("same_zh_conflict", zh, vi)
        elif not HAN.search(zh):
            reject("source_without_han", zh, vi)
        elif HAN.search(vi):
            reject("target_han_leak", zh, vi)
        elif BAD_TEXT.search(zh) or BAD_TEXT.search(vi):
            reject("replacement_or_null", zh, vi)
        elif not 8 <= len(zh) <= 500:
            reject("source_length", zh, vi)
        elif not 0.8 <= len(vi) / len(zh) <= 6.0:
            reject("length_ratio", zh, vi)
        elif len(tokenizer.encode(zh)) > 448:
            reject("source_over_448_tokens", zh, vi)
        elif not balanced_quotes(zh) or not balanced_quotes(vi):
            reject("unbalanced_quotes", zh, vi)
        elif digits(zh) != digits(vi):
            reject("digit_mismatch", zh, vi)
        elif MODERN_REGISTER.search(vi):
            reject("modern_register", zh, vi)
        else:
            digest = hashlib.sha256((zh + "\0" + vi).encode("utf-8")).digest()
            candidates.append((digest, zh, vi))

    candidates.sort(key=lambda item: item[0])
    selected = candidates[:limit]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        "".join(
            json.dumps(
                {
                    "zh": zh,
                    "vi": vi,
                    "status": "external_replay_candidate",
                    "source_dataset": "moa/Chinese-Vietnamese-literature",
                    "license": "CC-BY-SA-4.0",
                },
                ensure_ascii=False,
            )
            + "\n"
            for _, zh, vi in selected
        ),
        encoding="utf-8",
    )

    duplicate_rows = sum(count - 1 for count in pair_counts.values() if count > 1)
    lines = [
        "# Audit `moa/Chinese-Vietnamese-literature`",
        "",
        "> Đây là replay candidate, không phải gold người duyệt và chưa được nhập vào train.",
        "",
        "## Tổng quan",
        "",
        f"- Dòng gốc: **{totals['rows']:,}**.",
        f"- Cặp duy nhất: **{len(pair_counts):,}**; dòng trùng hoàn toàn dư: **{duplicate_rows:,}**.",
        f"- Nguồn Trung xung đột nhiều bản Việt: **{len(conflicts):,}**.",
        f"- Qua gate tự động: **{len(candidates):,}**.",
        f"- Lấy mẫu hash ổn định làm candidate: **{len(selected):,}**.",
        "",
        "## Loại bởi gate",
        "",
        "| Lý do | Số dòng |",
        "|---|---:|",
    ]
    lines.extend(f"| `{reason}` | {count:,} |" for reason, count in rejected.most_common())
    lines += ["", "## Mẫu bị loại", ""]
    for reason, rows in examples.items():
        lines.append(f"### `{reason}`")
        lines.extend(f"- {row}" for row in rows)
        lines.append("")
    lines += [
        "## Quyết định",
        "",
        "- Không gọi tập này là gold: không có metadata người dịch/tác phẩm ở cấp dòng.",
        "- Chỉ cân nhắc làm replay văn học sau khi đọc tay một mẫu cân bằng và kiểm tra điều khoản",
        "  ShareAlike đối với model phát hành.",
        "- Không dùng các dòng bị loại để sửa bằng heuristic rồi đưa trở lại.",
        "",
    ]
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text("\n".join(lines), encoding="utf-8")
    print(f"rows={totals['rows']} eligible={len(candidates)} selected={len(selected)}")
    print(report)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--parquet", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--limit", type=int, default=50_000)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
    elif not all((args.parquet, args.output, args.report)):
        parser.error("cần --parquet, --output và --report")
    else:
        main(args.parquet, args.output, args.report, args.limit)
