"""Dịch liên tục nhiều thể loại bằng Hachimi gốc để xác định nhu cầu finetune.

Chỉ đọc DB, không sửa chapter/glossary. Kết quả được ghi tăng dần để có thể chạy tiếp
nếu tiến trình bị ngắt.
"""
from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path

from novelworker import db
from novelworker.translator import termguard
from novelworker.translator.hachimi_engine import _Engine
from novelworker.translator.text_clean import clean_source
from novelworker.translator.worker import (
    _clean_output,
    _fix_register,
    _fix_soft_style,
    _hanviet_fallback,
)


# Corpus longform đã cắt xong (hachimi_base_longform.jsonl) nên main() hiếm khi chạy lại;
# bản base đã xoá sau khi chốt v4 → trỏ vào model đang chạy production nếu cần dựng lại.
MODEL_DIR = str(Path(__file__).resolve().parents[2] / "models" / "hachimi-ct2")
OUTPUT_JSONL = Path(__file__).with_name("hachimi_base_longform.jsonl")
OUTPUT_MD = Path(__file__).with_name("hachimi_base_longform.md")
CASES = [
    ("Tiên hiệp", 1256),
    ("Huyền huyễn dị giới", 32),
    ("Hệ thống, vô hạn", 1380),
    ("Game huyền huyễn", 282),
    ("Khoa huyễn", 322),
    ("Võng du, hệ thống", 1382),
    ("Xuyên không", 992),
    ("Huyền huyễn học viện", 205),
    ("Tiên hiệp chính kịch", 409),
    ("Hệ thống, vô hạn cổ", 24),
    ("Huyền huyễn, ngôn tình", 356),
    ("Kiếm đạo", 293),
    ("Lãnh chúa, hệ thống", 1320),
    ("Ngự thú", 1306),
    ("Tiên hiệp dị bản", 3978),
]
HAN = re.compile(r"[\u3400-\u9fff]")
MODERN = re.compile(r"(?i)(?<!\w)(tôi|bạn|cậu|cháu|mình)(?!\w)")
PADDING = re.compile(r"(?i)(?<!\w)(nhé|nha|đấy)(?!\w)")


def translate_block(engine: _Engine, text: str) -> str:
    lines = text.split("\n")
    indexes = [index for index, line in enumerate(lines) if clean_source(line)]
    cleaned = [clean_source(lines[index]) for index in indexes]
    translated = engine.translate_lines(cleaned)
    out = list(lines)
    for index, value in zip(indexes, translated):
        out[index] = value
    return "\n".join(out)


def pipeline(engine: _Engine, source: str, terms: list[dict]) -> tuple[str, str]:
    raw = translate_block(engine, source)

    def cached_translate(text: str) -> str:
        return raw if text == source else translate_block(engine, text)

    restored = termguard.translate_text(source, terms, cached_translate)
    restored = _clean_output(restored)
    restored, _ = _hanviet_fallback(restored)
    restored = _fix_register(_fix_soft_style(restored))
    return raw, restored


def metrics(source: str, raw: str, restored: str) -> dict:
    return {
        "source_chars": len(source),
        "raw_chars": len(raw),
        "pipeline_chars": len(restored),
        "raw_han": len(HAN.findall(raw)),
        "pipeline_han": len(HAN.findall(restored)),
        "raw_modern_pronouns": len(MODERN.findall(raw)),
        "pipeline_modern_pronouns": len(MODERN.findall(restored)),
        "raw_padding": len(PADDING.findall(raw)),
        "pipeline_padding": len(PADDING.findall(restored)),
        "source_lines": len(source.splitlines()),
        "raw_lines": len(raw.splitlines()),
        "pipeline_lines": len(restored.splitlines()),
    }


def load_done() -> tuple[list[dict], set[tuple[int, int]]]:
    rows: list[dict] = []
    if OUTPUT_JSONL.exists():
        for line in OUTPUT_JSONL.read_text(encoding="utf-8").splitlines():
            if line.strip():
                rows.append(json.loads(line))
    return rows, {(row["novel_id"], row["chapter_index"]) for row in rows}


