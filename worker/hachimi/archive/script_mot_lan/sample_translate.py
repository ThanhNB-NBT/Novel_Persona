"""Dịch thử vài chương thật bằng engine Hachimi (đúng đường production, trừ trích tên LLM).

Chỉ đọc Supabase, không ghi DB. Chạy từ worker/:
    PYTHONIOENCODING=utf-8 PYTHONPATH=. HACHIMI_MODEL_DIR=models/hachimi-ct2 \
      ../.venv/Scripts/python.exe experiments/sample_translate.py --novels 3 --chapters 2
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

from novelworker import db
from novelworker.translator import hachimi_engine, termguard, hanviet
from novelworker.translator.text_clean import clean_source
from novelworker.translator.worker import (
    _clean_output, _hanviet_fallback, _fix_register, _fix_soft_style, HAN_CHARS,
    TITLE_CHAPTER_PREFIX,
)


def _terms(novel_id: int) -> list[dict]:
    return db.get_glossary(novel_id)[0]


def _render(zh: str, terms: list[dict]) -> str:
    text = termguard.translate_text(clean_source(zh), terms, hachimi_engine.translate_text)
    text = _clean_output(text)
    text, _ = _hanviet_fallback(text)
    return _fix_register(_fix_soft_style(text))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--novels", type=int, default=3)
    p.add_argument("--chapters", type=int, default=2)
    p.add_argument("--output", type=Path, default=Path("experiments/sample_translation.md"))
    args = p.parse_args()

    # Truyện có glossary riêng (term-bearing) để thấy rõ cưỡng chế tên riêng.
    gid = (db.sb().table("glossary_terms").select("novel_id").eq("approved", True)
           .not_.is_("novel_id", "null").order("novel_id").limit(4000).execute().data or [])
    seen: list[int] = []
    for row in gid:
        if row["novel_id"] not in seen:
            seen.append(row["novel_id"])
    novels = (db.sb().table("novels").select("id,title_vi,title_zh,engine")
              .in_("id", seen[:60]).execute().data or [])

    out: list[str] = ["# Dịch thử Hachimi (model mới)\n"]
    picked = 0
    for nv in novels:
        chapters = (db.sb().table("chapters")
                    .select("id,chapter_index,title_zh,content_zh")
                    .eq("novel_id", nv["id"]).not_.is_("content_zh", "null")
                    .order("chapter_index").limit(args.chapters).execute().data or [])
        if len(chapters) < args.chapters:
            continue
        terms = _terms(nv["id"])
        out.append(f"\n---\n\n## Truyện {nv['id']} — {nv.get('title_vi') or nv.get('title_zh')}")
        out.append(f"*glossary: {len(terms)} term*\n")
        for ch in chapters:
            t0 = time.perf_counter()
            body = _render(ch["content_zh"], terms)
            title_vi = None
            tz = TITLE_CHAPTER_PREFIX.sub("", (ch.get("title_zh") or "").strip())
            if tz:
                title_vi = termguard.translate_text(
                    clean_source(tz), terms, hachimi_engine.translate_text
                ).strip()
                if title_vi and HAN_CHARS.search(title_vi):
                    title_vi = hanviet.han_viet(tz) or title_vi
            dt = time.perf_counter() - t0
            out.append(f"\n### Chương {ch['chapter_index']}: {title_vi or '(không tiêu đề)'}")
            out.append(f"<sub>gốc: {tz} · {len(ch['content_zh'])} ký tự · {dt:.1f}s</sub>\n")
            # Dòng trắng giữa các đoạn để markdown xuống đoạn (app tách theo \n nên vẫn đúng).
            out.append("\n\n".join(p for p in body.split("\n") if p.strip()))
        picked += 1
        if picked >= args.novels:
            break

    args.output.write_text("\n".join(out), encoding="utf-8")
    print(f"Đã ghi {args.output} ({picked} truyện)")


if __name__ == "__main__":
    main()
