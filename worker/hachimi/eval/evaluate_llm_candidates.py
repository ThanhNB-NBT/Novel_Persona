"""So model LLM lớn (qua NVIDIA NIM) với Hachimi trên ĐÚNG 60 cảnh khoá.

Vòng v4 cho thấy đổ thêm data không còn ăn — trần nằm ở model 57M. Trước khi kết luận
"hết cách", đo thử các model lớn sẵn có trên NIM bằng cùng thước đo, cùng hậu xử lý và
cùng termguard/glossary như Hachimi, để biết đổi model có đáng không.

Không ghi DB. Mỗi model chạy tuần tự, có đo giây và token thật.
"""
from __future__ import annotations

import argparse
import json
import time
from collections import defaultdict
from pathlib import Path

from openai import OpenAI

from novelworker.config import settings
from novelworker.translator import termguard
from novelworker.translator.text_clean import clean_source
from novelworker.translator.worker import _clean_output, _fix_register, _fix_soft_style, _hanviet_fallback

from audit_hachimi_base_longform import metrics
from eval_common import EVAL, balanced_quotes, production_terms, similarity
from evaluate_hachimi_teacher_v2 import sentences

BASE_URL = "https://integrate.api.nvidia.com/v1"
CANDIDATES = [
    "qwen/qwen3-next-80b-a3b-instruct",
    "deepseek-ai/deepseek-v4-flash",
    "z-ai/glm-5.2",
    "nvidia/riva-translate-4b-instruct",
]
SYSTEM = (
    "Bạn là dịch giả truyện mạng Trung → Việt, văn phong tiên hiệp/huyền huyễn.\n"
    "LUẬT BẮT BUỘC:\n"
    "- Lời kể ngôi ba: nam = 'hắn', nữ = 'nàng'; ngôi nhất = 'ta'. Đối thoại xưng 'ta', gọi 'ngươi'.\n"
    "  TUYỆT ĐỐI KHÔNG dùng: tôi, mình, bạn, cậu, cháu, anh ta, cô ta, cô ấy, ông ta, bà ta.\n"
    "- Danh xưng thân tộc theo lối cổ: ca ca, tỷ tỷ, muội muội, đệ đệ.\n"
    "- Giữ nguyên mọi con số. Tên riêng Trung dùng âm Hán-Việt; tên phương Tây giữ chữ Latin.\n"
    "- Ngắt câu theo nhịp tiếng Việt: một câu Trung dài nhiều dấu phẩy nên tách thành 2 câu Việt.\n"
    "- Chỉ trả về bản dịch, không giải thích, không thêm tiêu đề."
)
OUTPUT_MD = Path(__file__).with_name("hachimi_vs_llm_candidates.md")
OUTPUT_JSONL = Path(__file__).with_name("hachimi_vs_llm_candidates.jsonl")


def post_process(vi: str) -> str:
    vi = _clean_output(vi)
    vi, _ = _hanviet_fallback(vi)
    return _fix_register(_fix_soft_style(vi))


def translate(client: OpenAI, model: str, source: str, terms: list[dict]) -> tuple[str, int, int]:
    """Gọi thẳng NIM, KHÔNG qua TranslationProvider: bộ pacing của nó dùng chung nhịp với
    worker production nên chạy đo cục bộ sẽ bị xếp hàng vô thời hạn."""
    used = {"prompt": 0, "completion": 0}

    def call(text: str) -> str:
        response = client.chat.completions.create(
            model=model, temperature=0.3, max_tokens=4096,
            messages=[{"role": "system", "content": SYSTEM}, {"role": "user", "content": text}],
        )
        usage = response.usage
        used["prompt"] += usage.prompt_tokens if usage else 0
        used["completion"] += usage.completion_tokens if usage else 0
        result = type("R", (), {"text": response.choices[0].message.content or ""})
        # Model lớn hay trả thừa dòng trắng — termguard đòi số dòng khớp nguồn.
        lines = [line for line in result.text.split("\n") if line.strip()]
        want = len([line for line in text.split("\n") if line.strip()])
        return "\n".join(lines[:want] if len(lines) >= want else lines + [""] * (want - len(lines)))

    vi = termguard.translate_text(source, terms, call)
    return post_process(vi), used["prompt"], used["completion"]


