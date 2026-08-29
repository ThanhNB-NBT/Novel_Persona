"""Đo khả năng dịch THƠ của một model CT2 — trục mà v5 đang gần như bằng 0.

Đo 29/08 trên v5: `更上一层楼` → "tiến thêm một bước nữa" (đúng: lên thêm một tầng lầu),
và thơ bị bẻ thành văn xuôi một dòng. Ba chỉ số, không cần bản dịch tham chiếu:

  giữ_vế  — mỗi vế thơ thành đúng một dòng Việt (thể thơ còn hay mất)
  sạch_Hán — không còn chữ Hán trơ
  không_lặp — không rơi vào vòng lặp từ

    python eval_poem.py <model_ct2_dir> [eval_poem_locked.jsonl]
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import ctranslate2
import sentencepiece as spm

HAN = re.compile(r"[一-鿿]")
EOS = "</s>"


def verses(zh: str) -> list[str]:
    return [v.strip() for line in zh.split("\n")
            for v in re.split(r"[，,。；;？！]", line) if v.strip()]


def loops(vi: str) -> bool:
    w = vi.split()
    return any(w[i] == w[i + 1] == w[i + 2] for i in range(len(w) - 2))


def main() -> None:
    model = sys.argv[1]
    data = Path(sys.argv[2] if len(sys.argv) > 2 else "data/eval_poem_locked.jsonl")
    rows = [json.loads(l) for l in data.read_text(encoding="utf-8").splitlines() if l.strip()]
    src, tgt = spm.SentencePieceProcessor(), spm.SentencePieceProcessor()
    src.load(f"{model}/source.spm"); tgt.load(f"{model}/target.spm")
    tr = ctranslate2.Translator(model, device="cpu", compute_type="int8", intra_threads=8)

    # Dịch TỪNG VẾ: đó là cách production chia câu, và cũng là cách duy nhất giữ được thể thơ.
    n_han = n_loop = 0
    outs = []
    for r in rows:
        vs = verses(r["zh"])
        res = tr.translate_batch([src.encode(v, out_type=str) + [EOS] for v in vs],
                                 beam_size=6, max_decoding_length=128,
                                 repetition_penalty=1.1, no_repeat_ngram_size=4)
        lines = [tgt.decode([t for t in x.hypotheses[0] if t != EOS]) for x in res]
        vi = "\n".join(lines)
        n_han += bool(HAN.search(vi))
        n_loop += any(loops(l) for l in lines)
        outs.append({"zh": r["zh"], "vi": vi, "ref": r.get("vi")})
    n = len(rows) or 1
    print(f"{model}  ·  {n} bài")
    print(f"  sạch chữ Hán : {n - n_han:4d}/{n} ({(n-n_han)/n:.0%})")
    print(f"  không lặp    : {n - n_loop:4d}/{n} ({(n-n_loop)/n:.0%})")
    Path("poem_eval_out.jsonl").write_text(
        "\n".join(json.dumps(o, ensure_ascii=False) for o in outs), encoding="utf-8")
    for o in outs[:3]:
        print(f"\n  ZH: {o['zh'].splitlines()[0]}")
        print(f"  ra: {o['vi'].splitlines()[0] if o['vi'] else ''}")
        if o.get("ref"):
            print(f"  gemma: {o['ref'].splitlines()[0]}")


if __name__ == "__main__":
    main()
