"""So sánh hai bản Hachimi trên các chương dài liên tục, đọc như đọc truyện.

Nguồn chương lấy từ corpus longform đã cắt sẵn (không phụ thuộc `chapters.content_zh` —
kho production xoá nguồn sau khi dịch). Glossary dùng ĐÚNG bộ của production, gồm cả term
gợi ý chưa duyệt; đo bằng term approved-only sẽ thổi phồng lỗi tên riêng.
"""
from __future__ import annotations

import argparse
import json
import re
import time
from collections import defaultdict
from pathlib import Path

from novelworker.translator.hachimi_engine import _Engine

from audit_hachimi_base_longform import metrics, pipeline
from eval_common import MODELS_DIR, balanced_quotes, production_terms


CORPUS = Path(__file__).with_name("hachimi_base_longform.jsonl")
OUTPUT_JSONL = Path(__file__).with_name("hachimi_fullchapters_eval.jsonl")
OUTPUT_MD = Path(__file__).with_name("hachimi_fullchapters_eval.md")
# Mặc định: giữ 32 (ca tên riêng loạn) + 293 (đã duyệt, làm mốc) + bốn truyện võng du/hệ thống.
NOVELS = (32, 293, 282, 1382, 1380, 1320)
CHAPTERS_PER_NOVEL = 2
MODELS = {
    "current": MODELS_DIR / "hachimi-ct2",
    "teacher_v4": MODELS_DIR / "hachimi-teacher-v4",
}


def bad_quote_paragraphs(text: str) -> int:
    return sum(bool(paragraph.strip()) and not balanced_quotes(paragraph) for paragraph in text.splitlines())


def digits_match(source: str, output: str) -> bool:
    return re.findall(r"\d+", source) == re.findall(r"\d+", output)


def chapter_rows() -> list[dict]:
    corpus = [json.loads(line) for line in CORPUS.read_text(encoding="utf-8").splitlines() if line.strip()]
    by_novel: dict[int, list[dict]] = defaultdict(list)
    for row in corpus:
        by_novel[row["novel_id"]].append(row)
    rows = []
    for novel_id in NOVELS:
        chapters = sorted(by_novel[novel_id], key=lambda row: row["chapter_index"])[:CHAPTERS_PER_NOVEL]
        if len(chapters) != CHAPTERS_PER_NOVEL:
            raise RuntimeError(f"Corpus thiếu chương cho truyện {novel_id}: {len(chapters)}")
        for chapter in chapters:
            rows.append({
                "novel_id": novel_id,
                "genre": chapter["genre"],
                "title_vi": chapter["title_vi"],
                "chapter_index": chapter["chapter_index"],
                "chapter_title_zh": chapter.get("chapter_title_zh"),
                "source_zh": chapter["source_zh"],
            })
    return rows


def blocks(text: str) -> str:
    """Mỗi dòng nguồn là một đoạn văn — markdown cần dòng trắng giữa chúng mới xuống dòng."""
    return "\n\n".join(line.strip() for line in text.split("\n") if line.strip())


def anchor(row: dict) -> str:
    slug = f"{row['title_vi']} — chương {row['chapter_index']}".lower()
    return re.sub(r"[^\w\s-]", "", slug).strip().replace(" ", "-")


