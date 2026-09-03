"""Xuất chương chưa dịch ra lô `in_XXX.jsonl` cho Gemini chạy tay, và gom `out_XXX.jsonl` về.

Vì sao vẫn dùng đường Gemini chạy tay: đo 02/09, cổng trả tiền hoặc đắt gấp 9 (DeepSeek pro
chính hãng ~254.000₫ cho 930 chương) hoặc nghẽn 503 hàng loạt. Gemini free thì chậm nhưng
không mất tiền — đây là đúng đường đã dùng cho 401 lô văn xuôi trước.

BẪY ĐÃ DÍNH Ở VÒNG VĂN XUÔI (đọc trước khi đổi số):
  * Lô 250 câu ⇒ 17% dữ liệu LỆCH DÒNG mà mọi phép kiểm hình thức đều xanh (đủ dòng, đủ `n`).
    Nên ở đây lô để **120 câu** và bản gom BẮT BUỘC chấm bằng âm Hán-Việt, không tin `n`.
  * Model tự đánh lại `n` = 1..N theo thứ tự nó sinh. Ghép theo `n` vẫn lệch nếu nó rớt câu
    giữa chừng — nên `gather` đối chiếu NỘI DUNG rồi mới nhận.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

_HAN = re.compile(r"[一-鿿]")
LOT = 120


def _gw():
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "gw", Path(__file__).with_name("38_translate_gateway.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def export(args) -> None:
    gw = _gw()
    done = set()
    if args.done.exists():
        for line in args.done.open(encoding="utf-8"):
            if line.strip():
                row = json.loads(line)
                done.add((row["novel_id"], row["chapter_index"]))
    genres = tuple(x.strip() for x in args.genres.split(",")) if args.genres \
        else (gw.GAP_GENRES if args.gap_genres else None)
    novels = gw.pick_novels(args.chapters_file, genres) if genres else None
    chapters = [c for c in gw.load_chapters(args.chapters_file, None, novels)
                if (c.get("novel_id"), c.get("chapter_index")) not in done]
    args.dir.mkdir(parents=True, exist_ok=True)

    # `key` giữ được chương/câu gốc, nên gom về khỏi phải đoán; `n` chỉ để Gemini đánh số.
    rows: list[dict] = []
    for ch in chapters:
        for i, zh in enumerate(gw.split_sentences(ch.get("zh", "")), 1):
            rows.append({"novel_id": ch["novel_id"], "chapter_index": ch["chapter_index"],
                         "i": i, "zh": zh})
    lots = [rows[k:k + LOT] for k in range(0, len(rows), LOT)]
    for j, lot in enumerate(lots):
        (args.dir / f"in_{j:04d}.jsonl").write_text("\n".join(
            json.dumps({"n": m + 1, "zh": r["zh"]}, ensure_ascii=False)
            for m, r in enumerate(lot)) + "\n", encoding="utf-8")
        (args.dir / f"key_{j:04d}.jsonl").write_text("\n".join(
            json.dumps(r, ensure_ascii=False) for r in lot) + "\n", encoding="utf-8")
    print(f"{len(chapters)} chương · {len(rows):,} câu · {len(lots)} lô × {LOT} câu"
          f"\nthư mục: {args.dir}")


def gather(args) -> None:
    gw = _gw()
    from lot_io import read_out
    from novelworker.translator import hanviet
    table = hanviet._load()
    # Chống trùng: DeepSeek chạy song song cùng ghi vào `done`, nên đọc lại NGAY trước khi
    # gom và bỏ chương đã có. Không có bước này thì một chương vào corpus hai lần.
    have: set[tuple] = set()
    if args.done.exists():
        for line in args.done.open(encoding="utf-8"):
            if line.strip():
                r = json.loads(line)
                have.add((r["novel_id"], r["chapter_index"]))
    kept = dropped = skipped = 0
    with args.done.open("a", encoding="utf-8") as out:
        for key_path in sorted(args.dir.glob("key_*.jsonl")):
            vi_path = args.dir / key_path.name.replace("key_", "out_")
            if not vi_path.exists():
                continue
            all_src = [json.loads(x) for x in key_path.open(encoding="utf-8") if x.strip()]
            src = [r for r in all_src if (r["novel_id"], r["chapter_index"]) not in have]
            if not src:
                skipped += 1
                continue
            got, fixed, lost = read_out(vi_path)
            if fixed:
                print(f"  {vi_path.name}: vá {fixed} dòng nháy chưa thoát")
            for m, r in enumerate(all_src):
                r["_m"] = m + 1
            # Thiếu vài câu thì nhận phần có, đừng bỏ cả lô: `got` đánh theo `n` của câu
            # nguồn nên câu vắng không đẩy câu nào lệch chỗ.
            if len(got) < len(all_src) * args.min_cover:
                print(f"  {vi_path.name}: {len(got)}/{len(all_src)} dòng — BỎ"); dropped += 1
                continue
            src = [r for r in src if r["_m"] in got]
            if not src:
                skipped += 1
                continue
            pairs = [(s["zh"], got[s["_m"]]) for s in src]
            rate = gw.aligned_rate(pairs, table)
            han = sum(1 for _, v in pairs if _HAN.search(v)) / len(pairs)
            if rate < args.min_align or han > args.max_han:
                print(f"  {vi_path.name}: khớp {rate:.0%} Hán {han:.0%} — BỎ"); dropped += 1
                continue
            for s, (_, vi) in zip(src, pairs):
                have.add((s["novel_id"], s["chapter_index"]))
                out.write(json.dumps({"novel_id": s["novel_id"],
                                      "chapter_index": s["chapter_index"],
                                      "n": s["i"], "zh": s["zh"], "vi": vi},
                                     ensure_ascii=False) + "\n")
            kept += 1
    print(f"nhận {kept} lô · bỏ {dropped} lô · trùng sẵn {skipped} lô → {args.done}")


def main(argv=None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=("export", "gather"))
    ap.add_argument("--chapters-file", type=Path,
                    default=Path.home() / "hachimi-work/scratch/zh_raw_v7.jsonl")
    ap.add_argument("--done", type=Path,
                    default=Path.home() / "hachimi-work/scratch/crawl_gap_merged.jsonl")
    ap.add_argument("--dir", type=Path,
                    default=Path.home() / "hachimi-work/scratch/gap_batch")
    ap.add_argument("--gap-genres", action="store_true", default=True)
    ap.add_argument("--genres", default="",
                    help="danh sách thể loại ngăn bằng phẩy, ví dụ 'game'; "
                         "để trống thì dùng bốn thể loại thiếu")
    ap.add_argument("--min-align", type=float, default=0.85)
    ap.add_argument("--max-han", type=float, default=0.10)
    ap.add_argument("--min-cover", type=float, default=0.95)
    args = ap.parse_args(argv)
    (export if args.mode == "export" else gather)(args)


if __name__ == "__main__":
    main()
