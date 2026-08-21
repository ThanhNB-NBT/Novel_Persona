"""Xoá term glossary KHÔNG có term_zh (neo chữ Hán) — chúng chỉ dùng để string-replace lên
mọi chương, đúng cơ chế đã biến 'em'→'muội' thành "xmuội". Termguard cưỡng chế theo term_zh
nên các term này không giúp gì lúc dịch.

    python clean_unanchored_glossary.py --dry-run   # chỉ in ra
    python clean_unanchored_glossary.py             # xoá thật (ghi backup JSON trước)
"""
from __future__ import annotations

import json
import sys
from datetime import datetime

from novelworker import db

DRY = "--dry-run" in sys.argv
sys.stdout.reconfigure(encoding="utf-8")  # console Windows mặc định cp1252, in tên Việt là vỡ


def main() -> None:
    rows: list[dict] = []
    frm = 0
    while True:
        batch = (db.sb().table("glossary_terms").select("*")
                 .is_("term_zh", "null").range(frm, frm + 499).execute()).data or []
        rows += batch
        if len(batch) < 500:
            break
        frm += 500
    print(f"term không có term_zh: {len(rows)}")
    for t in rows[:200]:
        print(f"  nv{t['novel_id']}: {t.get('wrong_vi')!r} -> {t.get('correct_vi')!r}")
    if DRY or not rows:
        return
    backup = f"glossary_unanchored_backup_{datetime.now():%Y%m%d_%H%M%S}.json"
    with open(backup, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=1)
    print(f"đã ghi backup {backup}")
    ids = [t["id"] for t in rows]
    for i in range(0, len(ids), 50):
        db.sb().table("glossary_terms").delete(returning="minimal").in_("id", ids[i:i + 50]).execute()
    left = (db.sb().table("glossary_terms").select("id", count="exact")
            .is_("term_zh", "null").execute()).count
    print(f"xoá xong. còn lại: {left}")


if __name__ == "__main__":
    main()
