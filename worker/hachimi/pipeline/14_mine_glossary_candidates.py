"""Mine ứng viên glossary từ kho human-dịch: cụm zh mà v5 dịch LỆCH so với người.

Ý tưởng (Hạng 2, dùng chính data người làm thay vì đoán term):
  1. Lấy mẫu cặp (zh, vi-người) từ kaihe_anchor.
  2. Chạy v5 dịch lại zh -> vi-v5.
  3. Câu "lệch" = độ giống (token) giữa vi-v5 và vi-người thấp.
  4. Quy lỗi về cụm: cụm zh 2-4 ký tự nào XUẤT HIỆN NHIỀU trong câu lệch hơn hẳn nền
     (lift cao) => ứng viên term đáng ép glossary. In kèm ví dụ để người chốt VI.

KHÔNG ghi DB — chỉ in + xuất jsonl ứng viên. Người đọc quyết VI (gu là của user;
term sai đầu độc glossary — xem docs/memory glossary-drift).

    python 14_mine_glossary_candidates.py --n 8000 --sim 0.45 --min-df 8
"""
from __future__ import annotations

import argparse
import difflib
import json
import os
import random
import re
from collections import Counter
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data" / "kaihe_anchor.jsonl"
OUT = Path(__file__).resolve().parents[1] / "data" / "glossary_candidates.jsonl"
_HAN = re.compile(r"[一-鿿]")


def _load_glossary_zh() -> set[str]:
    """term_zh đã có trong glossary global — để loại khỏi ứng viên. DB không nối được thì rỗng."""
    try:
        import sys
        sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
        from novelworker import db
        rows = (db.sb().table("glossary_terms").select("term_zh")
                .execute().data or [])
        return {(r.get("term_zh") or "").strip() for r in rows}
    except Exception as exc:  # DB không có creds khi chạy local — bỏ qua, chỉ mất bước loại trùng
        print(f"[cảnh báo] không nối được glossary DB ({exc}); bỏ qua bước loại term đã có")
        return set()


def _ngrams(zh: str, lo: int = 2, hi: int = 4) -> set[str]:
    """Cụm Hán liền mạch 2-4 ký tự, dedup trong 1 câu (đếm document-frequency, không term-freq)."""
    out: set[str] = set()
    for run in _HAN.findall(zh) and re.findall(r"[一-鿿]+", zh):
        for n in range(lo, hi + 1):
            for i in range(len(run) - n + 1):
                out.add(run[i : i + n])
    return out


def _sim(a: str, b: str) -> float:
    """Độ giống token tiếng Việt (nhanh, đủ để tách câu lệch khỏi câu khớp)."""
    return difflib.SequenceMatcher(None, a.split(), b.split()).ratio()


def mine(n: int, sim_thr: float, min_df: int, min_lift: float, seed: int) -> list[dict]:
    from novelworker.translator.hachimi_engine import _Engine
    rows = [json.loads(l) for l in DATA.open(encoding="utf-8")]
    rows = [r for r in rows if 6 <= len(r.get("zh", "")) <= 120 and r.get("vi")]
    random.Random(seed).shuffle(rows)
    rows = rows[:n]
    print(f"mẫu {len(rows)} cặp · dịch v5…")

    eng = _Engine(os.environ["HACHIMI_MODEL_DIR"])
    v5 = eng.translate_lines([r["zh"] for r in rows])

    df: Counter[str] = Counter()      # số câu chứa cụm
    bdf: Counter[str] = Counter()     # số câu LỆCH chứa cụm
    bad_total = 0
    examples: dict[str, list[tuple[str, str, str]]] = {}
    for r, hyp in zip(rows, v5):
        grams = _ngrams(r["zh"])
        bad = _sim(hyp, r["vi"]) < sim_thr
        bad_total += bad
        for g in grams:
            df[g] += 1
            if bad:
                bdf[g] += 1
                examples.setdefault(g, [])
                if len(examples[g]) < 2:
                    examples[g].append((r["zh"], r["vi"], hyp))

    base = bad_total / len(rows) or 1e-9
    have = _load_glossary_zh()
    cands = []
    for g, d in df.items():
        if d < min_df or g in have:
            continue
        lift = (bdf[g] / d) / base
        if lift < min_lift:
            continue
        cands.append({"zh": g, "df": d, "bad": bdf[g], "lift": round(lift, 2),
                      "examples": examples.get(g, [])})
    # cụm dài trùm cụm con: ưu tiên điểm = bad * lift, rồi loại cụm con nếu cụm cha điểm cao hơn
    cands.sort(key=lambda c: -c["bad"] * c["lift"])
    kept: list[dict] = []
    for c in cands:
        if any(c["zh"] in k["zh"] and k["bad"] * k["lift"] >= c["bad"] * c["lift"] for k in kept):
            continue
        kept.append(c)
    return kept


def _self_check() -> None:
    assert _ngrams("网吧开黑") == {"网吧", "开黑", "网吧开", "吧开黑", "网吧开黑", "吧开"}
    assert _sim("hắn đi", "hắn đi") == 1.0 and _sim("a b c", "x y z") == 0.0
    assert _ngrams("a网吧") == {"网吧"}  # bỏ ký tự không-Hán, không tạo cụm bắc cầu
    print("14_mine_glossary_candidates self-check OK")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-check", action="store_true")
    ap.add_argument("--n", type=int, default=8000)
    ap.add_argument("--sim", type=float, default=0.45)
    ap.add_argument("--min-df", type=int, default=8)
    ap.add_argument("--min-lift", type=float, default=1.6)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--top", type=int, default=40)
    a = ap.parse_args()
    if a.self_check:
        _self_check()
        raise SystemExit
    cands = mine(a.n, a.sim, a.min_df, a.min_lift, a.seed)
    OUT.write_text("".join(json.dumps(c, ensure_ascii=False) + "\n" for c in cands), encoding="utf-8")
    print(f"\n{len(cands)} ứng viên -> {OUT}\nTop {a.top} (df=xuất hiện, bad=số câu lệch, lift):\n")
    for c in cands[: a.top]:
        print(f"  {c['zh']:6} df={c['df']:4} bad={c['bad']:3} lift={c['lift']}")
        for zh, vi, hyp in c["examples"][:1]:
            print(f"        zh : {zh[:70]}")
            print(f"        ng : {vi[:70]}")
            print(f"        v5 : {hyp[:70]}")
