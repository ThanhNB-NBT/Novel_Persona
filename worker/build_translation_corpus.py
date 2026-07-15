"""Tạo corpus zh/vi cố định từ bản dịch DB; crawl thiếu chữ Trung nhưng không ghi DB.

Mặc định tạo 65 mẫu đã chốt cho đợt đánh giá 2026-07:
  python build_translation_corpus.py --fetch-missing
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
import time

from novelworker import db


DEFAULT_SPECS = ("1380:50:20", "293:1:15", "1223:1:15", "1281:1:15")


@dataclass(frozen=True)
class CorpusSpec:
    novel_id: int
    start: int
    count: int


def _parse_spec(raw: str) -> CorpusSpec:
    try:
        novel_id, start, count = (int(part) for part in raw.split(":"))
    except (TypeError, ValueError):
        raise argparse.ArgumentTypeError("định dạng phải là NOVEL_ID:CHƯƠNG_ĐẦU:SỐ_LƯỢNG")
    if novel_id <= 0 or start <= 0 or count <= 0:
        raise argparse.ArgumentTypeError("mọi giá trị trong spec phải lớn hơn 0")
    return CorpusSpec(novel_id, start, count)


def _local_zh(path: Path) -> str | None:
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    try:
        payload = text.split("--- GỐC (zh) ---\n", 1)[1]
        return payload.split("\n\n--- DỊCH (vi) ---\n", 1)[0].strip() or None
    except IndexError:
        return None


def _adapter_for(source_id: int, adapters: dict):
    return next((adapter for adapter in adapters.values()
                 if adapter.source_row.get("id") == source_id), None)


def build_corpus(specs: list[CorpusSpec], outdir: Path, fetch_missing: bool,
                 delay: float) -> dict:
    outdir.mkdir(parents=True, exist_ok=True)
    adapters = None
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "specs": [spec.__dict__ for spec in specs],
        "samples": 0,
        "content_zh": {"database": 0, "source": 0, "local": 0},
        "novels": [],
        "failures": [],
    }

    for spec in specs:
        novel = (db.sb().table("novels")
                 .select("id,title_vi,title_zh,genres,source_id")
                 .eq("id", spec.novel_id).single().execute().data or {})
        rows = (db.sb().table("chapters")
                .select("chapter_index,title_zh,source_chapter_id,content_zh,content_vi,model_used")
                .eq("novel_id", spec.novel_id)
                .gte("chapter_index", spec.start)
                .lt("chapter_index", spec.start + spec.count)
                .eq("translation_status", "done")
                .not_.is_("content_vi", "null")
                .order("chapter_index").execute().data or [])
        found = {row["chapter_index"] for row in rows}
        expected = set(range(spec.start, spec.start + spec.count))
        for missing in sorted(expected - found):
            manifest["failures"].append(
                {"novel_id": spec.novel_id, "chapter_index": missing,
                 "error": "không có bản dịch done trong DB"})

        written = 0
        for row in rows:
            chapter_index = row["chapter_index"]
            path = outdir / f"n{spec.novel_id}_c{chapter_index}.txt"
            zh = row.get("content_zh")
            origin = "database"
            if not zh:
                zh = _local_zh(path)
                origin = "local"
            if not zh and fetch_missing:
                if adapters is None:
                    from novelworker.main import build_adapters
                    adapters = build_adapters()
                adapter = _adapter_for(novel.get("source_id"), adapters)
                if not adapter:
                    manifest["failures"].append(
                        {"novel_id": spec.novel_id, "chapter_index": chapter_index,
                         "error": f"không có adapter cho source {novel.get('source_id')}"})
                    continue
                try:
                    zh = adapter.fetch_chapter(row["source_chapter_id"])
                    origin = "source"
                    if delay:
                        time.sleep(delay)
                except Exception as exc:
                    manifest["failures"].append(
                        {"novel_id": spec.novel_id, "chapter_index": chapter_index,
                         "error": str(exc)[:300]})
                    continue
            if not zh:
                manifest["failures"].append(
                    {"novel_id": spec.novel_id, "chapter_index": chapter_index,
                     "error": "thiếu content_zh; chạy lại với --fetch-missing"})
                continue

            title = novel.get("title_vi") or novel.get("title_zh") or "?"
            tag = (f"novel {spec.novel_id} ch.{chapter_index} ({title}) "
                   f"[{row.get('model_used') or '(db)'}]")
            path.write_text(
                f"=== {tag}\n=== thể loại: {', '.join(novel.get('genres') or [])}\n\n"
                f"--- GỐC (zh) ---\n{zh.strip()}\n\n"
                f"--- DỊCH (vi) ---\n{row['content_vi'].strip()}\n",
                encoding="utf-8")
            manifest["content_zh"][origin] += 1
            manifest["samples"] += 1
            written += 1
            print(f"[{manifest['samples']:02d}] n{spec.novel_id} c{chapter_index}: {origin}")
        manifest["novels"].append({
            "novel_id": spec.novel_id,
            "title": novel.get("title_vi") or novel.get("title_zh"),
            "requested": spec.count,
            "written": written,
        })

    (outdir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--novel", action="append", type=_parse_spec,
                        help="NOVEL_ID:CHƯƠNG_ĐẦU:SỐ_LƯỢNG; lặp lại để thêm truyện")
    parser.add_argument("--out", type=Path, default=Path("corpus_translation"))
    parser.add_argument("--fetch-missing", action="store_true",
                        help="crawl content_zh còn thiếu và chỉ lưu vào corpus local")
    parser.add_argument("--delay", type=float, default=1.2,
                        help="số giây nghỉ sau mỗi chương crawl (mặc định 1.2)")
    args = parser.parse_args()
    specs = args.novel or [_parse_spec(raw) for raw in DEFAULT_SPECS]
    manifest = build_corpus(specs, args.out, args.fetch_missing, max(args.delay, 0))
    print(json.dumps({"samples": manifest["samples"],
                      "content_zh": manifest["content_zh"],
                      "failures": len(manifest["failures"])}, ensure_ascii=False))
    if manifest["failures"] or manifest["samples"] != sum(s.count for s in specs):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
