"""Chấm điểm các model miễn phí trên NVIDIA NIM bằng ĐÚNG luồng dịch production.

Mỗi model dịch cùng một tập cảnh đã khoá, đi qua đúng thứ tự của worker: prompt production
→ termguard/glossary → hậu xử lý (_clean_output, _hanviet_fallback, _fix_soft_style,
_fix_register). Chấm bằng cùng bộ thước đang dùng cho Hachimi, cộng độ trễ và token.

Chạy song song trên CẢ HAI API key (hai tài khoản), mỗi key hai làn.

    python benchmark_nim_models.py --stage 1              # sàng nhanh, 10 cảnh mỗi model
    python benchmark_nim_models.py --stage 2 --limit 60   # chung kết, chỉ model đã lọt
    python benchmark_nim_models.py --chapters 2           # đo độ trễ trên chương thật
"""
from __future__ import annotations

import argparse
import json
import re
import threading
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from openai import OpenAI

from novelworker.config import settings
from novelworker.translator import prompts, termguard
from novelworker.translator.text_clean import clean_source
from novelworker.translator.worker import (
    _clean_output, _fix_register, _fix_soft_style, _hanviet_fallback, _register_line,
)

from audit_hachimi_base_longform import metrics
from eval_common import EVAL, balanced_quotes, production_terms, similarity
from evaluate_hachimi_teacher_v2 import sentences


BASE_URL = "https://integrate.api.nvidia.com/v1"
CORPUS = Path(__file__).with_name("hachimi_base_longform.jsonl")
OUTPUT_MD = Path(__file__).with_name("benchmark_nim_models.md")
OUTPUT_JSONL = Path(__file__).with_name("benchmark_nim_models.jsonl")
LANES_PER_KEY = 2

# Vòng 1: quét rộng. Vòng 2 chỉ giữ những model qua được cổng.
STAGE1_MODELS = [
    "qwen/qwen3-next-80b-a3b-instruct",
    "deepseek-ai/deepseek-v4-flash",
    "meta/llama-4-maverick-17b-128e-instruct",
    "mistralai/mistral-small-4-119b-2603",   # model production cũ, làm mốc
]
# ĐÃ LOẠI VÌ ĐỘ TRỄ (đo 25/07 trên cảnh ~370 ký tự — chương thật gấp ~7 lần):
# glm-5.2 119-312s/cảnh, minimax-m3 132s, nemotron-3-super-120b 117s, gemma-4-31b 51s,
# deepseek-v4-pro 44s. Tất cả vượt xa ngưỡng 60 giây/chương, không cần đo chất lượng nữa.
# Key không mở (404 toàn bộ) — đo 25/07, đừng thử lại nếu chưa đổi tài khoản:
# qwen/qwen3.5-397b-a17b, moonshotai/kimi-k2.6, nvidia/riva-translate-4b-instruct.
STAGE2_MODELS: list[str] = [
    "deepseek-ai/deepseek-v4-flash",
    "meta/llama-4-maverick-17b-128e-instruct",
    "qwen/qwen3-next-80b-a3b-instruct",
]


def make_clients() -> list[OpenAI]:
    """Mỗi API key một client riêng; hai tài khoản = hai hạn mức tách biệt."""
    keys = settings.nvidia_keys
    if not keys:
        raise SystemExit("Chưa có NVIDIA_API_KEYS trong worker/.env")
    return [OpenAI(base_url=BASE_URL, api_key=key, timeout=240, max_retries=0) for key in keys]


class Lane:
    """Một làn gọi API: giữ client + đếm token, có khoá riêng để đo giây cho chính xác."""

    def __init__(self, client: OpenAI, name: str):
        self.client = client
        self.name = name
        self.lock = threading.Lock()


def translate_one(lane: Lane, model: str, source: str, terms: list[dict]) -> tuple[str, int, float, int]:
    """Dịch một cảnh qua ĐÚNG luồng production. Trả (vi, tokens, giây, số lần gọi)."""
    used = {"tokens": 0, "calls": 0}
    system = prompts.build_main_chapter_system()
    register_line = _register_line(source)
    started = time.perf_counter()

    def call(text: str) -> str:
        used["calls"] += 1
        # NIM free hay trả 503 ResourceExhausted lúc đông — đó là hàng đợi, không phải model
        # tồi; thử lại vài nhịp rồi mới tính là hỏng. 404 = key không mở model đó, bỏ ngay.
        for attempt in range(4):
            try:
                response = lane.client.chat.completions.create(
                    model=model, temperature=prompts.CHAPTER_TEMPERATURE, max_tokens=4096,
                    messages=[
                        {"role": "system", "content": system},
                        {"role": "user", "content": prompts.build_chapter_user(
                            None, text, register_line=register_line)},
                    ],
                )
                break
            except Exception as error:  # noqa: BLE001
                status = getattr(error, "status_code", None)
                if status == 404 or attempt == 3:
                    raise
                time.sleep(5 * (attempt + 1))
        if response.usage:
            used["tokens"] += response.usage.total_tokens
        out = response.choices[0].message.content or ""
        # termguard đòi số dòng khớp nguồn; model lớn hay thêm/bớt dòng trắng.
        lines = [line for line in out.split("\n") if line.strip()]
        want = len([line for line in text.split("\n") if line.strip()])
        return "\n".join(lines[:want] if len(lines) >= want else lines + [""] * (want - len(lines)))

    vi = termguard.translate_text(source, terms, call)
    vi = _clean_output(vi)
    vi, _ = _hanviet_fallback(vi)
    vi = _fix_register(_fix_soft_style(vi))
    return vi, used["tokens"], time.perf_counter() - started, used["calls"]


