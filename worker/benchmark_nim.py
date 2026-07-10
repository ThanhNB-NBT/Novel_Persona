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
import time

from novelworker import db
from novelworker.config import settings
from novelworker.translator import prompts
from novelworker.translator.providers import TranslationProvider
from novelworker.translator.worker import (
    REGISTER_LINE, _register_violation, _strip_meta, check_translation, han_ratio,
)

NVIDIA_BASE_URL = "https://integrate.api.nvidia.com/v1"

# Ứng viên mặc định: model đang dùng + vài model đáng theo dõi. Sửa thoải mái.
DEFAULT_MODELS = [
    settings.nvidia_model,
    "qwen/qwen3-next-80b-a3b-instruct",
]


def fetch_sample(chars: int) -> str:
    """Lấy 1 chương thật (content_zh) trong DB làm đề bài."""
    rows = (
        db.sb().table("chapters").select("content_zh")
        .not_.is_("content_zh", "null").limit(1).execute()
    ).data or []
    if not rows:
        raise SystemExit("DB không có chương nào còn content_zh — cần 1 chương mẫu")
    return rows[0]["content_zh"][:chars]


def bench_model(model: str, zh: str, runs: int) -> dict:
    key = settings.nvidia_keys[0]
    p = TranslationProvider(NVIDIA_BASE_URL, key, model, "nvidia")
    system = prompts.build_chapter_system([], zh)
    user = prompts.build_chapter_user("测试章节", zh, None, register_line=REGISTER_LINE)
    out = {"model": model, "ok": 0, "fail": 0, "lat": [], "tps": [], "han": [],
           "ratio": [], "register_bad": 0, "err": ""}
    for _ in range(runs):
        t0 = time.time()
        try:
            res = p.complete(system, user)
        except Exception as e:
            out["fail"] += 1
            out["err"] = str(e)[:80]
            continue
        lat = time.time() - t0
        body = _strip_meta(res.text)
        out["ok"] += 1
        out["lat"].append(lat)
        out["tps"].append(res.completion_tokens / lat if lat > 0 else 0)
        out["han"].append(han_ratio(body))
        out["ratio"].append(len(body) / max(len(zh), 1))
        problem = check_translation(zh, body) or _register_violation(body)
        if problem:
            out["register_bad"] += 1
            out["err"] = problem[:80]
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--models", help="danh sách model id, phân cách phẩy",
                    default=",".join(DEFAULT_MODELS))
    ap.add_argument("--runs", type=int, default=2, help="số lượt mỗi model (mặc định 2)")
    ap.add_argument("--chars", type=int, default=3000, help="độ dài đề bài (ký tự Hán)")
    args = ap.parse_args()

    zh = fetch_sample(args.chars)
    print(f"Đề bài: {len(zh)} ký tự Hán, {args.runs} lượt/model\n")
    hdr = f"{'model':<45} {'ok':>5} {'lat(s)':>8} {'tok/s':>7} {'hán%':>6} {'phình':>6} {'lỗi prompt':>10}"
    print(hdr)
    print("-" * len(hdr))
    results = []
    for m in [x.strip() for x in args.models.split(",") if x.strip()]:
        r = bench_model(m, zh, args.runs)
        results.append(r)
        avg = lambda xs: sum(xs) / len(xs) if xs else 0
        print(f"{r['model']:<45} {r['ok']}/{args.runs:<3} {avg(r['lat']):>8.1f} "
              f"{avg(r['tps']):>7.1f} {avg(r['han'])*100:>5.1f}% {avg(r['ratio']):>6.2f} "
              f"{r['register_bad']:>10}" + (f"  ({r['err']})" if r["err"] else ""))
    good = [r for r in results if r["ok"] and not r["register_bad"]]
    if good:
        best = min(good, key=lambda r: sum(r["lat"]) / len(r["lat"]))
        print(f"\nNhanh nhất trong nhóm sạch: {best['model']}")


if __name__ == "__main__":
    main()
