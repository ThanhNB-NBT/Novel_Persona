"""Chạy một model trên bộ 36 chương thật, N làn song song, ghi jsonl để chấm."""
import json, sys, threading, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from openai import OpenAI
from novelworker.config import settings
from novelworker.translator import prompts

HERE = Path(__file__).parent
MODEL = sys.argv[1] if len(sys.argv) > 1 else "google/gemma-4-31b-it"
LANES = int(sys.argv[2]) if len(sys.argv) > 2 else 4
OUT = HERE / (sys.argv[3] if len(sys.argv) > 3 else "big_out.jsonl")
EXTRA = json.loads(sys.argv[4]) if len(sys.argv) > 4 else None

rows = [json.loads(l) for l in (HERE / "chapters_big.jsonl").open(encoding="utf-8")]
done = set()
if OUT.exists():
    done = {(json.loads(l)["novel_id"], json.loads(l)["chapter_index"])
            for l in OUT.open(encoding="utf-8")}
todo = [r for r in rows if (r["novel_id"], r["chapter_index"]) not in done]
keys = settings.nvidia_keys
system = prompts.build_main_chapter_system()
lock = threading.Lock()
print(f"{MODEL} · {len(todo)}/{len(rows)} chương còn lại · {LANES} làn", flush=True)

def one(item):
    i, row = item
    cli = OpenAI(base_url="https://integrate.api.nvidia.com/v1", api_key=keys[i % len(keys)],
                 timeout=600, max_retries=0)
    t = time.time()
    try:
        r = cli.chat.completions.create(
            model=MODEL, temperature=prompts.CHAPTER_TEMPERATURE, max_tokens=16384,
            messages=[{"role": "system", "content": system},
                      {"role": "user", "content": prompts.build_chapter_user(
                          row["chapter_title_zh"], row["source_zh"])}],
            extra_body=EXTRA)
        dt = time.time() - t
        rec = {"model": MODEL, "novel_id": row["novel_id"], "chapter_index": row["chapter_index"],
               "sec": round(dt, 1), "finish": r.choices[0].finish_reason,
               "out_tok": r.usage.completion_tokens if r.usage else 0,
               "tok_s": round((r.usage.completion_tokens if r.usage else 0) / dt, 1),
               "vi": r.choices[0].message.content or ""}
        msg = (f"nv{row['novel_id']} ch{row['chapter_index']} {rec['sec']:6.1f}s "
               f"{rec['finish']} {len(rec['vi']):6d} chars")
    except Exception as e:
        rec = {"model": MODEL, "novel_id": row["novel_id"], "chapter_index": row["chapter_index"],
               "error": str(e)[:200]}
        msg = f"nv{row['novel_id']} ch{row['chapter_index']} LỖI {str(e)[:110]}"
    with lock:
        with OUT.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        print(msg, flush=True)
    return rec

t0 = time.time()
with ThreadPoolExecutor(LANES) as ex:
    list(ex.map(one, enumerate(todo)))
print(f"XONG {len(todo)} chương trong {time.time()-t0:.0f}s "
      f"→ {(time.time()-t0)/max(1,len(todo)):.1f}s/chương hiệu dụng", flush=True)
