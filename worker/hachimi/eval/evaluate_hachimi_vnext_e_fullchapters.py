"""So sánh current, v-next D và E trên sáu chương DB cùng nguồn, chỉ đọc DB."""
from __future__ import annotations

import argparse
import json
import re
import time
from collections import defaultdict
from pathlib import Path

from novelworker import db
from novelworker.translator.hachimi_engine import _Engine
from novelworker.translator.text_clean import clean_source

from audit_hachimi_base_longform import metrics, pipeline
from eval_common import MODELS_DIR, balanced_quotes, load_terms


OUTPUT_JSONL = Path(__file__).with_name("hachimi_fullchapters_eval.jsonl")
OUTPUT_MD = Path(__file__).with_name("hachimi_fullchapters_eval.md")
NOVELS = (32, 282, 293)
MODELS = {
    "current": MODELS_DIR / "hachimi-ct2",
    "teacher_v2": MODELS_DIR / "hachimi-teacher-v2",
}


def bad_quote_paragraphs(text: str) -> int:
    return sum(bool(paragraph.strip()) and not balanced_quotes(paragraph) for paragraph in text.splitlines())


def digits_match(source: str, output: str) -> bool:
    return re.findall(r"\d+", source) == re.findall(r"\d+", output)


def chapter_rows() -> list[dict]:
    rows = []
    for novel_id in NOVELS:
        novel = db.sb().table("novels").select("title_zh,title_vi").eq("id", novel_id).single().execute().data
        chapters = (
            db.sb().table("chapters").select("chapter_index,title_zh,content_zh")
            .eq("novel_id", novel_id).not_.is_("content_zh", "null")
            .order("chapter_index").limit(2).execute().data or []
        )
        if len(chapters) != 2:
            raise RuntimeError(f"Truyện {novel_id} không đủ 2 chương nguồn: {len(chapters)}")
        for chapter in chapters:
            rows.append({
                "novel_id": novel_id,
                "title_zh": novel["title_zh"],
                "title_vi": novel.get("title_vi") or novel["title_zh"],
                "chapter_index": chapter["chapter_index"],
                "chapter_title_zh": chapter.get("title_zh"),
                "source_zh": clean_source(chapter["content_zh"]),
            })
    return rows


def render(rows: list[dict]) -> None:
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    for row in rows:
        for name, output in row["outputs"].items():
            for key in ("modern_pronouns", "han", "padding", "bad_quote_paragraphs", "digit_fail"):
                summary[name][key] += output[key]
            summary[name]["seconds"] += output["seconds"]
    lines = [
        "# Hachimi v-next E — sáu chương dài cùng nguồn",
        "",
        "> Chỉ đọc DB. Mỗi model chạy cùng pipeline termguard/hậu xử lý; glossary chỉ lấy term đã duyệt.",
        "",
        "| Model | Đại từ hiện đại | Hán sót | Đệm | Đoạn quote lệch | Số lỗi | Thời gian |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for name in MODELS:
        item = summary[name]
        lines.append(f"| `{name}` | {int(item['modern_pronouns'])} | {int(item['han'])} | {int(item['padding'])} | {int(item['bad_quote_paragraphs'])} | {int(item['digit_fail'])} | {item['seconds']:.1f}s |")
    if len(rows) == 6:
        e = summary["e_strict_replay"]
        lines.extend([
            "",
            "## Cổng sáu chương của E",
            "",
            f"- Đại từ hiện đại ≤ 39: **{'đạt' if e['modern_pronouns'] <= 39 else 'không đạt'}** ({int(e['modern_pronouns'])}).",
            f"- Đoạn quote lệch ≤ 4: **{'đạt' if e['bad_quote_paragraphs'] <= 4 else 'không đạt'}** ({int(e['bad_quote_paragraphs'])}).",
            f"- Hán sót ≤ 21: **{'đạt' if e['han'] <= 21 else 'không đạt'}** ({int(e['han'])}).",
            f"- Số lỗi là phép so khớp chuỗi số nghiêm: {int(e['digit_fail'])}/6 chương; cần đọc tay vì có thể là số chương được model thêm hoặc tách khoảng trắng.",
        ])
    for row in rows:
        lines.extend(["", f"## Truyện {row['novel_id']} — {row['title_vi']} — chương {row['chapter_index']}", "", "### Nguồn Trung", "", row["source_zh"]])
        for name in MODELS:
            output = row["outputs"][name]
            lines.extend(["", f"### {name}", "", f"`{json.dumps({key: output[key] for key in ('modern_pronouns', 'han', 'padding', 'bad_quote_paragraphs', 'digits_match', 'seconds')}, ensure_ascii=False)}`", "", output["pipeline_vi"]])
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
    terms = {novel_id: load_terms(novel_id) for novel_id in NOVELS}
    engines = {name: _Engine(str(path)) for name, path in MODELS.items()}
    for index, row in enumerate(rows, start=1):
        previous = saved.get((row["novel_id"], row["chapter_index"]))
        if previous and previous.get("source_zh") == row["source_zh"] and set(previous.get("outputs", {})) == set(MODELS):
            row["outputs"] = previous["outputs"]
            print(f"[{index}/6] dùng lại truyện {row['novel_id']} / chương {row['chapter_index']}", flush=True)
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
                "seconds": round(time.perf_counter() - started, 2),
            }
        row["outputs"] = outputs
        OUTPUT_JSONL.write_text("".join(json.dumps(item, ensure_ascii=False) + "\n" for item in rows[:index]), encoding="utf-8")
        render(rows[:index])
        print(f"[{index}/6] truyện {row['novel_id']} / chương {row['chapter_index']}", flush=True)
    render(rows)
    print(f"Đã ghi {OUTPUT_JSONL} và {OUTPUT_MD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    self_check() if args.self_check else main()
