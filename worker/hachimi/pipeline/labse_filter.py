"""Lọc cặp kaihe theo điểm LaBSE (chạy SAU 15_score_labse.py, trên Kaggle GPU).

15_score_labse.py chỉ CHẤM (thêm trường `labse`). Script này: in phân bố điểm + các cặp
điểm THẤP NHẤT để đọc tay chốt ngưỡng (bài học dự án: đừng tin thước đo mù), rồi lọc
`labse >= ngưỡng` ghi ra file train.

    python labse_filter.py kaihe_scored.jsonl kaihe_anchor.jsonl --min 0.70

Đọc 15 cặp điểm thấp in ra: nếu chúng ĐÚNG là lệch-căn (Trung một đằng Việt một nẻo) thì
ngưỡng ổn; nếu có cặp dịch ĐÚNG mà điểm thấp thì hạ ngưỡng xuống.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", type=Path, help="file đã có trường labse (từ 15_score_labse.py)")
    ap.add_argument("output", type=Path, help="file train sau lọc")
    ap.add_argument("--min", type=float, default=0.70, help="ngưỡng cosine LaBSE (DATA_CHUAN ~0.70)")
    ap.add_argument("--show", type=int, default=15, help="số cặp điểm thấp in ra để đọc tay")
    args = ap.parse_args(argv)
    try:
        import sys
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    except Exception:
        pass

    rows = [json.loads(l) for l in args.input.read_text(encoding="utf-8").splitlines() if l.strip()]
    scored = [r for r in rows if "labse" in r]
    if not scored:
        raise SystemExit("Input chưa có trường 'labse' — chạy 15_score_labse.py trước.")
    scored.sort(key=lambda r: r["labse"])

    n = len(scored)
    pct = [scored[int(n * q)]["labse"] for q in (0.01, 0.05, 0.10, 0.25, 0.50)]
    print(f"{n} cặp · phân bố labse  p1={pct[0]:.3f} p5={pct[1]:.3f} p10={pct[2]:.3f} "
          f"p25={pct[3]:.3f} median={pct[4]:.3f}")
    print(f"\n--- {args.show} CẶP ĐIỂM THẤP NHẤT (đọc tay: có ĐÚNG là lệch-căn không?) ---")
    for r in scored[:args.show]:
        print(f"[{r['labse']:.3f}] ZH: {r['zh'][:90]}")
        print(f"        VI: {r['vi'][:90]}")

    kept = [r for r in scored if r["labse"] >= args.min]
    args.output.write_text(
        "".join(json.dumps({k: v for k, v in r.items() if k != "labse"}, ensure_ascii=False) + "\n"
                for r in kept), encoding="utf-8")
    print(f"\n=> giữ {len(kept)}/{n} (labse>={args.min}) → {args.output}  "
          f"| loại {n - len(kept)} ({100 * (n - len(kept)) / n:.1f}%)")


if __name__ == "__main__":
    main()
