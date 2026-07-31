"""Dựng bộ test đa truyện cho `eval_register.py` — nguồn zh lấy từ R2 (chương done).

Bộ test là DATA nên KHÔNG commit (theo quy ước hachimi/**/*.jsonl bị gitignore, giống
eval_locked). Giữ SCRIPT này để tái tạo bộ test bất cứ lúc nào:

    python build_testset_from_r2.py            # -> eval/testset_multi.jsonl

Chọn 7 truyện đa thể loại (tiên hiệp / tận thế / huyền huyễn / game), mỗi truyện ~25 chương
rải đều. Chỉ số eval đều ref-free (so output với nguồn) nên không cần bản dịch mẫu.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[2] / ".env")
from novelworker import blob  # noqa: E402

U = os.environ["SUPABASE_URL"]; K = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
# tiên hiệp, tận thế/vô hạn lưu, huyền huyễn ×3, game, phản phái — phủ thể loại
NOVELS = [1256, 1380, 205, 778, 282, 356, 2163]
PER_NOVEL = 25
OUT = Path(__file__).resolve().parent / "testset_multi.jsonl"


def _get(path: str, params: dict) -> list[dict]:
    q = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{U}/rest/v1/{path}?{q}",
                                 headers={"apikey": K, "Authorization": "Bearer " + K})
    return json.load(urllib.request.urlopen(req))


def main() -> None:
    n_ch = n_miss = 0
    with OUT.open("w", encoding="utf-8") as f:
        for nid in NOVELS:
            rows = _get("chapters", {"select": "id,chapter_index", "novel_id": f"eq.{nid}",
                                     "translation_status": "eq.done", "order": "chapter_index",
                                     "limit": "400"})
            if not rows:
                continue
            step = max(1, len(rows) // PER_NOVEL)
            for ch in rows[::step][:PER_NOVEL]:
                zh = blob.get_zh(ch["id"])
                if not zh:
                    n_miss += 1
                    continue
                f.write(json.dumps({"novel_id": nid, "chapter_index": ch["chapter_index"],
                                    "zh_lines": zh.split("\n")}, ensure_ascii=False) + "\n")
                n_ch += 1
            print(f"  novel {nid}: {len(rows)} done", flush=True)
    print(f"→ {OUT} — {n_ch} chương ({n_miss} thiếu trên R2)")


if __name__ == "__main__":
    main()
