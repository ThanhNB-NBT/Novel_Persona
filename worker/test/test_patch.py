"""Lõi job 'vá': lọc term hợp lệ + xếp cụm dài trước + thay chuỗi (sai→đúng, Hán→chuẩn)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker import db
from novelworker.translator.worker import _patch_replacements


def test_patch_replacements_filter_order_apply():
    terms = [
        {"wrong_vi": "Hoan Yêu", "correct_vi": "Huyễn Yêu"},  # bản dịch Việt sai
        {"term_zh": "幻妖", "correct_vi": "Huyễn Yêu"},        # chữ Hán còn sót
        {"wrong_vi": "", "correct_vi": "bỏ"},                 # rỗng vế trái → loại
        {"wrong_vi": "abc"},                                  # thiếu vế phải → loại
    ]
    repls = _patch_replacements(terms)
    keys = [w for w, _, _ in repls]
    assert keys == sorted(keys, key=lambda k: -len(k))        # cụm dài thay trước
    assert set(keys) == {"Hoan Yêu", "幻妖"}                   # loại rỗng/thiếu vế

    # vá y như handle_patch: áp lần lượt từng cặp lên nội dung chương
    text = "Con Hoan Yêu và 幻妖 khác"
    for w, c, by_word in repls:
        text = db.replace_word(text, w, c) if by_word else text.replace(w, c)
    assert text == "Con Huyễn Yêu và Huyễn Yêu khác"


def test_patch_khong_an_vao_giua_tu():
    """Cặp Việt→Việt phải theo ranh giới từ: 'em'→'muội' KHÔNG được biến "xem" thành "xmuội"."""
    repls = _patch_replacements([{"wrong_vi": "em", "correct_vi": "muội"}])
    text = "Hắn xem em gái đem đồ."
    for w, c, by_word in repls:
        text = db.replace_word(text, w, c) if by_word else text.replace(w, c)
    assert text == "Hắn xem muội gái đem đồ."


def test_early_retranslate_chi_kich_hoat_o_chuong_ngay_sau_vung_trich(monkeypatch):
    """Chương khác gate+1 thì không được đụng DB (mỗi truyện chỉ tốn 1 query trong cả đời)."""
    from novelworker.config import settings
    from novelworker.translator.worker import _retranslate_early_chapters_once

    touched = []
    monkeypatch.setattr(db, "sb", lambda: touched.append(1))
    gate = settings.hachimi_extract_max_chapter
    for idx in (1, gate, gate + 2, gate + 50):
        _retranslate_early_chapters_once(1, idx)
    assert not touched
