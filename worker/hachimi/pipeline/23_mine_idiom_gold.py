"""Lấy từ kaihe_anchor (bản dịch người thật) các câu chứa thành ngữ/phương ngữ
để OVERSAMPLE trong vòng patch v5 — human gold đã có sẵn, chỉ thiếu tần suất.

    python 23_mine_idiom_gold.py --per-term 40 --out ../data/gold/idiom_oversample.jsonl
"""
from __future__ import annotations

import argparse
import json
import random
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ANCHOR = HERE.parents[0] / "data" / "kaihe_anchor.jsonl"
OUT = HERE.parents[0] / "data" / "gold" / "idiom_oversample.jsonl"

# thành ngữ/chengyu hay bị dịch chết nghĩa + phương ngữ/lóng (từ audit + đọc tay)
IDIOMS = [
    "不由分说", "二话不说", "七上八下", "说曹操", "井水不犯河水", "顺藤摸瓜",
    "打草惊蛇", "一举两得", "半途而废", "名副其实", "出人头地", "恩将仇报",
    "忘恩负义", "血债血偿", "趁热打铁", "火上浇油", "雪上加霜", "祸不单行",
    "左右为难", "进退两难", "措手不及", "猝不及防", "出其不意", "心知肚明",
    "敷衍了事", "得寸进尺", "忍无可忍", "势不两立", "同归于尽", "自讨苦吃",
    "自作自受", "迫不得已", "无可奈何", "惺惺相惜", "人心惶惶", "蠢蠢欲动",
    "方兴未艾", "当机立断", "斩草除根", "瓮中之鳖", "如临大敌", "不动声色",
    # lóng/phương ngữ hiện đại
    "牛逼", "吹牛", "扯淡", "装逼", "卧槽", "我靠", "熊孩子", "土豪",
    "背锅", "甩锅", "打脸",
]


def main(per_term: int, seed: int) -> None:
    rng = random.Random(seed)
    picked: dict[str, list[dict]] = defaultdict(list)
    total = 0
    seen_zh: set[str] = set()
    with ANCHOR.open(encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            r = json.loads(line)
            zh, vi = (r.get("zh") or "").strip(), (r.get("vi") or "").strip()
            if not (6 <= len(zh) <= 120) or not vi or zh in seen_zh:
                continue
            hit = next((t for t in IDIOMS if t in zh), None)
            if hit is None or len(picked[hit]) >= per_term:
                continue
            seen_zh.add(zh)
            picked[hit].append({"zh": zh, "vi": vi,
                                "domain": f"idiom:{hit}", "status": "approved"})
            total += 1
    rows = [r for lst in picked.values() for r in lst]
    rng.shuffle(rows)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows),
                   encoding="utf-8")
    top = sorted(picked.items(), key=lambda kv: -len(kv[1]))[:10]
    print(f"{total} câu -> {OUT}")
    for t, lst in top:
        print(f"  {t}: {len(lst)}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-term", type=int, default=40)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out", type=Path, default=OUT)
    a = ap.parse_args()
    main(a.per_term, a.seed)
