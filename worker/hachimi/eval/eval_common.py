"""Tiện ích dùng chung cho mọi harness đánh giá Hachimi.

Trước đây nằm rải trong `evaluate_hachimi_vnext_ab.py` (so ứng viên A–E, các model đó đã
bị loại và xoá). Giữ lại đúng phần còn dùng: đường dẫn eval khoá, chỉ báo similarity,
kiểm ngoặc kép và đọc glossary approved.
"""
from __future__ import annotations

import re
from difflib import SequenceMatcher
from pathlib import Path


HUB = Path(__file__).resolve().parents[1]
WORKER = Path(__file__).resolve().parents[2]
MODELS_DIR = WORKER / "models"
EVAL = HUB / "data" / "eval_locked" / "eval_reference_60.jsonl"
EVAL_GAME = HUB / "data" / "eval_locked" / "eval_game_english_locked.jsonl"
EVAL_CHAPTERS = HUB / "data" / "eval_locked" / "hachimi_vnext_e_fullchapters.jsonl"
QUOTE_PAIRS = (("“", "”"), ("「", "」"), ("『", "』"))


def similarity(reference: str, output: str) -> float:
    normalize = lambda text: re.sub(r"\s+", "", text).lower()
    return SequenceMatcher(None, normalize(reference), normalize(output), autojunk=False).ratio()


def balanced_quotes(text: str) -> bool:
    return (
        text.count('"') % 2 == 0
        and all(text.count(left) == text.count(right) for left, right in QUOTE_PAIRS)
    )


def load_terms(novel_id: int) -> list[dict]:
    """Chỉ đọc term đã duyệt; không gọi get_glossary vì hàm đó có thể lành hóa và ghi DB."""
    from novelworker import db  # import muộn: similarity/balanced_quotes phải chạy được khi không có supabase

    return (
        db.sb().table("glossary_terms")
        .select("term_zh,correct_vi,wrong_vi,term_type,approved")
        .eq("approved", True)
        .or_(f"novel_id.eq.{novel_id},novel_id.is.null")
        .execute().data
        or []
    )


def production_terms(novel_id: int) -> list[dict]:
    """Đúng bộ term production dùng: term đã duyệt + term GỢI Ý (approved=false) của truyện.

    `db.get_glossary` còn ghi lại DB ở bước lành hoá, nên ở đây chép lại phần chọn lọc và
    lành hoá trong bộ nhớ. Đo bằng `load_terms` (chỉ approved) sẽ thổi phồng lỗi tên riêng
    vì termguard không có gì để cưỡng chế.
    """
    from novelworker import db
    from novelworker.db import _is_safe_pending_term, heal_glossary_terms
    from novelworker.translator import hanviet

    columns = ("id,novel_id,term_zh,wrong_vi,correct_vi,term_type,note,narrator_term,"
               "approved,first_chapter,hit_count,conflict_vi")
    terms = (
        db.sb().table("glossary_terms").select(columns)
        .eq("approved", True).or_(f"novel_id.eq.{novel_id},novel_id.is.null")
        .execute().data or []
    )
    seen = {term["term_zh"] for term in terms if term.get("term_zh")}
    pending = (
        db.sb().table("glossary_terms").select(columns)
        .eq("approved", False).eq("novel_id", novel_id)
        .order("hit_count", desc=True).order("created_at")
        .execute().data or []
    )
    for term in pending:
        zh = term.get("term_zh")
        if zh and zh not in seen and _is_safe_pending_term(term, hanviet.han_viet(zh)):
            seen.add(zh)
            terms.append(term)
    heal_glossary_terms(terms)  # sửa in-place, không ghi DB
    return terms


def self_check() -> None:
    assert similarity("Ta đi.", "Ta đi!") >= 0.8
    assert balanced_quotes("“Được.”") and balanced_quotes('"Được."')
    assert not balanced_quotes("“Hỏng.") and not balanced_quotes('"Hỏng.')
    assert EVAL.is_file() and EVAL_GAME.is_file() and EVAL_CHAPTERS.is_file()
    print("eval_common OK")


if __name__ == "__main__":
    self_check()