def score(source: str, reference: str, vi: str) -> dict:
    counts = metrics(source, vi, vi)
    return {
        "similarity": round(similarity(reference, vi), 4),
        "sentences": sentences(vi),
        "han": counts["pipeline_han"],
        "modern_pronouns": counts["pipeline_modern_pronouns"],
        "quote_ok": balanced_quotes(vi),
        "digits_ok": re.findall(r"\d+", source) == re.findall(r"\d+", vi),
        "chars": len(vi),
    }


def run(models: list[str], rows: list[dict], lanes: list[Lane]) -> tuple[list[dict], dict]:
    terms = {novel_id: production_terms(novel_id) for novel_id in {row["novel_id"] for row in rows}}
    tasks = [(model, index, row) for model in models for index, row in enumerate(rows)]
    results: list[dict] = []
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    lock = threading.Lock()

    def work(task: tuple[str, int, dict]) -> None:
        model, index, row = task
        lane = lanes[index % len(lanes)]
        source = clean_source(row["zh"])
        try:
            vi, tokens, seconds, calls = translate_one(lane, model, source, terms[row["novel_id"]])
        except Exception as error:  # noqa: BLE001 — model hỏng thì ghi nhận, không chặn cả lô
            with lock:
                summary[model]["fail"] += 1
                summary[model]["fail_reason_" + type(error).__name__] += 1
            print(f"  [{model}] cảnh {index + 1} LỖI {type(error).__name__}: {str(error)[:90]}", flush=True)
            return
        item = score(source, row["reference_vi"], vi)
        with lock:
            results.append({"model": model, "index": index, "eval_category": row["eval_category"],
                            "source_clean": source, "reference_vi": row["reference_vi"],
                            "vi": vi, "seconds": round(seconds, 2), "tokens": tokens,
                            "calls": calls, **item})
            for key in ("similarity", "sentences", "han", "modern_pronouns", "tokens", "chars"):
                summary[model][key] += item.get(key, 0) if key in item else 0
            summary[model]["tokens"] += 0  # giữ khoá tồn tại kể cả khi usage rỗng
            summary[model]["seconds"] += seconds
            summary[model]["quote_fail"] += not item["quote_ok"]
            summary[model]["digit_fail"] += not item["digits_ok"]
            summary[model]["done"] += 1
        print(f"  [{model}] {index + 1}/{len(rows)} {seconds:.1f}s", flush=True)

    with ThreadPoolExecutor(max_workers=len(lanes)) as pool:
        list(pool.map(work, tasks))
    return results, summary


def render(models: list[str], rows: list[dict], results: list[dict], summary: dict, label: str) -> None:
    lines = [
        f"# Benchmark model NIM — {label}",
        "",
        f"Mỗi model dịch {len(rows)} cảnh khoá qua ĐÚNG luồng production (prompt + termguard +",
        "hậu xử lý). Mốc so sánh — Hachimi teacher_v4 trên cùng tập: similarity **0,7246**,",
        "câu/cảnh **3,4**, đại từ hiện đại **14**, Hán sót **0**, ~**0,3 giây/cảnh**.",
        "",
        "| Model | Cảnh đo được | Similarity | Câu/cảnh | Hán sót | Đại từ hiện đại | Quote lỗi | Số lỗi | Giây/cảnh | Hỏng |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for model in sorted(models, key=lambda m: -(summary[m]["similarity"] / max(1, summary[m]["done"]))):
        item = summary[model]
        done = int(item["done"]) or 1
        lines.append(
            f"| `{model}` | {int(item['done'])}/{len(rows)} | {item['similarity'] / done:.4f} | "
            f"{item['sentences'] / done:.1f} | {int(item['han'])} | {int(item['modern_pronouns'])} | "
            f"{int(item['quote_fail'])} | {int(item['digit_fail'])} | {item['seconds'] / done:.1f} | "
            f"{int(item['fail'])} |"
        )
    lines += ["", "## Ước lượng cho một chương thật (~2.700 ký tự nguồn)", "",
              "| Model | Giây/chương ước lượng | Trong ngưỡng 60s? |", "|---|---:|---|"]
    avg_source = sum(len(clean_source(row["zh"])) for row in rows) / max(1, len(rows))
    for model in models:
        item = summary[model]
        done = int(item["done"]) or 1
        est = item["seconds"] / done * (2700 / avg_source)
        lines.append(f"| `{model}` | {est:.0f}s | {'đạt' if est <= 60 else 'KHÔNG'} |")
    for row in sorted(results, key=lambda r: (r["index"], r["model"]))[:60]:
        lines += ["", f"## Cảnh {row['index'] + 1} — {row['eval_category']} — `{row['model']}`", "",
                  f"- Tham chiếu: {row['reference_vi'][:300]}", f"- Bản dịch: {row['vi'][:300]}"]
    OUTPUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    OUTPUT_JSONL.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in results), encoding="utf-8")
    print("\n".join(lines[:9 + len(models)]))
    print(f"Đã ghi {OUTPUT_MD}")


