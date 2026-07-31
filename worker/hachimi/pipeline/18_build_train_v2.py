"""Corpus train doc-level v2 = SỬA lỗi v1 (thiếu gold register).

v1 thất bại vì train từ base sạch + CHỈ corpus doc-level rộng → register tụt về base (đại từ
hiện đại 196 vs teacher-v4 86). Chẩn đoán: mất bộ booster/gold nhắm-đích làm teacher-v4 giỏi.

v2 = gold register của teacher-v4 (core+booster+game, LẶP để booster đậm ~10% như teacher-v4)
   + corpus doc-level (cap nhỏ lại để gold không bị loãng) cho bài học NGỮ CẢNH.
Giữ cả hai: register nhắm-đích (đè 524) + ngữ cảnh (đè bịa chủ ngữ). Train từ base sạch 1 lượt.

    python 18_build_train_v2.py                       # -> data/doclevel_v2_corpus.jsonl
    python 18_build_train_v2.py --cap 34000 --gold-repeat 6
    python 18_build_train_v2.py --self-check
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data"
GOLD = [DATA / "gold" / f for f in (
    "core_gold.jsonl", "booster_v3.jsonl",
    "train_game_english_approved.jsonl", "train_db_game_litrpg_approved.jsonl")]
DOCLEVEL = DATA / "doclevel_corpus.jsonl"
OUT = DATA / "doclevel_v2_corpus.jsonl"


def _pair(row: dict) -> dict | None:
    zh = (row.get("zh") or row.get("source") or row.get("source_zh") or "").strip()
    vi = (row.get("vi") or row.get("proposed_vi") or row.get("target") or row.get("target_vi") or "").strip()
    return {"zh": zh, "vi": vi} if zh and vi else None


def load_gold() -> list[dict]:
    rows = []
    for path in GOLD:
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip() and (p := _pair(json.loads(line))):
                rows.append({**p, "source": "gold", "human": True})
    return rows


def main(argv=None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cap", type=int, default=34_000, help="số cặp doc-level lấy vào")
    ap.add_argument("--gold-repeat", type=int, default=6, help="lặp gold để booster đậm ~10%")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return

    gold = load_gold()
    doclevel = [json.loads(l) for l in DOCLEVEL.read_text(encoding="utf-8").splitlines() if l.strip()]
    rnd = random.Random(20260731)
    rnd.shuffle(doclevel)
    doclevel = doclevel[:args.cap]
    mix = gold * args.gold_repeat + doclevel
    rnd.shuffle(mix)
    OUT.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in mix), encoding="utf-8")

    n_gold = len(gold) * args.gold_repeat
    booster = sum(1 for _ in (DATA / "gold" / "booster_v3.jsonl").read_text(encoding="utf-8").splitlines() if _.strip())
    print(f"v2: {len(mix):,} cặp = gold {n_gold:,} (×{args.gold_repeat}, {n_gold/len(mix):.0%}) "
          f"+ doc-level {len(doclevel):,}")
    print(f"  booster đậm độ: {booster * args.gold_repeat / len(mix):.1%} (teacher-v4 ~10%)")
    print(f"  có ngữ cảnh: {sum(1 for r in mix if r.get('ctx_len')) / len(mix):.0%}")
    print(f"→ {OUT}")


def _self_check() -> None:
    assert all(p.is_file() for p in GOLD), "thiếu file gold"
    g = load_gold()
    assert len(g) > 900 and all(r["zh"] and r["vi"] and r["source"] == "gold" for r in g)
    assert _pair({"source_zh": "他", "target_vi": "Hắn"}) == {"zh": "他", "vi": "Hắn"}
    assert _pair({"zh": "", "vi": "x"}) is None
    print("18_build_train_v2 OK")


if __name__ == "__main__":
    main()
