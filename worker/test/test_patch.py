"""Lõi job 'vá': lọc term hợp lệ + xếp cụm dài trước + thay chuỗi (sai→đúng, Hán→chuẩn)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.translator.worker import _patch_replacements


def test_patch_replacements_filter_order_apply():
    terms = [
        {"wrong_vi": "Hoan Yêu", "correct_vi": "Huyễn Yêu"},  # bản dịch Việt sai
        {"term_zh": "幻妖", "correct_vi": "Huyễn Yêu"},        # chữ Hán còn sót
        {"wrong_vi": "", "correct_vi": "bỏ"},                 # rỗng vế trái → loại
        {"wrong_vi": "abc"},                                  # thiếu vế phải → loại
    ]
    repls = _patch_replacements(terms)
    keys = [w for w, _ in repls]
    assert keys == sorted(keys, key=lambda k: -len(k))        # cụm dài thay trước
    assert set(keys) == {"Hoan Yêu", "幻妖"}                   # loại rỗng/thiếu vế

    # vá y như handle_patch: áp lần lượt từng cặp lên nội dung chương
    text = "Con Hoan Yêu và 幻妖 khác"
    for w, c in repls:
        text = text.replace(w, c)
    assert text == "Con Huyễn Yêu và Huyễn Yêu khác"
