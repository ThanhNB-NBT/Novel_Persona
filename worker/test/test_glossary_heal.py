import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker import db
from novelworker.db import heal_glossary_terms


def main() -> None:
    # Ca gốc (bug thật 2026-07-08): gợi ý LLM 幻妖→"Hoan Yêu", user sửa qua form
    # "Hoan Yêu"→"Huyễn Yêu" (không term_zh) → gợi ý phải được lành hoá.
    sug = {"id": 1, "novel_id": 9, "term_zh": "幻妖", "correct_vi": "Hoan Yêu", "wrong_vi": None}
    fix = {"id": 2, "novel_id": 9, "term_zh": None, "correct_vi": "Huyễn Yêu", "wrong_vi": "Hoan Yêu"}
    changed = heal_glossary_terms([sug, fix])
    assert sug["correct_vi"] == "Huyễn Yêu"
    assert sug["wrong_vi"] == "Hoan Yêu"       # bản cũ giữ lại cho patch + prompt "KHÔNG dịch thành"
    assert fix["correct_vi"] == "Huyễn Yêu"    # term sửa không tự ăn chính nó
    assert changed == [sug]

    # Tên là cụm con: "Hoan Yêu Vương" cũng phải lành theo, wrong_vi có sẵn thì giữ
    boss = {"id": 3, "novel_id": 9, "term_zh": "幻妖王", "correct_vi": "Hoan Yêu Vương",
            "wrong_vi": "Hoạn Yêu Vương"}
    heal_glossary_terms([boss, dict(fix)])
    assert boss["correct_vi"] == "Huyễn Yêu Vương"
    assert boss["wrong_vi"] == "Hoạn Yêu Vương"

    # Không có cặp sửa nào → không đổi gì
    only = {"id": 4, "novel_id": 9, "term_zh": "林松", "correct_vi": "Lâm Tùng", "wrong_vi": None}
    assert heal_glossary_terms([only]) == []
    assert only["correct_vi"] == "Lâm Tùng"

    # Cặp thoái hoá wrong==correct không được gây vòng lặp/đổi bậy
    weird = {"id": 5, "novel_id": 9, "term_zh": None, "correct_vi": "Như Nhau", "wrong_vi": "Như Nhau"}
    other = {"id": 6, "novel_id": 9, "term_zh": "某", "correct_vi": "Như Nhau X", "wrong_vi": None}
    assert heal_glossary_terms([weird, other]) == []

    # Chỉ patch conflict_vi của row cũ; correct_vi/approved không có trong payload update.
    updates = []
    filters = []

    class Query:
        def update(self, value):
            updates.append(value)
            return self

        def eq(self, *args):
            filters.append(("eq", *args))
            return self

        def is_(self, *args):
            filters.append(("is_", *args))
            return self

        def neq(self, *args):
            filters.append(("neq", *args))
            return self

        def execute(self):
            return self

    old_sb = db.sb
    try:
        db.sb = lambda: type("SB", (), {"table": lambda *_: Query()})()
        db.record_glossary_conflicts(7, [{"term_zh": "林松", "candidate_vi": "Lâm Tồng",
                                         "conflict_vi": "Lâm Tồng (c105)"}])
    finally:
        db.sb = old_sb
    assert updates == [{"conflict_vi": "Lâm Tồng (c105)"}]
    assert filters == [("eq", "novel_id", 7), ("eq", "term_zh", "林松"),
                       ("is_", "conflict_vi", "null"), ("neq", "correct_vi", "Lâm Tồng")]

    print("test_glossary_heal OK")


if __name__ == "__main__":
    main()
