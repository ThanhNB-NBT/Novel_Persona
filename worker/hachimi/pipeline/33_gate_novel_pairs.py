"""Cổng cấp TRUYỆN: loại những cặp `nguyên tác Trung ↔ epub Việt` ghép nhầm truyện.

Vì sao cần (đo 30/08): `32_pair_novel_chapters.py` ghép theo tên truyện phiên âm Hán-Việt.
Cách đó **ghép nhầm thật** — mẫu `siêu cấp thiên phú` có nguyên tác là truyện hình sự đô thị
còn bản dịch là tiên hiệp. Trong 2.281 truyện ghép được, **793 (35%) không kiểm được tác giả**
vì ba kho `84sk/jjjjxsw/qisuwang` không ghi `作者：` trong tên file.

Vì sao gác ở cấp TRUYỆN chứ không cấp chương: cổng chương đúng nghĩa (dịch máy cả chương rồi
chấm chrF) tốn 21 triệu câu cho 209k cặp — quá nặng. Nhưng sai ở đây gần như luôn là sai cả
truyện, nên chỉ cần dịch vài câu của vài chương là đủ kết luận: **~34k câu, ~20 phút CPU**.

    python 33_gate_novel_pairs.py --paired paired.jsonl --out paired_clean.jsonl
    python 33_gate_novel_pairs.py --self-check

⚠ Ngưỡng do ĐO mà ra, không phán. Script tự dựng **đối chứng âm** (ghép chương Trung của truyện
này với chương Việt của truyện khác) rồi chọn ngưỡng tách hai phân bố. Bài học 30/08: thước
"trùng âm Hán-Việt" nhìn thì hợp lý nhưng đối chứng âm cho thấy nó lọt 27% cặp giả — truyện
tiên hiệp dùng chung kho từ Hán-Việt nên hai chương vô can vẫn trùng nhiều.
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

SENT = re.compile(r"[^。！？!?；;]*[。！？!?；;]")
DEFAULT_MODEL = Path.home() / "hachimi-work/hachimi-v6/ct2-int8_float32"


def zh_sentences(text: str, count: int) -> list[str]:
    """Vài câu Trung ĐẦU chương, bỏ câu quá ngắn (tiêu đề, tiếng động)."""
    out = []
    for match in SENT.finditer(text):
        piece = match.group(0).strip()
        if len(piece) >= 12:
            out.append(piece)
        if len(out) >= count:
            break
    return out


def score_pair(translations: list[str], vi_text: str) -> float:
    """chrF giữa bản dịch máy của mấy câu Trung và ĐOẠN ĐẦU chương Việt.

    Dùng đoạn đầu chứ không cả chương: chrF với một văn bản dài luôn cao giả tạo vì mẫu số
    tính trên bản dịch ngắn, còn cơ hội trùng n-gram thì nhiều.
    """
    import sacrebleu

    if not translations:
        return 0.0
    hypothesis = " ".join(translations)
    reference = vi_text[:max(400, len(hypothesis) * 3)]
    return sacrebleu.sentence_chrf(hypothesis, [reference]).score


def load_by_novel(path: Path, per_novel: int) -> dict[str, list[dict]]:
    """Gom tối đa `per_novel` chương mỗi truyện, rải đều chứ không lấy toàn chương đầu."""
    buckets: dict[str, list[dict]] = defaultdict(list)
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            row = json.loads(line)
            buckets[row["novel"]].append(row)
    out: dict[str, list[dict]] = {}
    for novel, rows in buckets.items():
        rows.sort(key=lambda r: r["index"])
        step = max(1, len(rows) // per_novel)
        out[novel] = rows[::step][:per_novel]
    return out


def run(args) -> None:
    import ctranslate2
    import sentencepiece as spm

    picked = load_by_novel(args.paired, args.chapters_per_novel)
    print(f"{len(picked):,} truyện · lấy tối đa {args.chapters_per_novel} chương mỗi truyện",
          flush=True)

    translator = ctranslate2.Translator(str(args.model), device="cpu", compute_type="int8",
                                        intra_threads=args.threads)
    processor = spm.SentencePieceProcessor()
    processor.load(str(args.model / "source.spm"))

    def translate(sentences: list[str]) -> list[str]:
        if not sentences:
            return []
        encoded = [processor.encode(s, out_type=str)[:120] + ["</s>"] for s in sentences]
        results = translator.translate_batch(encoded, beam_size=args.beam, max_batch_size=32,
                                             max_decoding_length=160)
        return [processor.decode([t for t in r.hypotheses[0] if t not in ("</s>", "<s>")])
                for r in results]

    novels = sorted(picked)
    rng = random.Random(args.seed)
    scores: dict[str, float] = {}
    negatives: list[float] = []
    for order, novel in enumerate(novels, 1):
        chapter_scores = []
        for row in picked[novel]:
            hyp = translate(zh_sentences(row["zh"], args.sentences))
            chapter_scores.append(score_pair(hyp, row["vi"]))
            # Đối chứng âm: CÙNG bản dịch máy đó, chấm với chương Việt của truyện KHÁC.
            other = picked[novels[rng.randrange(len(novels))]]
            if other and other[0]["novel"] != novel:
                negatives.append(score_pair(hyp, other[0]["vi"]))
        if chapter_scores:
            chapter_scores.sort()
            scores[novel] = chapter_scores[len(chapter_scores) // 2]
        if order % 100 == 0:
            print(f"  {order}/{len(novels)}", flush=True)

    positive = sorted(scores.values())
    negatives.sort()
    if not positive or not negatives:
        raise SystemExit("Không chấm được cặp nào")

    def rate(values: list[float], cut: float) -> float:
        return sum(1 for v in values if v >= cut) / len(values)

    cut, gap = max(((c, rate(positive, c) - rate(negatives, c))
                    for c in [i / 2 for i in range(20, 120)]), key=lambda x: x[1])
    print(f"\nDƯƠNG (cặp đã ghép) trung vị {positive[len(positive)//2]:.1f}")
    print(f"ÂM   (truyện khác)   trung vị {negatives[len(negatives)//2]:.1f}")
    print(f"NGƯỠNG đo được: {cut:.1f} → giữ {rate(positive, cut):.0%} truyện, "
          f"lọt {rate(negatives, cut):.0%} cặp giả (tách {gap:.0%})")
    if args.threshold is not None:
        cut = args.threshold
        print(f"  (dùng ngưỡng ép tay {cut})")

    keep = {n for n, s in scores.items() if s >= cut}
    kept = dropped = 0
    with args.paired.open(encoding="utf-8") as src, args.out.open("w", encoding="utf-8") as dst:
        for line in src:
            if json.loads(line)["novel"] in keep:
                dst.write(line)
                kept += 1
            else:
                dropped += 1
    report = {"novels": len(scores), "novels_kept": len(keep), "threshold": cut,
              "pairs_kept": kept, "pairs_dropped": dropped,
              "median_positive": positive[len(positive) // 2],
              "median_negative": negatives[len(negatives) // 2]}
    Path(str(args.out) + ".report.json").write_text(
        json.dumps({**report, "scores": scores}, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


def _self_check() -> None:
    # Câu đầu ngắn (tiêu đề/tiếng động) phải bị bỏ; chỉ lấy câu đủ dài.
    text = "短。" + "他走进房间，环视四周，然后坐了下来。" * 3
    got = zh_sentences(text, 2)
    assert len(got) == 2 and all(len(s) >= 12 for s in got), got
    assert not got[0].startswith("短"), got
    assert zh_sentences("", 3) == []
    # Chấm: bản dịch trùng đoạn đầu phải hơn hẳn bản chẳng liên quan.
    high = score_pair(["Hắn bước vào phòng, nhìn quanh bốn phía."],
                      "Hắn bước vào phòng, nhìn quanh bốn phía. Rồi ngồi xuống.")
    low = score_pair(["Hắn bước vào phòng, nhìn quanh bốn phía."],
                     "Cô gái mỉm cười, cầm lấy tách trà nóng trên bàn gỗ.")
    assert high > low + 20, (high, low)
    assert score_pair([], "abc") == 0.0

    rows = [{"novel": "A", "index": i, "zh": "x", "vi": "y"} for i in range(20)]
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "p.jsonl"
        path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows),
                        encoding="utf-8")
        picked = load_by_novel(path, 3)
        assert len(picked["A"]) == 3, picked
        # Rải đều, không dồn ba chương đầu.
        assert [r["index"] for r in picked["A"]] != [0, 1, 2]
    print("33_gate_novel_pairs OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--paired", type=Path,
                    default=Path.home() / "hachimi-work/scratch/paired.jsonl")
    ap.add_argument("--out", type=Path,
                    default=Path.home() / "hachimi-work/scratch/paired_clean.jsonl")
    ap.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    ap.add_argument("--chapters-per-novel", type=int, default=3)
    ap.add_argument("--sentences", type=int, default=5)
    ap.add_argument("--beam", type=int, default=2, help="cổng lọc thôi, khỏi beam 6")
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--threshold", type=float, help="ép ngưỡng thay vì để script tự đo")
    ap.add_argument("--seed", type=int, default=20260830)
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return
    run(args)


if __name__ == "__main__":
    main()
