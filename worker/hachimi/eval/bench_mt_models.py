"""So các model dịch chuyên GỐC (chưa finetune) trên cùng 400 câu có bản dịch NGƯỜI (kaihe).

Chấm chrF/BLEU so bản người + đo tốc độ thật trên box production. Mỗi họ model có cách
báo ngôn ngữ đích riêng — sai chỗ này là model dịch ra ngôn ngữ khác chứ không phải dở.
"""
from __future__ import annotations
import json, sys, time
from pathlib import Path
import ctranslate2, sacrebleu

HERE = Path("/bench")
MODELS = Path("/mt")
EOS = "</s>"
MAX_SRC = 110   # hirashiba-medium chỉ có position encoding tới 128


def make_runner(d: Path):
    """Trả (encode, decode, target_prefix) đúng theo họ model."""
    name = d.name
    if (d / "source.spm").exists():          # Marian: hachimi, opus-mt, hirashiba-tiny
        import sentencepiece as spm
        src, tgt = spm.SentencePieceProcessor(), spm.SentencePieceProcessor()
        src.load(str(d / "source.spm")); tgt.load(str(d / "target.spm"))
        return (lambda s: src.encode(s, out_type=str)[:MAX_SRC] + [EOS],
                lambda t: tgt.decode(t), None)

    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(str(d))

    if "nllb" in name:
        tok.src_lang = "zho_Hans"
        prefix = ["vie_Latn"]
    elif "m2m100" in name:
        tok.src_lang = "zh"
        prefix = [tok.lang_code_to_token["vi"]]
    elif "madlad" in name:
        prefix = None                        # madlad báo đích bằng '<2vi>' ngay trong nguồn
    else:
        prefix = None                        # Marian dạng tokenizer.json (hirashiba-medium)

    def enc(s: str) -> list[str]:
        if "madlad" in name:
            s = "<2vi> " + s
        t = tok.convert_ids_to_tokens(tok(s).input_ids)
        return t[:MAX_SRC] + [EOS] if len(t) > MAX_SRC else t

    def dec(t: list[str]) -> str:
        return tok.decode(tok.convert_tokens_to_ids(t), skip_special_tokens=True)

    return enc, dec, prefix


def run(d: Path, pairs: list[dict], beam: int, threads: int) -> dict:
    enc, dec, prefix = make_runner(d)
    tr = ctranslate2.Translator(str(d), device="cpu", compute_type="int8",
                                intra_threads=threads)
    src = [enc(p["zh"]) for p in pairs]
    t0 = time.time()
    res = tr.translate_batch(
        src, beam_size=beam, max_decoding_length=256, max_batch_size=8,
        repetition_penalty=1.1, no_repeat_ngram_size=4,
        target_prefix=[prefix] * len(src) if prefix else None)
    dt = time.time() - t0
    hyp = []
    for r in res:
        toks = [t for t in r.hypotheses[0] if t != EOS]
        if prefix:
            toks = toks[len(prefix):]
        hyp.append(dec(toks))
    ref = [[p["vi"] for p in pairs]]
    return {"model": d.name, "sec": round(dt, 1),
            "chrF": round(sacrebleu.corpus_chrf(hyp, ref).score, 2),
            "BLEU": round(sacrebleu.corpus_bleu(hyp, ref).score, 2),
            "chars_per_s": round(sum(len(p["zh"]) for p in pairs) / dt),
            "sample": hyp[:3]}


def main() -> None:
    beam = int(sys.argv[1]) if len(sys.argv) > 1 else 6
    threads = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    only = sys.argv[3].split(",") if len(sys.argv) > 3 else []
    pairs = [json.loads(l) for l in (HERE / "mt_testset.jsonl").open(encoding="utf-8")]
    dirs = sorted(p for p in MODELS.iterdir() if p.is_dir() and (p / "model.bin").exists())
    if only:
        dirs = [d for d in dirs if d.name in only]
    print(f"{len(pairs)} câu · beam={beam} · threads={threads}\n", flush=True)
    out = []
    for d in dirs:
        try:
            r = run(d, pairs, beam, threads)
            out.append(r)
            print(f"{r['model']:22s} chrF {r['chrF']:6.2f} · BLEU {r['BLEU']:6.2f} · "
                  f"{r['sec']:7.1f}s · {r['chars_per_s']:5d} chữ Trung/s", flush=True)
        except Exception as e:
            print(f"{d.name:22s} LỖI {str(e)[:150]}", flush=True)
    old = HERE / "mt_bench_out.json"
    prev = json.loads(old.read_text(encoding="utf-8")) if old.exists() else []
    keep = [p for p in prev if p["model"] not in {r["model"] for r in out}]
    old.write_text(json.dumps(keep + out, ensure_ascii=False, indent=1), encoding="utf-8")
    print("\nMẫu câu đầu:")
    for r in out:
        print(f"  [{r['model']}] {r['sample'][0][:140]}")


main()
