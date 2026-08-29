"""So model ở CẤP CHƯƠNG trên bộ test sạch (nguyên tác Trung × bản dịch tay từ kho epub).

Bộ này chưa model nào trong dự án từng thấy, nên dùng được để so cả v5 production —
khác kaihe (đã dùng train v5 nên chấm v5 bằng nó sẽ ra điểm ảo).
"""
from __future__ import annotations
import json, re, sys, time
from pathlib import Path
import ctranslate2, sacrebleu, sentencepiece as spm

HERE = Path("/bench")
EOS = "</s>"
MAX_SRC = 110
SENT = re.compile(r"[^。！？!?；;]*[。！？!?；;]|[^。！？!?；;]+")


def split_line(line: str) -> list[str]:
    return [s for s in (m.group(0).strip() for m in SENT.finditer(line)) if s]


def load(d: Path):
    if (d / "source.spm").exists():
        src, tgt = spm.SentencePieceProcessor(), spm.SentencePieceProcessor()
        src.load(str(d / "source.spm")); tgt.load(str(d / "target.spm"))
        return (lambda s: src.encode(s, out_type=str)[:MAX_SRC] + [EOS], lambda t: tgt.decode(t))
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(str(d))
    return (lambda s: tok.convert_ids_to_tokens(tok(s).input_ids)[:MAX_SRC] + [EOS],
            lambda t: tok.decode(tok.convert_tokens_to_ids(t), skip_special_tokens=True))


def run(name: str, d: Path, rows: list[dict], beam: int, nbest: int, threads: int) -> dict:
    enc, dec = load(d)
    tr = ctranslate2.Translator(str(d), device="cpu", compute_type="int8", intra_threads=threads)
    hyps, refs, t0, n_sent = [], [], time.time(), 0
    for r in rows:
        units, index = [], []
        for line in [l for l in r["zh"].split("\n") if l.strip()]:
            parts = split_line(line)
            index.append(len(parts))
            units += parts
        n_sent += len(units)
        res = tr.translate_batch([enc(u) for u in units], beam_size=beam,
                                 num_hypotheses=1, max_decoding_length=256, max_batch_size=8,
                                 repetition_penalty=1.1, no_repeat_ngram_size=4)
        out, pos = [], 0
        for k in index:
            out.append(" ".join(dec([t for t in res[i].hypotheses[0] if t != EOS])
                                for i in range(pos, pos + k)))
            pos += k
        hyps.append("\n".join(out))
        refs.append(r["vi_human"])
    dt = time.time() - t0
    return {"model": name, "chapters": len(rows), "sentences": n_sent, "sec": round(dt, 1),
            "sec_per_chapter": round(dt / max(1, len(rows)), 1),
            "chrF": round(sacrebleu.corpus_chrf(hyps, [refs]).score, 2),
            "BLEU": round(sacrebleu.corpus_bleu(hyps, [refs]).score, 2),
            "sample": hyps[0][:400]}


def main() -> None:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    threads = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    rows = [json.loads(l) for l in (HERE / "clean_testset.jsonl").open(encoding="utf-8")][:n]
    targets = [("hachimi-v5-PRODUCTION", Path("/prod"), 6, 6),
               ("hachimi60-goc", Path("/mt/hachimi60-goc"), 6, 1),
               ("hirashiba-medium", Path("/mt/hirashiba-medium"), 6, 1)]
    print(f"{len(rows)} chương sạch · threads={threads}\n", flush=True)
    out = []
    for name, d, beam, nbest in targets:
        if not (d / "model.bin").exists():
            print(f"{name:24s} THIẾU {d}"); continue
        try:
            r = run(name, d, rows, beam, nbest, threads)
            out.append(r)
            print(f"{r['model']:24s} chrF {r['chrF']:6.2f} · BLEU {r['BLEU']:6.2f} · "
                  f"{r['sec_per_chapter']:6.1f}s/chương", flush=True)
        except Exception as e:
            print(f"{name:24s} LỖI {str(e)[:140]}", flush=True)
    (HERE / "mt_chapters_out.json").write_text(json.dumps(out, ensure_ascii=False, indent=1),
                                              encoding="utf-8")
    for r in out:
        print(f"\n--- {r['model']} ---\n{r['sample'][:300]}")


main()