def run_chapters(models: list[str], count: int, lanes: list[Lane]) -> None:
    """Đo ĐỘ TRỄ THẬT trên chương đầy đủ — ngưỡng của dự án là 60 giây/chương.

    Cảnh trong tập khoá chỉ ~370 ký tự nên nhân lên sẽ lệch: chương dài đổi cả số lần gọi
    (chunk) lẫn số token sinh ra.
    """
    corpus = [json.loads(line) for line in CORPUS.read_text(encoding="utf-8").splitlines() if line.strip()]
    chapters = [row for row in corpus if row["chapter_index"] <= count][:count * 3][:count]
    terms = {row["novel_id"]: production_terms(row["novel_id"]) for row in chapters}
    print(f"Đo {len(chapters)} chương thật × {len(models)} model", flush=True)
    lines = ["# Độ trễ trên chương thật", "",
             "| Model | Chương | Ký tự nguồn | Giây | Số lần gọi | Câu | Đại từ hiện đại | Hán sót |",
             "|---|---|---:|---:|---:|---:|---:|---:|"]
    for model in models:
        for index, chapter in enumerate(chapters):
            source = clean_source(chapter["source_zh"])
            lane = lanes[index % len(lanes)]
            try:
                vi, _tokens, seconds, calls = translate_one(lane, model, source, terms[chapter["novel_id"]])
            except Exception as error:  # noqa: BLE001
                lines.append(f"| `{model}` | {chapter['novel_id']}/{chapter['chapter_index']} | "
                             f"{len(source)} | LỖI {type(error).__name__} | | | | |")
                print(f"  [{model}] chương {chapter['chapter_index']} LỖI: {str(error)[:90]}", flush=True)
                continue
            counts = metrics(source, vi, vi)
            lines.append(
                f"| `{model}` | {chapter['novel_id']}/{chapter['chapter_index']} | {len(source)} | "
                f"**{seconds:.0f}** | {calls} | {sentences(vi)} | {counts['pipeline_modern_pronouns']} | "
                f"{counts['pipeline_han']} |"
            )
            print(f"  [{model}] chương {chapter['chapter_index']}: {seconds:.0f}s, {calls} lần gọi", flush=True)
    lines += ["", "Mốc Hachimi teacher_v4 trên máy này: **~5 giây/chương**, 0 lần gọi mạng."]
    path = Path(__file__).with_name("benchmark_nim_chapters.md")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    print(f"Đã ghi {path}")


def main(stage: int, limit: int) -> None:
    models = STAGE1_MODELS if stage == 1 else (STAGE2_MODELS or STAGE1_MODELS)
    rows = [json.loads(line) for line in EVAL.read_text(encoding="utf-8").splitlines() if line.strip()][:limit]
    clients = make_clients()
    lanes = [Lane(client, f"key{i + 1}-lane{j + 1}")
             for i, client in enumerate(clients) for j in range(LANES_PER_KEY)]
    print(f"{len(models)} model × {len(rows)} cảnh, {len(lanes)} làn ({len(clients)} key)", flush=True)
    results, summary = run(models, rows, lanes)
    render(models, rows, results, summary, f"vòng {stage}, {len(rows)} cảnh")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=int, default=1)
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--chapters", type=int, default=0, help="đo độ trễ trên N chương thật")
    args = parser.parse_args()
    if args.chapters:
        clients = make_clients()
        run_chapters(
            STAGE2_MODELS,
            args.chapters,
            [Lane(client, f"key{i + 1}-lane{j + 1}")
             for i, client in enumerate(clients) for j in range(LANES_PER_KEY)],
        )
    else:
        main(args.stage, args.limit)