def render(rows: list[dict]) -> None:
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    for row in rows:
        for name, output in row["outputs"].items():
            for key in ("modern_pronouns", "han", "padding", "bad_quote_paragraphs", "digit_fail", "sentences"):
                summary[name][key] += output[key]
            summary[name]["seconds"] += output["seconds"]
    lines = [
        f"# Hachimi — {len(rows)} chương dài liên tục",
        "",
        "> Glossary dùng đúng bộ production (gồm term gợi ý chưa duyệt), pipeline termguard/hậu xử lý",
        "> y như worker. Nguồn chương lấy từ corpus longform, không đọc `chapters.content_zh`.",
        "",
        "| Model | Đại từ hiện đại | Hán sót | Đệm | Đoạn quote lệch | Số lỗi | Câu/chương | Thời gian |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in MODELS:
        item = summary[name]
        lines.append(
            f"| `{name}` | {int(item['modern_pronouns'])} | {int(item['han'])} | {int(item['padding'])} | "
            f"{int(item['bad_quote_paragraphs'])} | {int(item['digit_fail'])} | "
            f"{item['sentences'] / max(1, len(rows)):.0f} | {item['seconds']:.1f}s |"
        )
    lines.extend(["", "## Theo thể loại", "",
                  "| Thể loại | Model | Đại từ hiện đại | Đoạn quote lệch | Số lỗi | Câu/chương |",
                  "|---|---|---:|---:|---:|---:|"])
    by_genre: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        by_genre[row.get("genre", "?")].append(row)
    for genre, group in sorted(by_genre.items()):
        for name in MODELS:
            get = lambda key: sum(row["outputs"][name][key] for row in group)
            lines.append(
                f"| {genre} | `{name}` | {get('modern_pronouns')} | {get('bad_quote_paragraphs')} | "
                f"{get('digit_fail')} | {get('sentences') / len(group):.0f} |"
            )
    lines.extend(["", "## Mục lục", ""])
    lines += [f"- [{row['title_vi']} — chương {row['chapter_index']}](#{anchor(row)})" for row in rows]
    for row in rows:
        lines.extend([
            "",
            "---",
            "",
            f"## {row['title_vi']} — chương {row['chapter_index']}",
            "",
            f"Truyện {row['novel_id']} · {row.get('chapter_title_zh') or ''}".strip(" ·"),
        ])
        for name in MODELS:
            output = row["outputs"][name]
            flags = ", ".join(
                f"{label} {output[key]}" for key, label in (
                    ("modern_pronouns", "đại từ hiện đại"), ("han", "Hán sót"),
                    ("padding", "đệm"), ("bad_quote_paragraphs", "đoạn quote lệch"),
                    ("sentences", "câu"))
            )
            lines.extend(["", f"### Bản {name}", "", f"*{flags} · {output['seconds']}s*", "",
                          blocks(output["pipeline_vi"])])
        lines.extend(["", "<details>", "<summary>Nguồn Trung</summary>", "",
                      blocks(row["source_zh"]), "", "</details>"])
    OUTPUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


def self_check() -> None:
    assert bad_quote_paragraphs('"Được."\n“Ổn.”') == 0
    assert bad_quote_paragraphs('"Hỏng.\n“Ổn.”') == 1
    assert digits_match("A12", "B12")
    assert not digits_match("A12", "B21")
    print("evaluate_hachimi_vnext_e_fullchapters OK")


def main() -> None:
    rows = chapter_rows()
    saved = {}
    if OUTPUT_JSONL.exists():
        for line in OUTPUT_JSONL.read_text(encoding="utf-8").splitlines():
            if line.strip():
                row = json.loads(line)
                saved[(row["novel_id"], row["chapter_index"])] = row
    terms = {novel_id: production_terms(novel_id) for novel_id in NOVELS}
    print("Glossary production: " + ", ".join(f"truyện {nid}: {len(t)} term" for nid, t in terms.items()), flush=True)
    engines = {name: _Engine(str(path)) for name, path in MODELS.items()}
    for index, row in enumerate(rows, start=1):
        previous = saved.get((row["novel_id"], row["chapter_index"]))
        if previous and previous.get("source_zh") == row["source_zh"] and set(previous.get("outputs", {})) == set(MODELS):
            row["outputs"] = previous["outputs"]
            print(f"[{index}/{len(rows)}] dùng lại truyện {row['novel_id']} / chương {row['chapter_index']}", flush=True)
            continue
        outputs = {}
        for name, engine in engines.items():
            started = time.perf_counter()
            raw, restored = pipeline(engine, row["source_zh"], terms[row["novel_id"]])
            count = metrics(row["source_zh"], raw, restored)
            outputs[name] = {
                "pipeline_vi": restored,
                "modern_pronouns": count["pipeline_modern_pronouns"],
                "han": count["pipeline_han"],
                "padding": count["pipeline_padding"],
                "bad_quote_paragraphs": bad_quote_paragraphs(restored),
                "digits_match": digits_match(row["source_zh"], restored),
                "digit_fail": int(not digits_match(row["source_zh"], restored)),
                "sentences": len([part for part in re.split(r"(?<=[.!?…])\s+", restored) if part.strip()]),
                "seconds": round(time.perf_counter() - started, 2),
            }
        row["outputs"] = outputs
        OUTPUT_JSONL.write_text("".join(json.dumps(item, ensure_ascii=False) + "\n" for item in rows[:index]), encoding="utf-8")
        render(rows[:index])
        print(f"[{index}/{len(rows)}] truyện {row['novel_id']} / chương {row['chapter_index']}", flush=True)
    render(rows)
    print(f"Đã ghi {OUTPUT_JSONL} và {OUTPUT_MD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    self_check() if args.self_check else main()

