"""Chấm ba bậc probe v7 ở NHÀ: chrF từng bậc, đặt cạnh HAI mốc trên CÙNG bộ dev.

Câu hỏi của bậc P0: *data người có đủ để train từ số 0 không?*

⚠ Đọc kỹ chỗ này trước khi tin con số. Bộ dev là truyện holdout của **kaihe**, mà probe cũng
train trên kaihe ⇒ probe có **lợi thế sân nhà**, thắng `hirashiba-mt-tiny` gần như chắc chắn và
điều đó **không chứng minh gì cả**. Nên luôn chấm kèm mốc thứ hai là chính model production
(`--ct2-baseline .../ct2-int8_float32`): nó 57M, train trên data khác, cũng chịu bất lợi sân
khách y hệt. Cách đọc đúng:

- p0 **sập hẳn** so với cả hai mốc ⇒ 2M cặp chưa đủ dựng một model từ số 0, dừng.
- p0 đứng được (12M tham số) cạnh production 57M ⇒ dây chuyền lành, bản thật với 11M cặp và
  57M tham số đáng bỏ 15-30 giờ GPU.
- p0 thắng đậm cả hai ⇒ **đừng mừng**, đó phần lớn là lợi thế sân nhà.

    python eval_scratch_probe.py --hyp-dir ~/hachimi-work/scratch/kaggle_out \
        --dev ~/hachimi-work/scratch/dev.jsonl \
        --ct2-baseline ~/hachimi-work/hachimi-v6/ct2-int8_float32

Từ bậc P1 trở đi ĐỪNG dùng chrF — nó thưởng model trung tính (ghi ở
`docs/ban-giao-2026-08-30.md`). Dùng `eval/eval_register.py --context 2` để đo bịa chủ ngữ và
`eval/eval_project_metrics.py` cho lint/đại từ.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

BASELINE = "chi-vi/hirashiba-mt-tiny-zh-vi"


def load_dev(path: Path, limit: int) -> list[dict]:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    return rows[:limit]


def chrf(hypotheses: list[str], references: list[str]) -> float:
    import sacrebleu

    return round(sacrebleu.corpus_chrf(hypotheses, [references]).score, 2)


def translate_hf(model_id: str, sources: list[str], batch: int, beam: int) -> list[str]:
    """Mốc chạy bằng HF generate chứ không convert CT2: model ngoài có thể có hàng <pad> thừa
    cuối vocab, mà `kaggle_train._export_ct2` lại vá tắt bước cắt pad cho model của mình —
    trộn hai thứ đó là ra vocab lệch một dòng, sai âm thầm."""
    import torch
    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(model_id)
    model = AutoModelForSeq2SeqLM.from_pretrained(model_id).eval()
    out: list[str] = []
    with torch.no_grad():
        for start in range(0, len(sources), batch):
            chunk = sources[start:start + batch]
            encoded = tokenizer(chunk, return_tensors="pt", padding=True, truncation=True,
                                max_length=256)
            generated = model.generate(**encoded, num_beams=beam, max_new_tokens=180)
            out.extend(tokenizer.batch_decode(generated, skip_special_tokens=True))
            print(f"  mốc {min(start + batch, len(sources))}/{len(sources)}", flush=True)
    return out


def translate_ct2(model_dir: Path, sources: list[str], beam: int) -> list[str]:
    """Mốc production: CT2 + spm thô, đúng đường chạy thật của worker."""
    import ctranslate2
    import sentencepiece as spm

    translator = ctranslate2.Translator(str(model_dir), device="cpu", compute_type="int8",
                                        intra_threads=8)
    processor = spm.SentencePieceProcessor()
    processor.load(str(model_dir / "source.spm"))
    results = translator.translate_batch(
        [processor.encode(text, out_type=str) + ["</s>"] for text in sources],
        beam_size=beam, max_batch_size=8, max_decoding_length=180)
    return [processor.decode([t for t in r.hypotheses[0] if t != "</s>"]) for r in results]


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dev", type=Path, default=Path.home() / "hachimi-work/scratch/dev.jsonl")
    ap.add_argument("--hyp-dir", type=Path, required=True,
                    help="thư mục tải về từ `kaggle kernels output` (có hyp_p0.json…)")
    ap.add_argument("--baseline", default=BASELINE, help="mốc HF cùng cỡ; '-' để bỏ qua")
    ap.add_argument("--ct2-baseline", type=Path, action="append", default=[],
                    help="mốc CT2 tại chỗ, ví dụ model production — nên luôn có một cái")
    ap.add_argument("--limit", type=int, default=500)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--beam", type=int, default=4)
    args = ap.parse_args(argv)

    rows = load_dev(args.dev, args.limit)
    references = [row["vi"] for row in rows]
    table: dict[str, float] = {}

    for path in sorted(args.hyp_dir.glob("hyp_*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        hypotheses, refs = payload["hyp"], payload["ref"]
        if len(hypotheses) != len(refs):
            print(f"!! {path.name}: {len(hypotheses)} bản dịch vs {len(refs)} tham chiếu, bỏ")
            continue
        table[path.stem.replace("hyp_", "")] = chrf(hypotheses, refs)

    if args.baseline != "-":
        # Mốc chỉ dịch CÂU HIỆN TẠI: nó là model câu-lẻ, nhét ⟪ctx⟫ vào là chấm oan nó.
        hypotheses = translate_hf(args.baseline, [row["zh"] for row in rows], args.batch, args.beam)
        table[args.baseline] = chrf(hypotheses, references)
        (args.hyp_dir / "hyp_baseline.json").write_text(
            json.dumps({"hyp": hypotheses, "ref": references,
                        "zh": [r["zh"] for r in rows]}, ensure_ascii=False),
            encoding="utf-8")

    for model_dir in args.ct2_baseline:
        hypotheses = translate_ct2(model_dir, [row["zh"] for row in rows], args.beam)
        table[f"ct2:{model_dir.parent.name}"] = chrf(hypotheses, references)

    width = max(len(name) for name in table) if table else 10
    for name, score in sorted(table.items(), key=lambda item: -item[1]):
        print(f"{name:<{width}}  chrF {score}")
    print("\nCổng P0: p0 đứng được cạnh mốc production (dù chỉ 12M vs 57M) ⇒ dây chuyền lành,")
    print("bản thật đáng bỏ 15-30 giờ GPU. p0 sập hẳn ⇒ 2M cặp chưa đủ, dừng.")
    print("Nhắc lại: dev là truyện holdout của kaihe nên probe CÓ lợi thế sân nhà — thắng đậm")
    print("mốc ngoài không phải bằng chứng.")


if __name__ == "__main__":
    main()
