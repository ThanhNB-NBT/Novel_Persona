"""Vòng 2: đo lại các model reasoning với suy luận TẮT, trên chương thật.

Mỗi biến thể là một cách tắt suy luận khác nhau — NIM không thống nhất API.
"""
from __future__ import annotations
import argparse, json, time
from pathlib import Path
from openai import OpenAI
from novelworker.config import settings
from novelworker.translator import prompts

BASE = "https://integrate.api.nvidia.com/v1"
HERE = Path(__file__).parent

# (nhãn, model, system_prefix, extra_body)
VARIANTS = [
    ("lightning-nothink-kw", "nvidia/nemotron-3.5-lightning-30b-a3b", "",
     {"chat_template_kwargs": {"thinking": False}}),
    ("lightning-nothink-sys", "nvidia/nemotron-3.5-lightning-30b-a3b", "detailed thinking off\n", {}),
    ("super-nothink-kw", "nvidia/nemotron-3-super-120b-a12b", "",
     {"chat_template_kwargs": {"thinking": False}}),
    ("gptoss-low", "openai/gpt-oss-120b", "", {"reasoning_effort": "low"}),
    ("minimax-nothink", "minimaxai/minimax-m3", "", {"chat_template_kwargs": {"thinking": False}}),
    ("gemma4-31b", "google/gemma-4-31b-it", "", {}),
    ("palmyra-creative", "writer/palmyra-creative-122b", "", {}),
]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--chapters", type=int, default=1)
    ap.add_argument("--timeout", type=int, default=420)
    ap.add_argument("--out", default="bench_v2_out.jsonl")
    a = ap.parse_args()
    only = {x.strip() for x in a.only.split(",") if x.strip()}
    rows = [json.loads(l) for l in (HERE / "chapters.jsonl").open(encoding="utf-8")][:a.chapters]
    keys = settings.nvidia_keys
    out = HERE / a.out
    system_base = prompts.build_main_chapter_system()
    for i, (label, model, sys_prefix, extra) in enumerate(VARIANTS):
        if only and label not in only:
            continue
        for j, row in enumerate(rows):
            cli = OpenAI(base_url=BASE, api_key=keys[(i + j) % len(keys)],
                         timeout=a.timeout, max_retries=0)
            user = prompts.build_chapter_user(row["chapter_title_zh"], row["source_zh"],
                                              novel_line=row["title_vi"])
            t0 = time.time()
            try:
                r = cli.chat.completions.create(
                    model=model, temperature=prompts.CHAPTER_TEMPERATURE, max_tokens=16384,
                    messages=[{"role": "system", "content": sys_prefix + system_base},
                              {"role": "user", "content": user}],
                    extra_body=extra or None)
                dt = time.time() - t0
                u = r.usage
                vi = r.choices[0].message.content or ""
                rec = {"model": label, "real_model": model, "novel_id": row["novel_id"],
                       "chapter_index": row["chapter_index"], "sec": round(dt, 1),
                       "finish": r.choices[0].finish_reason,
                       "out_tok": u.completion_tokens if u else 0,
                       "tok_s": round((u.completion_tokens if u else 0) / dt, 1), "vi": vi}
                print(f"{label:24s} ch{row['chapter_index']} {rec['sec']:7.1f}s "
                      f"{rec['out_tok']:6d}tok {rec['tok_s']:6.1f}tok/s {rec['finish']} "
                      f"vi_chars={len(vi)}", flush=True)
            except Exception as e:
                rec = {"model": label, "real_model": model, "novel_id": row["novel_id"],
                       "chapter_index": row["chapter_index"], "error": str(e)[:300]}
                print(f"{label:24s} ch{row['chapter_index']} LỖI {str(e)[:150]}", flush=True)
            with out.open("a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")

main()
