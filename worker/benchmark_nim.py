"""Benchmark model NIM free cho dịch chương: latency, tốc độ token, độ sạch, tuân prompt.

Chạy thủ công khi muốn dò model mới xịn hơn (danh sách text-gen free:
https://build.nvidia.com/models — lọc chat/instruct, để ý model mới ra):

    PYTHONIOENCODING=utf-8 ../.venv/Scripts/python.exe benchmark_nim.py
    ... benchmark_nim.py --models qwen/qwen3-next-80b-a3b-instruct,mistralai/mistral-small-4-119b-2603
    ... benchmark_nim.py --runs 3          # chạy nhiều lượt lấy trung bình

Dùng ĐÚNG prompt dịch chương thật + chương thật trong DB → kết quả phản ánh production.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from openai import OpenAI

from eval_translation import lint, narrator_terms
from novelworker import db
from novelworker.config import settings
from novelworker.translator import prompts
from novelworker.translator.providers import TranslationProvider
from novelworker.translator.worker import (
    REGISTER_LINE, _strip_meta, han_ratio,
)

NVIDIA_BASE_URL = "https://integrate.api.nvidia.com/v1"
NVIDIA_PREVIEW_MODELS_URL = (
    "https://build.nvidia.com/models?"
    "filters=nimType%3Anim_type_preview&orderBy=weightPopular%3ADESC"
)
NVIDIA_CATALOG_SEARCH_URL = (
    "https://api.ngc.nvidia.com/v2/search/catalog/resources/ENDPOINT"
)

# Ứng viên mặc định: model đang dùng + vài model đáng theo dõi. Sửa thoải mái.
DEFAULT_MODELS = [
    settings.nvidia_model,
    "qwen/qwen3-next-80b-a3b-instruct",
]

QUALITY_CANDIDATES = [
    "mistralai/mistral-small-4-119b-2603",
    "nvidia/nemotron-3-super-120b-a12b", "meta/llama-3.3-70b-instruct",
    "qwen/qwen3.5-397b-a17b", "qwen/qwen3.5-122b-a10b",
    "qwen/qwen3-next-80b-a3b-instruct", "google/gemma-4-31b-it",
    "google/diffusiongemma-26b-a4b-it", "deepseek-ai/deepseek-v4-pro",
    "deepseek-ai/deepseek-v4-flash", "minimaxai/minimax-m3", "minimaxai/minimax-m2.7",
    "moonshotai/kimi-k2.6", "stepfun-ai/step-3.7-flash", "z-ai/glm-5.2",
    "mistralai/mistral-large-3-675b-instruct-2512", "mistralai/mistral-medium-3.5-128b",
    "meta/llama-4-maverick-17b-128e-instruct", "nvidia/riva-translate-4b-instruct-v1.1",
    "writer/palmyra-creative-122b",
]

# Mẫu tự tạo, không lấy từ truyện/DB: an toàn gửi nhiều model bên thứ ba và cố ý chứa
# các lỗi production đang gặp (tự xưng giàu sắc thái + đại từ người kể + nhiều nam cùng cảnh).
SYNTHETIC_QUALITY_SAMPLE = """山门前，白发老者负手而立。老人看了陆沉一眼，冷声说道：“老夫等了你三十年。”
陆沉没有回答。他身旁还站着师兄周岳，两人都穿着黑衣。周岳上前半步，低声提醒陆沉：“师弟，不可无礼。”
白发老者忽然大笑：“老子纵横天下的时候，你们的师父还只是个孩子！”
陆沉拱手道：“在下并非有意冒犯，只想知道前辈为何拦路。”
这时，红衣女子从殿后走来。她是陆沉的师姐苏晚晴。苏晚晴没有看周岳，只对陆沉说：“你随我进去。”
陆沉望向周岳，周岳却摇了摇头。若只用‘他’来指代二人，旁人根本分不清究竟是谁拒绝了谁。
白发老者收起笑容，自称本座，命令三人立刻离开。苏晚晴却称他为前辈，语气恭敬，眼神却十分冷淡。"""

_NON_TRANSLATION_MODEL_MARKERS = (
    "embed", "rerank", "retrieval", "guard", "safety", "moderation", "vision",
    "vlm", "image", "video", "audio", "speech", "code-embed",
)


def _catalog_url(page: int = 0, page_size: int = 100) -> str:
    query = {
        "query": "*:*",
        "page": page,
        "pageSize": page_size,
        "filters": [{"field": "nimType", "value": "nim_type_preview"}],
        "orderBy": [{"field": "weightPopular", "value": "DESC"}],
    }
    return NVIDIA_CATALOG_SEARCH_URL + "?" + urlencode({
        "q": json.dumps(query, separators=(",", ":")),
        "group-labels-by-labelset": "true",
    })


def _parse_preview_models(page: str) -> tuple[list[str], int]:
    """Đọc model theo thứ tự phổ biến từ API search mà trang NVIDIA sử dụng."""
    payload = json.loads(page)
    models: list[str] = []
    for group in payload.get("results", []):
        for resource in group.get("resources", []):
            display = resource.get("displayName")
            publisher = next((label.get("values", [""])[0]
                              for label in resource.get("labels", [])
                              if label.get("key") == "publisher" and label.get("values")), "")
            if display and publisher:
                model = f"{publisher}/{display}"
            elif display:
                model = display
            else:
                continue
            if model not in models:
                models.append(model)
    return models, int(payload.get("resultTotal", len(models)))


def preview_models() -> list[str]:
    """Quét toàn bộ model Free Endpoint từ đúng catalog NVIDIA."""
    page_size = 100
    models: list[str] = []
    page = 0
    while True:
        request = Request(_catalog_url(page, page_size))
        with urlopen(request, timeout=30) as response:
            found, total = _parse_preview_models(response.read().decode("utf-8"))
        models.extend(model for model in found if model not in models)
        if not found or len(models) >= total:
            return models
        page += 1


def _model_key(model: str) -> str:
    return re.sub(r"[^a-z0-9]", "", model.rsplit("/", 1)[-1].lower())


def available_models() -> list[str]:
    """Free Endpoint trong catalog mà ít nhất một NVIDIA key truy cập được."""
    catalog = preview_models()
    accessible: set[str] = set()
    errors: list[str] = []
    for slot, key in enumerate(settings.nvidia_keys):
        try:
            client = OpenAI(base_url=NVIDIA_BASE_URL, api_key=key)
            accessible.update(m.id for m in client.models.list().data)
        except Exception as exc:
            errors.append(f"key {slot + 1}: {exc}")
    if not accessible:
        raise RuntimeError("Không đọc được /v1/models: " + "; ".join(errors))

    by_normalized = {_model_key(model): model for model in accessible}
    return [by_normalized[_model_key(model)] for model in catalog
            if _model_key(model) in by_normalized]


def translation_candidates(models: list[str]) -> list[str]:
    """Bỏ model chắc chắn không phải text generation; lỗi API sẽ lọc nốt khi benchmark."""
    return [m for m in models if not any(x in m.lower() for x in _NON_TRANSLATION_MODEL_MARKERS)]


def fetch_sample(chars: int, novel_id: int | None = None, chapter_index: int = 1) -> str:
    """Lấy 1 chương thật (content_zh) trong DB làm đề bài."""
    q = db.sb().table("chapters").select("content_zh").not_.is_("content_zh", "null")
    if novel_id is not None:
        q = q.eq("novel_id", novel_id).eq("chapter_index", chapter_index)
    rows = q.limit(1).execute().data or []
    if not rows:
        raise SystemExit("DB không có chương nào còn content_zh — cần 1 chương mẫu")
    return rows[0]["content_zh"][:chars]


def bench_model(model: str, zh: str, runs: int, timeout_sec: int, key_offset: int = 0) -> dict:
    providers = [TranslationProvider(NVIDIA_BASE_URL, key, model, "nvidia",
                                     timeout_sec=timeout_sec)
                 for key in settings.nvidia_keys]
    system = prompts.build_main_chapter_system([], zh)
    user = prompts.build_chapter_user(
        "测试章节", zh, None, register_line=REGISTER_LINE)
    out = {"model": model, "ok": 0, "fail": 0, "lat": [], "tps": [], "han": [],
           "ratio": [], "problem_runs": 0, "problems": [], "narrator_terms": {},
           "key_slots": [], "key_stats": {}, "sample": "", "err": ""}
    for run in range(runs):
        slot = (key_offset + run) % len(providers)
        p = providers[slot]
        out["key_slots"].append(slot + 1)
        key_stats = out["key_stats"].setdefault(str(slot + 1), {"ok": 0, "fail": 0})
        t0 = time.time()
        try:
            res = p.complete(system, user)
        except Exception as e:
            out["fail"] += 1
            key_stats["fail"] += 1
            out["err"] = str(e)[:80]
            continue
        lat = time.time() - t0
        body = _strip_meta(res.text)
        out["ok"] += 1
        key_stats["ok"] += 1
        key_stats["lat"] = round(lat, 2)
        if not out["sample"]:
            out["sample"] = body
        out["lat"].append(lat)
        out["tps"].append(res.completion_tokens / lat if lat > 0 else 0)
        out["han"].append(han_ratio(body))
        out["ratio"].append(len(body) / max(len(zh), 1))
        problems = lint(zh, body)
        if problems:
            out["problem_runs"] += 1
            out["problems"].extend(problems)
            out["err"] = problems[0][:80]
        for term, count in narrator_terms(body).items():
            out["narrator_terms"][term] = out["narrator_terms"].get(term, 0) + count
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--models", help="danh sách model id, phân cách phẩy",
                    default=",".join(DEFAULT_MODELS))
    ap.add_argument("--runs", type=int, default=2, help="số lượt mỗi model (mặc định 2)")
    ap.add_argument("--timeout", type=int, default=45,
                    help="timeout mỗi request benchmark, giây (không đổi worker production)")
    ap.add_argument("--chars", type=int, default=3000, help="độ dài đề bài (ký tự Hán)")
    ap.add_argument("--novel", type=int, help="novel id dùng làm mẫu benchmark")
    ap.add_argument("--chapter", type=int, default=1, help="chapter_index của mẫu")
    ap.add_argument("--synthetic", action="store_true", help="dùng mẫu tự tạo, không đọc/gửi nội dung DB")
    ap.add_argument("--synthetic-repeat", type=int, default=1,
                    help="lặp mẫu tự tạo để giả lập input dài hơn (mặc định 1)")
    ap.add_argument("--all", action="store_true", help="benchmark mọi text model endpoint đang liệt kê")
    ap.add_argument("--quality-candidates", action="store_true",
                    help="benchmark nhóm model free có khả năng cạnh tranh cho dịch văn học")
    ap.add_argument("--list", action="store_true", help="chỉ liệt kê model/candidate, không gọi dịch")
    ap.add_argument("--out", default="benchmark_out/benchmark_nim_results.json",
                    help="file JSON kết quả")
    args = ap.parse_args()

    discovered = available_models() if (args.all or args.list or args.quality_candidates) else []
    candidates = translation_candidates(discovered)
    if args.list:
        print(f"NVIDIA Free Endpoint: {len(discovered)} model truy cập được, "
              f"{len(candidates)} text candidate; {len(settings.nvidia_keys)} API key")
        print("\n".join(candidates))
        return

    zh = ((SYNTHETIC_QUALITY_SAMPLE + "\n") * max(args.synthetic_repeat, 1)
          if args.synthetic else fetch_sample(args.chars, args.novel, args.chapter))[:args.chars]
    print(f"Đề bài: {len(zh)} ký tự Hán, {args.runs} lượt/model\n")
    hdr = f"{'model':<45} {'ok':>5} {'lat(s)':>8} {'tok/s':>7} {'hán%':>6} {'phình':>6} {'run lỗi':>8}"
    print(hdr)
    print("-" * len(hdr))
    results = []
    models = (candidates if args.all else [m for m in QUALITY_CANDIDATES if m in candidates]
              if args.quality_candidates
              else [x.strip() for x in args.models.split(",") if x.strip()])
    for index, m in enumerate(models):
        r = bench_model(m, zh, args.runs, args.timeout, key_offset=index)
        results.append(r)
        avg = lambda xs: sum(xs) / len(xs) if xs else 0
        print(f"{r['model']:<45} {r['ok']}/{args.runs:<3} {avg(r['lat']):>8.1f} "
              f"{avg(r['tps']):>7.1f} {avg(r['han'])*100:>5.1f}% {avg(r['ratio']):>6.2f} "
              f"{r['problem_runs']:>8}" + (f"  ({r['err']})" if r["err"] else ""))
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nĐã ghi kết quả: {args.out}")
    good = [r for r in results if r["ok"] and not r["problem_runs"]]
    if good:
        best = min(good, key=lambda r: sum(r["lat"]) / len(r["lat"]))
        print(f"\nNhanh nhất trong nhóm sạch: {best['model']}")


if __name__ == "__main__":
    main()
