"""Chấm độ căn khớp của cặp zh-vi bằng LaBSE, ghi thêm trường `labse` vào jsonl.

    python 15_score_labse.py vao.jsonl ra.jsonl [--batch 64] [--limit N]

Tách khỏi `14_gate_corpus.py` để cổng đó thuần stdlib, chạy được ở mọi máy. Script này cần
`sentence-transformers` và tải model ~1,8 GB lần đầu → **chạy ở máy nhà, đừng đụng VPS**
(VPS 2 vCPU không có việc gì phải nuôi một encoder 471M).

Ngưỡng nào là "đạt" thì KHÔNG chốt ở đây — chấm xong chạy `14_gate_corpus.py --calibrate`
trên một lô đã biết là tốt rồi mới đặt `LABSE_MIN`.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

MODEL = "sentence-transformers/LaBSE"


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--batch", type=int, default=64)
    ap.add_argument("--limit", type=int)
    args = ap.parse_args(argv)

    try:
        from sentence_transformers import SentenceTransformer, util
    except ImportError:
        raise SystemExit("Thiếu sentence-transformers: pip install sentence-transformers")

    rows = [json.loads(line) for line in args.input.read_text(encoding="utf-8").splitlines() if line.strip()]
    if args.limit:
        rows = rows[:args.limit]
    model = SentenceTransformer(MODEL)
    for start in range(0, len(rows), args.batch):
        chunk = rows[start:start + args.batch]
        zh = model.encode([r["zh"] for r in chunk], convert_to_tensor=True, normalize_embeddings=True)
        vi = model.encode([r["vi"] for r in chunk], convert_to_tensor=True, normalize_embeddings=True)
        for row, score in zip(chunk, util.pairwise_cos_sim(zh, vi).tolist()):
            row["labse"] = round(float(score), 4)
        print(f"  {min(start + args.batch, len(rows))}/{len(rows)}", flush=True)
    args.output.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    scored = [r["labse"] for r in rows]
    print(f"→ {args.output} — trung vị {sorted(scored)[len(scored) // 2]:.3f}")


if __name__ == "__main__":
    main()
