"""Dựng bộ test đa truyện từ dữ liệu THẬT: zh lấy R2/DB, bản Việt hiện tại làm mốc Hachimi."""
import json
from pathlib import Path
from novelworker import db, blob

NOVELS = [1256, 2163, 1380, 205, 778, 282, 356, 8466, 9806, 322, 1382, 17371]
PER = 3
OUT = Path(__file__).parent / "chapters_big.jsonl"

n = 0
with OUT.open("w", encoding="utf-8") as f:
    for nid in NOVELS:
        nv = (db.sb().table("novels").select("title_vi,genres").eq("id", nid)
              .single().execute()).data or {}
        rows = (db.sb().table("chapters")
                .select("id,chapter_index,title_zh,content_zh,content_vi")
                .eq("novel_id", nid).eq("translation_status", "done")
                .order("chapter_index", desc=False).limit(400).execute()).data or []
        # bỏ 20 chương đầu (glossary chưa đủ, xem early-chapters-name-drift), rải đều phần còn lại
        rows = [r for r in rows if r["chapter_index"] > 20] or rows
        step = max(1, len(rows) // PER)
        for ch in rows[::step][:PER]:
            zh = ch.get("content_zh") or blob.get_zh(ch["id"])
            if not zh or len(zh) < 800 or not ch.get("content_vi"):
                continue
            f.write(json.dumps({
                "novel_id": nid, "title_vi": nv.get("title_vi") or "",
                "genres": nv.get("genres") or [], "chapter_index": ch["chapter_index"],
                "chapter_title_zh": ch.get("title_zh") or "", "source_zh": zh,
                "hachimi_vi": ch["content_vi"]}, ensure_ascii=False) + "\n")
            n += 1
        print(f"nv{nid} {nv.get('title_vi','')[:24]:24s} lấy {min(PER, len(rows))}", flush=True)
print("TỔNG", n, "chương ->", OUT)
