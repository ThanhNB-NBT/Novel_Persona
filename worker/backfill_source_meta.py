"""Một lần: điền lại metadata nguồn cho truyện ĐÃ có trong DB (thể loại, số chữ, chỉ số nguồn).

Vì sao cần: adapter ddxs trước đây không lấy thể loại (nguồn không có nhãn 类别, chỉ có
breadcrumb) → 5251/7140 truyện ddxs nằm trong kho mà trống thể loại, trong khi luật lọc thể
loại lại dựa đúng vào trường đó. Cùng lúc, faloo/ptwxz/69shuba còn công bố số chữ và vài chỉ
số mà crawler cũ bỏ qua.

    python backfill_source_meta.py --dry-run              # chỉ đếm, không ghi
    python backfill_source_meta.py --source ddxs          # chạy một nguồn
    python backfill_source_meta.py --limit 200            # giới hạn số truyện mỗi nguồn

CHỈ ĐIỀN, KHÔNG ẨN: script này không đụng cột `hidden` — lọc thể loại là quyết định riêng,
chạy sau khi đã nhìn dữ liệu thật.
"""
from __future__ import annotations

import sys
import time

sys.stdout.reconfigure(encoding="utf-8")

from novelworker import db
from novelworker.main import build_adapters

DRY = "--dry-run" in sys.argv
ONLY = None
LIMIT = None
if "--source" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--source") + 1]
if "--limit" in sys.argv:
    LIMIT = int(sys.argv[sys.argv.index("--limit") + 1])


def novels_of(source_id: int) -> list[dict]:
    """Truyện của nguồn còn THIẾU thứ gì đó lấy được: thể loại, số chữ, chỉ số."""
    rows: list[dict] = []
    frm = 0
    while True:
        b = (db.sb().table("novels")
             .select("id, source_novel_id, title_zh, genres, word_count, source_stats")
             .eq("source_id", source_id).range(frm, frm + 499).execute()).data or []
        rows += b
        if len(b) < 500:
            break
        frm += 500
    return [n for n in rows
            if not n.get("genres") or n.get("word_count") is None
            or n.get("source_stats") is None]


def main() -> None:
    for name, adapter in build_adapters().items():
        if ONLY and name != ONLY:
            continue
        sid = (db.sb().table("sources").select("id").eq("name", name)
               .single().execute()).data["id"]
        todo = novels_of(sid)
        if LIMIT:
            todo = todo[:LIMIT]
        print(f"\n=== {name}: {len(todo)} truyện cần điền", flush=True)
        if DRY:
            continue
        filled = failed = 0
        for i, nv in enumerate(todo, 1):
            try:
                meta = adapter.fetch_novel_meta(nv["source_novel_id"])
            except Exception as e:  # nguồn đổi khuôn / truyện bị gỡ → bỏ qua, không dừng cả mẻ
                failed += 1
                if failed <= 5:
                    print(f"  lỗi {nv['id']} {nv['source_novel_id']}: "
                          f"{type(e).__name__} {str(e)[:90]}", flush=True)
                continue
            patch: dict = {}
            if meta.genres_zh and not nv.get("genres"):
                patch["genres"] = meta.genres_zh
            if meta.word_count and nv.get("word_count") is None:
                patch["word_count"] = meta.word_count
            if meta.stats and nv.get("source_stats") is None:
                patch["source_stats"] = meta.stats
            if patch:
                db.sb().table("novels").update(patch, returning="minimal").eq(
                    "id", nv["id"]).execute()
                filled += 1
            if i % 50 == 0:
                print(f"  …{i}/{len(todo)} · điền {filled} · lỗi {failed}", flush=True)
            time.sleep(0.3)  # lịch sự với nguồn; adapter còn tự throttle bên trong
        print(f"  XONG {name}: điền {filled}, lỗi {failed}", flush=True)


if __name__ == "__main__":
    main()
