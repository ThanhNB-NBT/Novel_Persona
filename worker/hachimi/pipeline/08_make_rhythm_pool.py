"""Gom ứng viên dạy NHỊP CÂU cho vòng train sau: dòng nguồn có chuỗi phẩy dài.

Đo ở experiments/hachimi_rhythm_research.md: model gói cùng lượng chữ vào một nửa số câu
so với tham chiếu vì 97% replay dịch 1:1 theo dấu câu tiếng Trung. Pool này lấy đúng loại
dòng cần tách câu để thầy viết lại; bản model hiện tại đi kèm làm mốc so sánh.

Chỉ đọc DB. Loại mọi chương nằm trong tập eval khóa.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from novelworker import db


DATA = Path(__file__).resolve().parents[1] / "data"
OUT = DATA / "source" / "rhythm_pool.jsonl"
EVAL_FILES = [
    DATA / "eval_locked" / "eval_reference_60.jsonl",
    DATA / "eval_locked" / "hachimi_vnext_e_fullchapters.jsonl",
]
EXISTING_ZH = [
    DATA / "gold" / "core_gold.jsonl",
    DATA / "gold" / "train_game_english_approved.jsonl",
    DATA / "gold" / "train_db_game_litrpg_approved.jsonl",
    DATA / "replay" / "general_candidate.jsonl",
]
HAN = re.compile(r"[一-鿿]")
CAP = next((int(arg) for arg in sys.argv[1:] if arg.isdigit()), 3600)
PER_NOVEL = 12


def locked_groups() -> set[tuple[int, int]]:
    groups = set()
    for path in EVAL_FILES:
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            if row.get("novel_id") is not None and row.get("chapter_index") is not None:
                groups.add((row["novel_id"], row["chapter_index"]))
    return groups


def known_sources() -> set[str]:
    known = set()
    for path in EXISTING_ZH:
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                known.add(json.loads(line).get("zh", ""))
    return known


def wanted(zh: str, vi: str) -> bool:
    """Dòng đáng sửa nhịp: chuỗi phẩy dài, đủ dài để có chỗ tách, bản model chưa tách."""
    if not HAN.search(zh) or HAN.search(vi):
        return False
    if not 80 <= len(zh) <= 400 or zh.count("，") + zh.count("、") < 3:
        return False
    if not 1.5 <= len(vi) / len(zh) <= 4.5:
        return False
    stops = zh.count("。") + zh.count("！") + zh.count("？") or 1
    sentences = len([part for part in re.split(r"(?<=[.!?…])\s+", vi) if part.strip()])
    return sentences / stops < 1.4


def main() -> None:
    locked, known = locked_groups(), known_sources()
    seen: set[str] = set()
    per_novel: dict[int, int] = {}
    rows: list[dict] = []
    start = 0
    chapters = 0
    while len(rows) < CAP:
        batch = (
            db.sb().table("chapters").select("novel_id,chapter_index,content_zh,content_vi")
            .eq("translation_status", "done").eq("model_used", "hachimi")
            .not_.is_("content_zh", "null").range(start, start + 199).execute().data or []
        )
        if not batch:
            break
        for chapter in batch:
            chapters += 1
            key = (chapter["novel_id"], chapter["chapter_index"])
            if key in locked or per_novel.get(chapter["novel_id"], 0) >= PER_NOVEL:
                continue
            zh_lines = [line.strip() for line in (chapter["content_zh"] or "").split("\n") if line.strip()]
            vi_lines = [line.strip() for line in (chapter["content_vi"] or "").split("\n") if line.strip()]
            if len(zh_lines) != len(vi_lines):
                continue  # khung lệch thì không căn dòng được
            for index, (zh, vi) in enumerate(zip(zh_lines, vi_lines)):
                if zh in seen or zh in known or not wanted(zh, vi):
                    continue
                seen.add(zh)
                per_novel[chapter["novel_id"]] = per_novel.get(chapter["novel_id"], 0) + 1
                rows.append({"zh": zh, "vi_model": vi, "novel_id": chapter["novel_id"],
                             "chapter_index": chapter["chapter_index"], "line_index": index})
                if len(rows) >= CAP or per_novel[chapter["novel_id"]] >= PER_NOVEL:
                    break
            if len(rows) >= CAP:
                break
        start += 200
    OUT.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
    print(f"Quét {chapters} chương → {len(rows)} ứng viên từ {len(per_novel)} truyện → {OUT}")


def self_check() -> None:
    chain = "甲，乙，丙，丁。" + "你好，" * 30
    assert wanted(chain, "Câu dài một mạch, " * 12)
    assert not wanted("甲。", "Ngắn.")  # thiếu chuỗi phẩy
    assert not wanted(chain, "Câu một. Câu hai. Câu ba. " * 8)  # đã tách rồi
    print("08_make_rhythm_pool OK")


if __name__ == "__main__":
    self_check() if "--self-check" in sys.argv else main()