def render(rows: list[dict]) -> None:
    out = [
        "# Hachimi gốc — kiểm toán bản dịch liên tục theo thể loại",
        "",
        "Model: `ngocdang83/HachimiMT-60-zh-vi`, bản CT2 INT8 local.",
        "",
        "`Raw` chỉ qua làm sạch nguồn và model. `Pipeline` chạy thêm glossary/termguard "
        "và hậu xử lý production. Cả hai đều không gọi LLM.",
        "",
    ]
    for row in sorted(rows, key=lambda item: (item["case_order"], item["chapter_index"])):
        out.extend([
            f"## {row['genre']} — {row['title_vi']} — chương {row['chapter_index']}",
            "",
            f"- Novel ID: {row['novel_id']}",
            f"- Thời gian: {row['seconds']:.1f}s",
            f"- Metrics: `{json.dumps(row['metrics'], ensure_ascii=False)}`",
            "",
            "### Nguồn Trung",
            "",
            row["source_zh"],
            "",
            "### Raw Hachimi gốc",
            "",
            row["raw_vi"],
            "",
            "### Qua pipeline production",
            "",
            row["pipeline_vi"],
            "",
        ])
    OUTPUT_MD.write_text("\n".join(out), encoding="utf-8")


def self_check() -> None:
    sample = metrics("甲\n乙", "tôi\nA", "ta\nA")
    assert sample["source_lines"] == sample["raw_lines"] == 2
    assert sample["raw_modern_pronouns"] == 1
    assert sample["pipeline_modern_pronouns"] == 0
    print("audit_hachimi_base_longform OK")


def main(chapter_count: int) -> None:
    rows, done = load_done()
    engine = _Engine(MODEL_DIR)
    for case_order, (genre, novel_id) in enumerate(CASES):
        novel = (
            db.sb().table("novels").select("title_zh,title_vi,genres")
            .eq("id", novel_id).single().execute().data
        )
        chapters = (
            db.sb().table("chapters")
            .select("chapter_index,title_zh,content_zh")
            .eq("novel_id", novel_id)
            .not_.is_("content_zh", "null")
            .order("chapter_index")
            .limit(chapter_count)
            .execute().data or []
        )
        if len(chapters) < chapter_count:
            raise RuntimeError(
                f"Truyện {novel_id} chỉ có {len(chapters)}/{chapter_count} chương nguồn"
            )
        terms, _ = db.get_glossary(novel_id)
        for chapter in chapters:
            key = (novel_id, chapter["chapter_index"])
            if key in done:
                continue
            source = clean_source(chapter["content_zh"])
            started = time.perf_counter()
            raw, restored = pipeline(engine, source, terms)
            row = {
                "case_order": case_order,
                "genre": genre,
                "novel_id": novel_id,
                "title_zh": novel["title_zh"],
                "title_vi": novel.get("title_vi") or novel["title_zh"],
                "genres": novel.get("genres") or [],
                "chapter_index": chapter["chapter_index"],
                "chapter_title_zh": chapter.get("title_zh"),
                "seconds": time.perf_counter() - started,
                "metrics": metrics(source, raw, restored),
                "source_zh": source,
                "raw_vi": raw,
                "pipeline_vi": restored,
            }
            with OUTPUT_JSONL.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
            rows.append(row)
            done.add(key)
            render(rows)
            print(
                f"[{len(done)}/{len(CASES) * chapter_count}] "
                f"{genre} / {novel_id} / chương {chapter['chapter_index']}: "
                f"{row['seconds']:.1f}s",
                flush=True,
            )
    render(rows)
    print(f"Đã ghi {OUTPUT_JSONL} và {OUTPUT_MD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--chapters", type=int, default=10)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
    else:
        main(args.chapters)
