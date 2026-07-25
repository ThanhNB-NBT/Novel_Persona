"""Tạo hàng đợi duyệt nguồn ZH-VI ngoài repo, không tạo replay hay train manifest."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from urllib.request import urlopen
from collections import Counter, defaultdict
from pathlib import Path


HAN = re.compile(r"[\u3400-\u9fff]")
LATIN = re.compile(r"[A-Za-zÀ-ỹ]")
BAD = re.compile(r"[\x00\ufffd]|(?:https?://|www\.)", re.I)
PLACEHOLDER = re.compile(r"(?:^|\s)(?:\*{2,}|\[\s*ads?\s*\])(?:\s|$)", re.I)
QUOTES = (("“", "”"), ("「", "」"), ("『", "』"))


def stable_id(dataset: str, book: str | None, zh: str, vi: str) -> str:
    value = "\0".join((dataset, book or "", zh, vi))
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:20]


def balanced_quotes(text: str) -> bool:
    return all(text.count(left) == text.count(right) for left, right in QUOTES) and text.count('"') % 2 == 0


def digits(text: str) -> list[str]:
    return re.findall(r"\d+(?:[.:/]\d+)*", text)


def group_split(book: str | None) -> str:
    if not book:
        return "unassigned_unknown_book"
    return "holdout" if int(hashlib.sha256(book.encode("utf-8")).hexdigest()[:8], 16) % 10 == 0 else "pilot"


def flags(zh: str, vi: str) -> list[str]:
    zh = zh.strip()
    vi = vi.strip()
    result: list[str] = []
    if len(zh) < 8 or len(zh) > 500:
        result.append("source_length")
    if len(vi) < 8 or len(vi) > 900:
        result.append("target_length")
    if not HAN.search(zh) or len(HAN.findall(zh)) / max(1, len(re.sub(r"\s", "", zh))) < 0.35:
        result.append("source_language")
    if HAN.search(vi) or len(LATIN.findall(vi)) < 4:
        result.append("target_language")
    if BAD.search(zh) or BAD.search(vi) or PLACEHOLDER.search(zh) or PLACEHOLDER.search(vi):
        result.append("artifact_or_ad")
    if not 0.35 <= len(vi) / max(1, len(zh)) <= 6.0:
        result.append("length_ratio")
    if not balanced_quotes(zh) or not balanced_quotes(vi):
        result.append("quote")
    if digits(zh) != digits(vi):
        result.append("digit")
    return result


def moa_rows(parquet: Path):
    import pyarrow.parquet as pq

    for batch in pq.ParquetFile(parquet).iter_batches(columns=["zh", "vi"], batch_size=8192):
        for zh, vi in zip(batch.column("zh").to_pylist(), batch.column("vi").to_pylist()):
            yield {"zh": str(zh or "").strip(), "vi": str(vi or "").strip(), "book": None, "chapter": None}


def orient_pair(left: object, right: object) -> tuple[str, str, str]:
    """Card Kaihe mô tả ZH→VI, nhưng stream hiện có mẫu VI→ZH; xác định theo chữ Hán."""
    left, right = str(left).strip(), str(right).strip()
    if len(HAN.findall(right)) > len(HAN.findall(left)):
        return right, left, "vi_zh_detected_reversed"
    return left, right, "zh_vi_as_declared"


def kaihe_rows(source: Path):
    """Đọc raw `parallel_sentences.jsonl`; không nhận train_data instruction/chapter."""
    for line in source.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        book = str(row.get("name") or "").strip() or None
        for index, pair in enumerate(row.get("sentences", [])):
            if not isinstance(pair, list) or len(pair) != 2:
                continue
            zh, vi, pair_order = orient_pair(pair[0], pair[1])
            yield {"zh": zh, "vi": vi, "book": book, "chapter": index, "pair_order": pair_order}


def kaihe_stream_rows(max_books: int, max_per_book: int):
    """Đọc một cửa sổ cố định từ raw pairs, không tải file 5,24 GB về máy."""
    url = "https://huggingface.co/datasets/kaihe/chinese_vietnamese_bilingual_wangwen/resolve/main/parallel_sentences.jsonl?download=true"
    with urlopen(url, timeout=60) as response:
        for book_index, raw_line in enumerate(response):
            if book_index >= max_books:
                break
            row = json.loads(raw_line.decode("utf-8"))
            book = str(row.get("name") or f"stream-book-{book_index}").strip()
            for index, pair in enumerate(row.get("sentences", [])[:max_per_book]):
                if isinstance(pair, list) and len(pair) == 2:
                    zh, vi, pair_order = orient_pair(pair[0], pair[1])
                    yield {"zh": zh, "vi": vi, "book": book, "chapter": index, "pair_order": pair_order}


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def build(dataset: str, rows, output: Path, limit: int, sample: int) -> dict[str, int]:
    output.mkdir(parents=True, exist_ok=True)
    source_targets: dict[str, set[str]] = defaultdict(set)
    raw = list(rows)
    for row in raw:
        if row["zh"] and row["vi"]:
            source_targets[row["zh"]].add(row["vi"])

    eligible, quarantine = [], []
    rejected = Counter()
    for row in raw:
        row_flags = flags(row["zh"], row["vi"])
        if len(source_targets[row["zh"]]) > 1:
            row_flags.append("source_target_conflict")
        record = {
            "id": stable_id(dataset, row["book"], row["zh"], row["vi"]),
            "zh": row["zh"], "vi": row["vi"],
            "provenance": {"dataset": dataset, "book": row["book"], "chapter": row["chapter"], "pair_order": row.get("pair_order", "zh_vi_declared"), "human_translation_verified": False},
            "group_split": group_split(row["book"]),
            "flags": sorted(set(row_flags)),
        }
        if row_flags:
            rejected.update(record["flags"])
            if len(quarantine) < limit:
                quarantine.append({**record, "status": "quarantine"})
        else:
            eligible.append(record)

    # Không dùng những cặp không có book làm eval/train split giả; MOA chỉ là review pool.
    eligible.sort(key=lambda row: row["id"])
    selected = [row for row in eligible if row["group_split"] != "holdout"][:limit]
    review = [{**row, "status": "needs_human_review"} for row in selected]
    write_jsonl(output / "review_pool.jsonl", review)
    write_jsonl(output / "quarantine_sample.jsonl", quarantine)
    (output / "accepted.jsonl").write_text("", encoding="utf-8")

    lines = [
        f"# Review sample: {dataset}",
        "",
        "Không phải gold và không phải replay. `accepted.jsonl` chỉ được điền sau duyệt người.",
        "",
        "| ZH | VI nguồn | provenance | cờ lỗi | quyết định người duyệt |",
        "|---|---|---|---|---|",
    ]
    for row in review[:sample]:
        provenance = row["provenance"]
        clean = lambda value: str(value).replace("|", "\\|").replace("\n", " ").strip()
        lines.append(
            f"| {clean(row['zh'])} | {clean(row['vi'])} | "
            f"id={row['id']}; dataset={provenance['dataset']}; book={clean(provenance['book'])}; "
            f"chapter={provenance['chapter']}; pair_order={provenance['pair_order']}; human_translation_verified=false | "
            f"{', '.join(row['flags']) or 'không có cờ cơ học'} | `accepted / quarantine` |"
        )
    (output / "review_sample.md").write_text("\n".join(lines), encoding="utf-8")
    (output / "report.json").write_text(json.dumps({"raw": len(raw), "eligible": len(eligible), "review_pool": len(review), "quarantine_sample": len(quarantine), "rejected": rejected}, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"raw": len(raw), "eligible": len(eligible), "review_pool": len(review), "quarantine_sample": len(quarantine)}


def self_check() -> None:
    assert not flags("他说今天是第8天。", "Hắn nói hôm nay là ngày thứ 8.")
    assert "digit" in flags("今天是第8章。", "Hôm nay là chương 9.")
    assert "quote" in flags("“他说的话还没说完。", "Lời hắn nói vẫn chưa dứt.")
    assert orient_pair("Bản Việt", "中文原文")[2] == "vi_zh_detected_reversed"
    assert group_split("book-a") == group_split("book-a")
    print("prepare_external_review_pilot OK")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", choices=("moa", "kaihe"))
    parser.add_argument("--source", type=Path)
    parser.add_argument("--hf-streaming", action="store_true", help="Chỉ áp dụng Kaihe raw parallel_sentences")
    parser.add_argument("--stream-books", type=int, default=40)
    parser.add_argument("--stream-per-book", type=int, default=100)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--limit", type=int, default=2000)
    parser.add_argument("--sample", type=int, default=200)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
        return
    if args.dataset is None or args.output is None:
        parser.error("cần --dataset và --output")
    if not args.hf_streaming and args.source is None:
        parser.error("cần --source, hoặc --hf-streaming cho Kaihe")
    if args.hf_streaming and args.dataset != "kaihe":
        parser.error("--hf-streaming chỉ hỗ trợ Kaihe")
    if args.dataset == "moa":
        summary = build("moa/Chinese-Vietnamese-literature", moa_rows(args.source), args.output, args.limit, args.sample)
    elif args.hf_streaming:
        summary = build(
            "kaihe/chinese_vietnamese_bilingual_wangwen",
            kaihe_stream_rows(args.stream_books, args.stream_per_book),
            args.output,
            args.limit,
            args.sample,
        )
    else:
        summary = build("kaihe/chinese_vietnamese_bilingual_wangwen", kaihe_rows(args.source), args.output, args.limit, args.sample)
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
