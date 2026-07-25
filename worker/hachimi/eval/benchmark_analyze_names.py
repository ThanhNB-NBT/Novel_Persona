"""Chọn model cho việc DUY NHẤT còn cần LLM ở nhánh Hachimi: trích tên riêng.

Không phải bài dịch — bài này chấm: JSON có hợp lệ không, bắt được bao nhiêu tên, có
đúng mấy ca đã biết đáp án không (tên Trung → Hán-Việt, tên Tây → chữ Latin), và mất
bao lâu. Dùng đúng `prompts.SYSTEM_ANALYZE` và đúng cách gọi của `worker._analyze_names`.

    python benchmark_analyze_names.py --chapters 6
"""
from __future__ import annotations

import argparse
import json
import time
from collections import defaultdict
from pathlib import Path

from openai import OpenAI

from novelworker.config import settings
from novelworker.translator import prompts
from novelworker.translator.text_clean import clean_source
from novelworker.translator.worker import CHUNK_LIMIT, _extract_json


BASE_URL = "https://integrate.api.nvidia.com/v1"
CORPUS = Path(__file__).with_name("hachimi_base_longform.jsonl")
OUTPUT_MD = Path(__file__).with_name("benchmark_analyze_names.md")
CANDIDATES = [
    "mistralai/mistral-small-4-119b-2603",   # đang dùng, làm mốc
    "qwen/qwen3-next-80b-a3b-instruct",
    "meta/llama-4-maverick-17b-128e-instruct",
    "google/gemma-4-31b-it",
    "nvidia/nemotron-3-super-120b-a12b",
]
# Đáp án đã biết (đối chiếu tay từ glossary đã duyệt + gu đã chốt).
EXPECTED = {
    "龙傲天": "Long Ngạo Thiên",
    "玛利亚": "Maria",          # tên Tây → giữ Latin
    "埃尔顿": "Elton",
    "龙明": "Long Minh",
    "华凝霜": "Hoa Ngưng Sương",
}


def analyze(client: OpenAI, model: str, chunk: str) -> tuple[list[dict], float, bool]:
    started = time.perf_counter()
    response = client.chat.completions.create(
        model=model, temperature=0.3, max_tokens=1536,
        messages=[{"role": "system", "content": prompts.SYSTEM_ANALYZE},
                  {"role": "user", "content": chunk}],
    )
    seconds = time.perf_counter() - started
    data = _extract_json(response.choices[0].message.content or "")
    if isinstance(data, list):
        return data, seconds, True
    if isinstance(data, dict) and isinstance(data.get("terms"), list):
        return data["terms"], seconds, True
    return [], seconds, False


def main(chapter_count: int) -> None:
    corpus = [json.loads(line) for line in CORPUS.read_text(encoding="utf-8").splitlines() if line.strip()]
    # Truyện 32 có cả tên Trung lẫn tên Tây → đúng chỗ cần phân biệt.
    chapters = [row for row in corpus if row["novel_id"] == 32][:chapter_count]
    chunks = [clean_source(row["source_zh"])[:CHUNK_LIMIT] for row in chapters]
    client = OpenAI(base_url=BASE_URL, api_key=settings.nvidia_keys[-1], timeout=180, max_retries=1)
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    found: dict[str, dict[str, str]] = defaultdict(dict)
    for model in CANDIDATES:
        for index, chunk in enumerate(chunks, start=1):
            try:
                terms, seconds, ok = analyze(client, model, chunk)
            except Exception as error:  # noqa: BLE001
                summary[model]["fail"] += 1
                print(f"  [{model}] chương {index} LỖI {type(error).__name__}", flush=True)
                continue
            summary[model]["seconds"] += seconds
            summary[model]["done"] += 1
            summary[model]["json_ok"] += ok
            summary[model]["terms"] += len(terms)
            for term in terms:
                if isinstance(term, dict) and term.get("zh") in EXPECTED:
                    found[model].setdefault(term["zh"], str(term.get("vi") or ""))
            print(f"  [{model}] chương {index}: {len(terms)} term, {seconds:.1f}s", flush=True)
    lines = [
        f"# Chọn model trích tên riêng — {len(chunks)} chương truyện 32",
        "",
        "Bài này KHÔNG chấm dịch: nhánh Hachimi chỉ còn dùng LLM để liệt kê tên cho glossary.",
        "",
        "| Model | JSON hợp lệ | Term/chương | Đúng đáp án | Giây/chương | Hỏng |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for model in CANDIDATES:
        item = summary[model]
        done = int(item["done"]) or 1
        hits = sum(1 for zh, vi in found[model].items() if vi.strip().lower() == EXPECTED[zh].lower())
        lines.append(
            f"| `{model}` | {int(item['json_ok'])}/{done} | {item['terms'] / done:.0f} | "
            f"{hits}/{len(EXPECTED)} | {item['seconds'] / done:.1f} | {int(item['fail'])} |"
        )
    lines += ["", "## Từng đáp án", "", "| Chữ Trung | Mong đợi | " + " | ".join(m.split("/")[-1] for m in CANDIDATES) + " |",
              "|---|---|" + "---|" * len(CANDIDATES)]
    for zh, expect in EXPECTED.items():
        cells = [found[model].get(zh, "—") for model in CANDIDATES]
        lines.append(f"| {zh} | {expect} | " + " | ".join(cells) + " |")
    OUTPUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    print(f"Đã ghi {OUTPUT_MD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--chapters", type=int, default=6)
    main(parser.parse_args().chapters)