def main(limit: int) -> None:
    rows = [json.loads(line) for line in EVAL.read_text(encoding="utf-8").splitlines() if line.strip()][:limit]
    terms = {novel_id: production_terms(novel_id) for novel_id in {row["novel_id"] for row in rows}}
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    results = []
    # Dùng key CUỐI trong danh sách: key đầu là lane của worker production.
    client = OpenAI(base_url=BASE_URL, api_key=settings.nvidia_keys[-1], timeout=180, max_retries=1)
    for model in CANDIDATES:
        for index, row in enumerate(rows, start=1):
            source = clean_source(row["zh"])
            started = time.perf_counter()
            try:
                vi, prompt_tokens, completion_tokens = translate(client, model, source, terms[row["novel_id"]])
            except Exception as error:  # noqa: BLE001 — model lỗi thì ghi nhận rồi chạy tiếp
                print(f"  [{model}] cảnh {index} LỖI: {str(error)[:120]}", flush=True)
                summary[model]["fail"] += 1
                continue
            counts = metrics(source, vi, vi)
            item = {
                "model": model, "eval_category": row["eval_category"], "pipeline": vi,
                "similarity": round(similarity(row["reference_vi"], vi), 4),
                "sentences": sentences(vi),
                "han": counts["pipeline_han"],
                "modern_pronouns": counts["pipeline_modern_pronouns"],
                "quotes_balanced": balanced_quotes(vi),
                "seconds": round(time.perf_counter() - started, 2),
                "tokens": prompt_tokens + completion_tokens,
            }
            results.append({**row, "source_clean": source, "output": item})
            for key in ("similarity", "sentences", "han", "modern_pronouns", "seconds", "tokens"):
                summary[model][key] += item[key]
            summary[model]["quote_fail"] += not item["quotes_balanced"]
            print(f"  [{model}] {index}/{len(rows)} {item['seconds']}s", flush=True)
    OUTPUT_JSONL.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in results), encoding="utf-8")
    lines = [
        f"# Model lớn trên NIM so với Hachimi — {len(rows)} cảnh khoá",
        "",
        "> Cùng tập eval, cùng termguard/glossary production, cùng hậu xử lý. Mốc Hachimi lấy từ",
        "> `hachimi_eval_locked.md` (teacher_v4: similarity 0,7246 · câu/cảnh 3,4 · đại từ 14 · quote lỗi 2).",
        "",
        "| Model | Similarity TB | Câu/cảnh | Hán sót | Đại từ hiện đại | Quote lỗi | Giây/cảnh | Token/cảnh | Lỗi gọi |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for model in CANDIDATES:
        item = summary[model]
        done = max(1, len(rows) - int(item["fail"]))
        lines.append(
            f"| `{model}` | {item['similarity'] / done:.4f} | {item['sentences'] / done:.1f} | "
            f"{int(item['han'])} | {int(item['modern_pronouns'])} | {int(item['quote_fail'])} | "
            f"{item['seconds'] / done:.1f} | {int(item['tokens'] / done)} | {int(item['fail'])} |"
        )
    for row in results:
        item = row["output"]
        lines.extend(["", f"## {item['model']} — {row['eval_category']}", "",
                      f"- ZH: {row['source_clean'][:400]}",
                      f"- Tham chiếu: {row['reference_vi'][:400]}",
                      f"- Bản dịch: {item['pipeline'][:400]}"])
    OUTPUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines[:12]))
    print(f"Đã ghi {OUTPUT_MD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=20, help="số cảnh mỗi model (60 = cả tập)")
    main(parser.parse_args().limit)
