"""Chấm một dải lô out_XXXX.jsonl trước khi cho chạy hàng loạt.

Dùng cho lô THỬ: 5 lô đủ để thấy model có lệch dòng / dịch thoát quá hay không, mà không
tốn quota chạy 375 lô rồi mới biết hỏng. Mọi con số đều kèm mốc đối chiếu đã đo.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lot_io import read_out                                            # noqa: E402
from quality_gate import audit                                          # noqa: E402

_HAN = re.compile(r"[一-鿿]")
_BAN = re.compile(r"(?<![a-zA-ZÀ-ỹ])(tôi|cậu|bạn|anh ấy|cô ấy|anh ta|cô ta|ông ta|bà ta)"
                  r"(?![a-zA-ZÀ-ỹ])", re.I)
# Phải trừ các cụm KHÔNG phải đại từ trước khi dò, nếu không thước phóng đại gấp ba:
# đo 02/09 trên 720 câu Sonnet, 9 lần báo vi phạm nhưng chỉ 3 lần là thật — sáu lần còn
# lại là "tôi luyện" (rèn), "bạn thân", "bạn học", "bạn gái", toàn danh/động từ.
_NOT_PRON = re.compile(
    r"tôi luyện|bạn (?:học|thân|bè|hữu|đường|đồng|tốt|cũ|đọc|gái|trai|nhậu)|"
    r"cậu (?:ấm|bé|ta)", re.I)


def _ban_hits(vi: str):
    return _BAN.search(_NOT_PRON.sub("~", vi))
# Mốc đã đo (xem docs/ban-giao-2026-09-01-prose.md và bảng hiệu chuẩn quality_gate).
MOC = [("người dịch (kaihe)", 1.86, 38.5),
       ("Gemini vòng này", 1.36, 32.6),
       ("Gemini văn xuôi cũ", 1.11, 29.2)]


def main(argv=None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", type=Path,
                    default=Path.home() / "hachimi-work/scratch/gap_batch")
    ap.add_argument("--lots", default="0-4", help="dải lô, ví dụ 0-4")
    args = ap.parse_args(argv)

    spec = importlib.util.spec_from_file_location(
        "gw", Path(__file__).with_name("38_translate_gateway.py"))
    gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
    from novelworker.translator import hanviet
    table = hanviet._load()

    lo, hi = (int(x) for x in args.lots.split("-"))
    allp: list[tuple[str, str]] = []
    print("%-14s %6s %8s %7s %8s" % ("lô", "dòng", "khớp", "Hán", "đại từ"))
    print("-" * 48)
    for j in range(lo, hi + 1):
        key = args.dir / f"key_{j:04d}.jsonl"
        out = args.dir / f"out_{j:04d}.jsonl"
        if not out.exists():
            print("%-14s CHƯA CÓ" % f"out_{j:04d}"); continue
        src = [json.loads(x) for x in key.open(encoding="utf-8") if x.strip()]
        got, fixed, lost = read_out(out)
        if len(got) != len(src):
            why = f"{lost} dòng JSON HỎNG" if lost else "THIẾU DÒNG"
            print("%-14s %6s  %s" % (f"out_{j:04d}", f"{len(got)}/{len(src)}", why))
            continue
        pairs = [(s["zh"], got[m + 1]) for m, s in enumerate(src)]
        if fixed:
            print("%-14s   (vá %d dòng nháy chưa thoát)" % ("", fixed))
        allp += pairs
        print("%-14s %6d %7.0f%% %6.0f%% %8d" % (
            f"out_{j:04d}", len(pairs), gw.aligned_rate(pairs, table) * 100,
            sum(1 for _, v in pairs if _HAN.search(v)) / len(pairs) * 100,
            sum(1 for _, v in pairs if _ban_hits(v))))
    if not allp:
        return
    a = audit(allp)
    print(f"\nGỘP {len(allp)} câu · khớp {gw.aligned_rate(allp, table):.0%}")
    print("%-22s %10s %10s" % ("", "convert/1k", "phiên âm"))
    print("%-22s %10s %9s%%" % ("Opus lô thử", a["convert_per_1k"], a["translit_pct"]))
    for name, cv, tl in MOC:
        print("%-22s %10s %9s%%" % (name, cv, tl))


if __name__ == "__main__":
    main()
