"""Tìm thuật ngữ bị dịch KHÔNG NHẤT QUÁN trong glossary — nguyên liệu để thêm global term.

Lỗi "Thiên Hương Lâu/Các", "đệ tử nòng cốt/hạch tâm": cùng một cụm Hán ra nhiều bản dịch
khác nhau giữa các truyện. Đây quét glossary_terms thật (mọi truyện), gom theo term_zh, in
ra cụm nào có ≥2 bản dịch — kèm số phiếu mỗi bản + gợi ý Hán-Việt làm trọng tài. User đọc,
chốt bản đúng, rồi thêm vào TERMS của 13_add_global_terms.py (chỉ nên ép cụm 1-NGHĨA an toàn).

READ-ONLY (không ghi DB). Chạy như 13_add_global_terms.py (từ worker/):
    python hachimi/pipeline/check_glossary_consistency.py [--min-novels 3] [--top 40]
"""
from __future__ import annotations

import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # worker/ vào path


def find_inconsistent(rows: list[dict], min_variants: int = 2) -> list[tuple[str, Counter]]:
    """Gom correct_vi theo term_zh; trả các term có ≥min_variants bản dịch khác nhau,
    xếp theo tổng số lần xuất hiện (cụm phổ biến trước)."""
    variants: dict[str, Counter] = defaultdict(Counter)
    for r in rows:
        zh = (r.get("term_zh") or "").strip()
        vi = (r.get("correct_vi") or "").strip()
        if len(zh) >= 2 and vi:
            variants[zh][vi] += 1
    out = [(zh, c) for zh, c in variants.items() if len(c) >= min_variants]
    out.sort(key=lambda item: -sum(item[1].values()))
    return out


def _fetch_all() -> list[dict]:
    from novelworker.db import sb
    rows, off, step = [], 0, 1000
    while True:
        page = (sb().table("glossary_terms")
                .select("term_zh, correct_vi, novel_id, approved")
                .order("id").range(off, off + step - 1).execute()).data or []
        rows += page
        if len(page) < step:
            break
        off += step
    return rows


def main(min_novels: int, top: int) -> None:
    from novelworker.translator import hanviet
    rows = _fetch_all()
    bad = find_inconsistent(rows)
    bad = [(zh, c) for zh, c in bad if sum(c.values()) >= min_novels]
    print(f"{len(rows)} term glossary · {len(bad)} cụm có ≥2 bản dịch (xuất hiện ≥{min_novels} lần)\n")
    for zh, c in bad[:top]:
        hv = hanviet.han_viet(zh)
        ordered = c.most_common()
        winner = ordered[0][0]
        # đánh dấu bản khớp Hán-Việt (trọng tài) và bản thắng phiếu
        parts = []
        for vi, n in ordered:
            tag = ""
            if vi.casefold() == (hv or "").casefold():
                tag = "★HV"
            parts.append(f"{vi}×{n}{('('+tag+')') if tag else ''}")
        print(f"{zh}  [HV={hv}]  →  " + " | ".join(parts))
    print("\nGợi ý: cụm 1-nghĩa + có bản ★HV hoặc thắng phiếu rõ → thêm vào TERMS "
          "(13_add_global_terms.py). Cụm ĐA NGHĨA (vd 白板=quân bài/bảng trắng) thì ĐỪNG ép global.")


def _self_check() -> None:
    rows = [
        {"term_zh": "天香楼", "correct_vi": "Thiên Hương Lâu"},
        {"term_zh": "天香楼", "correct_vi": "Thiên Hương Các"},
        {"term_zh": "天香楼", "correct_vi": "Thiên Hương Lâu"},
        {"term_zh": "韩立", "correct_vi": "Hàn Lập"},          # nhất quán → bỏ qua
        {"term_zh": "x", "correct_vi": "y"},                   # <2 ký tự → bỏ
    ]
    bad = find_inconsistent(rows)
    assert len(bad) == 1 and bad[0][0] == "天香楼"
    assert bad[0][1]["Thiên Hương Lâu"] == 2 and bad[0][1]["Thiên Hương Các"] == 1
    print("check_glossary_consistency OK")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        _self_check()
    else:
        args = sys.argv[1:]
        mn = int(args[args.index("--min-novels") + 1]) if "--min-novels" in args else 3
        tp = int(args[args.index("--top") + 1]) if "--top" in args else 40
        main(mn, tp)
