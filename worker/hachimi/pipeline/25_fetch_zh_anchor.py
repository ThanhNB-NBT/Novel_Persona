"""Tải nguyên tác Trung cho các truyện có bản dịch TAY trong kho epub.

CỐ Ý KHÔNG đi qua hàng đợi production: `queue_sample_chapters` sẽ kéo theo dịch cả 2.200
chương (~13 giờ CPU box) và gọi LLM trích tên cho từng chương, trong khi ta chỉ cần vế
tiếng Trung. Ở đây gọi thẳng adapter, ghi ra file, không đụng DB.

Rải chậm 1 luồng: hai máy trong nhà chung một IP công cộng nên mọi request đều dồn vào
cùng một cửa — gặp SourceBlocked là bỏ truyện đó, đi tiếp, KHÔNG thử lại dồn dập.

    python -m pipeline.25_fetch_zh_anchor ids.json ra.jsonl [--chapters 10] [--delay 3]
"""
from __future__ import annotations

import argparse
import json
import random
import sys
import time
from pathlib import Path

# Chạy được cả từ worker/hachimi/ (dev) lẫn khi copy lẻ vào container (PYTHONPATH=/app).
_root = Path(__file__).resolve().parents
if len(_root) > 2:
    sys.path.insert(0, str(_root[2]))
from novelworker import db  # noqa: E402
from novelworker.crawler.base import (  # noqa: E402
    ChapterUnavailable, EmptyChapterList, SourceBlocked, SourceTransient)
from novelworker.crawler.registry import TEMPLATE_REGISTRY  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", type=Path, help="json: [{novel_id, epub, ...}]")
    ap.add_argument("out", type=Path)
    ap.add_argument("--chapters", type=int, default=10)
    ap.add_argument("--delay", type=float, default=3.0, help="giây nghỉ giữa 2 request")
    ap.add_argument("--limit-novels", type=int, default=0)
    args = ap.parse_args()

    want = json.loads(args.ids.read_text(encoding="utf-8"))
    ids = sorted({int(x["novel_id"] if isinstance(x, dict) else x) for x in want})
    if args.limit_novels:
        ids = ids[:args.limit_novels]

    done: set[tuple[int, int]] = set()
    if args.out.exists():
        for line in args.out.read_text(encoding="utf-8").splitlines():
            if line.strip():
                r = json.loads(line)
                done.add((r["novel_id"], r["chapter_index"]))
    # Dựng adapter cho MỌI nguồn, kể cả nguồn đang tắt: việc này chỉ đọc dữ liệu về làm data,
    # không phải bật nguồn cho crawler thường dùng lại. Bật/tắt trong bảng `sources` là quyết
    # định vận hành riêng — đừng đổi nó chỉ để lấy vài trăm chương.
    adapters, srcs = {}, {}
    for s_row in (db.sb().table("sources").select("*").execute().data or []):
        srcs[s_row["id"]] = s_row["name"]
        cls = TEMPLATE_REGISTRY.get(s_row.get("template") or "")
        if cls:
            adapters[s_row["name"]] = cls(base_url=s_row["base_url"],
                                          config=s_row.get("config") or {}, source_row=s_row)
    rows = (db.sb().table("novels").select("id,source_id,source_novel_id,title_zh")
            .in_("id", ids).execute()).data or []
    print(f"{len(rows)}/{len(ids)} truyện có bản ghi · đã có sẵn {len(done)} chương", flush=True)

    n_ok = n_skip = 0
    with args.out.open("a", encoding="utf-8") as fo:
        for i, nv in enumerate(rows, 1):
            name = srcs.get(nv["source_id"])
            ad = adapters.get(name)
            if not ad or not nv.get("source_novel_id"):
                n_skip += 1
                continue
            try:
                refs = ad.fetch_chapter_list(nv["source_novel_id"])[:args.chapters]
            except (SourceBlocked, SourceTransient, EmptyChapterList) as e:
                print(f"  [{i}/{len(rows)}] nv{nv['id']} {name}: bỏ ({type(e).__name__})", flush=True)
                n_skip += 1
                time.sleep(args.delay * 3)
                continue
            except Exception as e:
                print(f"  [{i}/{len(rows)}] nv{nv['id']} lỗi mục lục: {str(e)[:70]}", flush=True)
                n_skip += 1
                continue
            got = 0
            for ref in refs:
                idx = ref.index
                if (nv["id"], idx) in done:
                    continue
                time.sleep(args.delay * random.uniform(0.7, 1.4))
                try:
                    text = ad.fetch_chapter(ref.source_chapter_id)
                except (SourceBlocked, SourceTransient) as e:
                    print(f"  [{i}/{len(rows)}] nv{nv['id']} dừng giữa chừng ({type(e).__name__})",
                          flush=True)
                    time.sleep(args.delay * 5)
                    break
                except (ChapterUnavailable, Exception):
                    continue
                if not text or len(text) < 600:
                    continue
                fo.write(json.dumps({"novel_id": nv["id"], "chapter_index": idx,
                                     "title_zh": ref.title_zh, "zh": text},
                                    ensure_ascii=False) + "\n")
                fo.flush()
                got += 1
            n_ok += got
            print(f"  [{i}/{len(rows)}] nv{nv['id']} {name} · lấy {got} chương "
                  f"(tổng {n_ok})", flush=True)
    print(f"XONG · {n_ok} chương Trung · bỏ {n_skip} truyện → {args.out}")


if __name__ == "__main__":
    main()
