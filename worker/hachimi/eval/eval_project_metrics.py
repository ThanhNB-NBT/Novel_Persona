"""Chấm model bằng THƯỚC CỦA DỰ ÁN trên bộ chương sạch — nhận model tuỳ ý để so v5 vs v6.

Vì sao không dùng chrF: nó chấm độ trùng với gu của MỘT dịch giả cụ thể nên phạt model có
gu riêng (đo 29/08: model gốc chưa finetune còn hơn v5 về chrF, nhưng thua ở mọi thước của
dự án). Ở đây đo đúng thứ dự án tune: đại từ hiện đại, lint, bịa chủ ngữ.

    python eval_project_metrics.py clean_testset.jsonl <model_a> [<model_b> ...]
"""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

import ctranslate2
import sentencepiece as spm

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from novelworker.translator import lint                     # noqa: E402
from novelworker.translator.hachimi_engine import _invents_subject  # noqa: E402

EOS = "</s>"
SENT = re.compile(r"[^。！？!?；;]*[。！？!?；;]|[^。！？!?；;]+")
MODERN = re.compile(r"\b(tôi|anh ấy|cô ấy|anh ta|cô ta|cậu ấy|mày|tao)\b", re.I)
HAN = re.compile(r"[一-鿿]")


def run(model: str, rows: list[dict], beam: int = 6) -> dict:
    src, tgt = spm.SentencePieceProcessor(), spm.SentencePieceProcessor()
    src.load(f"{model}/source.spm"); tgt.load(f"{model}/target.spm")
    tr = ctranslate2.Translator(model, device="cpu", compute_type="int8", intra_threads=8)
    n_sent = invents = modern = han = lint_hits = 0
    t0 = time.time()
    for r in rows:
        units = [m.group(0).strip() for line in r["zh"].split("\n") if line.strip()
                 for m in SENT.finditer(line) if m.group(0).strip()]
        res = tr.translate_batch([src.encode(u, out_type=str)[:110] + [EOS] for u in units],
                                 beam_size=beam, max_decoding_length=256, max_batch_size=8,
                                 repetition_penalty=1.1, no_repeat_ngram_size=4)
        pairs = [(u, tgt.decode([t for t in x.hypotheses[0] if t != EOS]))
                 for u, x in zip(units, res)]
        vi = " ".join(v for _, v in pairs)
        n_sent += len(pairs)
        invents += sum(1 for zh, v in pairs if _invents_subject(zh, v))
        modern += len(MODERN.findall(vi))
        han += len(HAN.findall(vi))
        lint_hits += lint.lint_score(None, vi)
    n = len(rows) or 1
    return {"model": Path(model).name, "chương": n, "câu": n_sent,
            "bịa chủ ngữ/100 câu": round(invents / max(1, n_sent) * 100, 2),
            "đại từ hiện đại/chương": round(modern / n, 2),
            "Hán sót/chương": round(han / n, 2),
            "lint/chương": round(lint_hits / n, 2),
            "giây/chương": round((time.time() - t0) / n, 1)}


def main() -> None:
    data = Path(sys.argv[1])
    rows = [json.loads(l) for l in data.read_text(encoding="utf-8").splitlines() if l.strip()]
    out = [run(m, rows) for m in sys.argv[2:]]
    keys = [k for k in out[0] if k not in ("model", "chương", "câu")]
    print(f"{'model':22s} " + " ".join(f"{k:>22s}" for k in keys))
    for r in out:
        print(f"{r['model']:22s} " + " ".join(f"{r[k]:22.2f}" for k in keys))
    print(f"\n({out[0]['chương']} chương · {out[0]['câu']} câu)")


if __name__ == "__main__":
    main()
