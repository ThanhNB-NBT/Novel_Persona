#!/usr/bin/env python3
"""Benchmark Hy-MT2-1.8B GGUF trên VPS 2 core/2GB — đo tok/s, RAM, chất lượng.

Chạy TRÊN VPS (cần python3 + docker, không cần pip install gì):

    cd worker/hachimi/eval
    python3 hymt2_bench.py                     # mặc định: 2bit rồi Q4_K_M
    python3 hymt2_bench.py --quants 1.25,2bit  # thêm bản 1.25-bit
    python3 hymt2_bench.py --self-check        # kiểm tra cục bộ, không đụng mạng/docker

Mỗi quant: tải GGUF về ./hymt2_models/, dựng container llama.cpp server GIỚI HẠN
RAM (--mem, mặc định 1100MB — mô phỏng chung máy với worker ~700MB), dịch từng
chương trong hymt2_bench_input.jsonl, ghi kết quả vào ./hymt2_bench_result/.

Kết quả gồm tok/s, RAM đỉnh (docker stats), bản dịch để MỞ RA ĐỌC so với ref_vi
(bản Hachimi v5 đang production). Quyết định deploy bằng mắt + số, không tin ước tính.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

IMAGE = "ghcr.io/ggml-org/llama.cpp:server"
CONTAINER = "hymt2-bench"
PORT = 8090
CTX = 8192
THREADS = 2

# Repo GGUF trên HF — ID phân biệt hoa/thường nên thử nhiều biến thể chính tả.
QUANT_REPOS = {
    "1.25": ["tencent/Hy-MT2-1.8B-1.25bit-GGUF",
             "tencent/Hy-MT2-1.8B-1.25Bit-GGUF",
             "AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF"],
    "2bit": ["tencent/Hy-MT2-1.8B-2bit-GGUF",
             "tencent/Hy-MT2-1.8B-2Bit-GGUF"],
    "q4": ["tencent/Hy-MT2-1.8B-GGUF"],
}
QUANT_PREFER = {"q4": "Q4_K_M"}  # trong repo q4 chọn đúng bản Q4_K_M

PROMPT = ("将以下文本翻译成越南语，注意只需要输出翻译后的结果，不要额外解释：\n\n{zh}")
SAMPLE_PARAMS = {"temperature": 0.7, "top_p": 0.6, "top_k": 20}  # khuyến nghị của Tencent


def _self_check() -> None:
    assert PROMPT.format(zh="测试").startswith("将以下文本翻译成越南语")
    m = re.match(r"(\d+(?:\.\d+)?)\s*(MiB|GiB)", "812MiB / 1.07GiB")
    assert m and abs(float(m.group(1)) - 812) < 1e-9
    m = re.match(r"(\d+(?:\.\d+)?)\s*(MiB|GiB)", "1.07GiB / 2GiB")
    assert m and float(m.group(1)) * 1024 > 1000
    assert abs(StatsPoller.parse("812MiB / 1.07GiB") - 812) < 0.01
    assert abs(StatsPoller.parse("1.05GiB / 2GiB") - 1075.2) < 0.01
    assert pick_file([{"path": "mmproj.gguf"}, {"path": "Hy-MT2-Q4_K_M.gguf"},
                      {"path": "Hy-MT2-F16.gguf"}], "q4") == "Hy-MT2-Q4_K_M.gguf"
    print("hymt2_bench self-check OK")


def pick_file(entries: list[dict], quant: str) -> str | None:
    ggufs = [e["path"] for e in entries
             if e.get("path", "").lower().endswith(".gguf")
             and "mmproj" not in e["path"].lower()]
    if not ggufs:
        return None
    prefer = QUANT_PREFER.get(quant)
    if prefer:
        for g in ggufs:
            if prefer.lower() in g.lower():
                return g
    return min(ggufs, key=len)


def http_json(url: str, timeout: int = 30, method: str = "GET", body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def sh(*cmd: str, capture: bool = True):
    return subprocess.run(cmd, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.STDOUT if capture else None).stdout or ""


def preflight(input_path: Path, mem: str) -> None:
    if not input_path.exists():
        sys.exit(f"Không thấy {input_path}")
    try:
        sh("docker", "version", "--format", "{{.Server.Version}}")
    except Exception as e:
        sys.exit(f"Docker không chạy được: {e}")
    free_mb = int(sh("df", "-Pm", ".").strip().split("\n")[1].split()[3])
    need = 3000 if not Path("hymt2_models").exists() else 500
    if free_mb < need:
        sys.exit(f"Đĩa chỉ còn {free_mb}MB, cần ≥{need}MB cho models + kết quả")
    print(f"preflight OK (đĩa còn {free_mb}MB, mem limit container {mem})")


def resolve_gguf(quant: str) -> tuple[str, str]:
    """Trả (repo, filename); thử các biến thể chính tả repo cho tới khi ra."""
    last_err = ""
    for repo in QUANT_REPOS[quant]:
        url = f"https://huggingface.co/api/models/{repo}/tree/main"
        try:
            entries = http_json(url, timeout=20)
        except Exception as e:
            last_err = f"{repo}: {e}"
            continue
        fname = pick_file(entries, quant)
        if fname:
            size_mb = next((e.get("size", 0) for e in entries
                            if e.get("path") == fname), 0) // (1024 * 1024)
            print(f"[{quant}] chọn {repo}/{fname} (~{size_mb}MB)")
            return repo, fname
        last_err = f"{repo}: không thấy .gguf phù hợp"
    sys.exit(f"Không tìm được model cho quant '{quant}' ({last_err})")


def download(repo: str, fname: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 10_000_000:
        print(f"  đã có {dest.name}, bỏ qua tải")
        return
    url = f"https://huggingface.co/{repo}/resolve/main/{fname}"
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=60) as r, open(tmp, "wb") as f:
        total = int(r.headers.get("content-length") or 0)
        done = 0
        while True:
            chunk = r.read(1 << 22)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            if total:
                print(f"\r  tải {done >> 20}/{total >> 20} MB "
                      f"({done * 100 // total}%)", end="", flush=True)
    print()
    tmp.rename(dest)


class StatsPoller(threading.Thread):
    """Poll docker stats mỗi 0.7s, ghi đỉnh MB của container."""

    def __init__(self):
        super().__init__(daemon=True)
        self.peak = 0.0
        self.stop_flag = threading.Event()

    @staticmethod
    def parse(memusage: str) -> float:
        m = re.match(r"(\d+(?:\.\d+)?)\s*(MiB|GiB)", memusage.strip())
        if not m:
            return 0.0
        v = float(m.group(1))
        return v * 1024 if m.group(2) == "GiB" else v

    def run(self):
        while not self.stop_flag.is_set():
            try:
                out = sh("docker", "stats", "--no-stream", "--format",
                         "{{.MemUsage}}", CONTAINER)
                if out.strip():
                    mb = self.parse(out.strip().splitlines()[0])
                    self.peak = max(self.peak, mb)
            except Exception:
                pass
            self.stop_flag.wait(0.7)

    def stop(self):
        self.stop_flag.set()
        self.join(timeout=3)


def start_server(model_path: Path, mem: str) -> None:
    if subprocess.run(["docker", "inspect", CONTAINER],
                      capture_output=True).returncode == 0:
        sh("docker", "rm", "-f", CONTAINER)
    sh("docker", "run", "-d", "--name", CONTAINER,
       "--memory", mem, "--memory-swap", mem,  # không cho swap: OOM lộ sớm, khỏi thrashing
       "-p", f"{PORT}:8080",
       "-v", f"{model_path.parent.resolve()}:/models",
       IMAGE,
       "-m", f"/models/{model_path.name}",
       "--host", "0.0.0.0", "--port", "8080",
       "--threads", str(THREADS), "--ctx-size", str(CTX))
    deadline = time.time() + 180
    while time.time() < deadline:
        try:
            if http_json(f"http://127.0.0.1:{PORT}/health", timeout=5).get("status") == "ok":
                print("  server khoẻ")
                return
        except Exception:
            pass
        time.sleep(3)
    logs = sh("docker", "logs", "--tail", "40", CONTAINER)
    sh("docker", "rm", "-f", CONTAINER)
    raise RuntimeError(f"server không lên sau 180s. Log cuối:\n{logs[-1500:]}")


def translate(chapters: list[dict]) -> tuple[list[dict], float]:
    results = []
    poller = StatsPoller()
    poller.start()
    try:
        for i, ch in enumerate(chapters):
            body = {
                "messages": [{"role": "user",
                              "content": PROMPT.format(zh=ch["zh"])}],
                "max_tokens": 4096,
                **SAMPLE_PARAMS,
            }
            t0 = time.time()
            resp = http_json(f"http://127.0.0.1:{PORT}/v1/chat/completions",
                             timeout=1800, method="POST", body=body)
            wall = time.time() - t0
            n_tok = resp.get("usage", {}).get("completion_tokens", 0)
            pred_ms = (resp.get("timings") or {}).get("prediction_ms") or 0
            tps = n_tok / (pred_ms / 1000) if pred_ms else (n_tok / wall if wall else 0)
            content = resp["choices"][0]["message"]["content"]
            results.append({**{k: ch[k] for k in ("novel", "chapter_index")},
                            "out_vi": content, "wall_s": round(wall, 1),
                            "out_tokens": n_tok, "tok_per_s": round(tps, 1)})
            print(f"  chương {i + 1}/{len(chapters)}: {n_tok} token · "
                  f"{tps:.1f} tok/s · {wall:.0f}s")
    finally:
        poller.stop()
    return results, poller.peak


def write_report(out_dir: Path, quant: str, results: list[dict], peak_mb: float) -> None:
    avg_tps = sum(r["tok_per_s"] for r in results) / max(1, len(results))
    lines = [
        f"## Quant `{quant}` — đỉnh RAM {peak_mb:.0f}MB · trung bình {avg_tps:.1f} tok/s",
        "",
        "| Chương | Wall (s) | Token ra | tok/s |",
        "|---|---|---|---|",
    ]
    for r in results:
        lines.append(f"| {r['novel']} ch{r['chapter_index']} | {r['wall_s']} | "
                     f"{r['out_tokens']} | {r['tok_per_s']} |")
    lines.append("")
    for r in results:
        fn = out_dir / f"out_{quant}_{r['chapter_index']}.txt"
        fn.write_text(r["out_vi"], encoding="utf-8")
        lines += [f"### {fn.name} — {r['novel']}", "",
                  "**Hy-MT2:**", "```", r["out_vi"][:600], "```", "",
                  "**Hachimi v5 (ref):**", "```", r.get("ref_head", ""), "```", ""]
    (out_dir / "report.md").open("a", encoding="utf-8").write("\n".join(lines) + "\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--quants", default="2bit,q4",
                    help="danh sách quant chạy tuần tự (mặc định 2bit,q4)")
    ap.add_argument("--mem", default="1100m", help="giới hạn RAM container (mặc định 1100m)")
    ap.add_argument("--keep", action="store_true", help="không xoá container sau khi xong")
    ap.add_argument("--self-check", action="store_true")
    a = ap.parse_args()

    if a.self_check:
        _self_check()
        return

    here = Path(__file__).resolve().parent
    input_path = here / "hymt2_bench_input.jsonl"
    preflight(input_path, a.mem)
    chapters = [json.loads(l) for l in input_path.open(encoding="utf-8")]
    print(f"{len(chapters)} chương mẫu")

    models_dir = here / "hymt2_models"
    out_dir = here / "hymt2_bench_result"
    models_dir.mkdir(exist_ok=True)
    out_dir.mkdir(exist_ok=True)

    for quant in [q.strip() for q in a.quants.split(",") if q.strip()]:
        if quant not in QUANT_REPOS:
            sys.exit(f"quant lạ: '{quant}' (có: {', '.join(QUANT_REPOS)})")
        print(f"\n===== QUANT {quant} =====")
        try:
            repo, fname = resolve_gguf(quant)
        except SystemExit as e:
            print(f"bỏ qua {quant}: {e}")
            continue
        model_path = models_dir / fname
        download(repo, fname, model_path)
        try:
            start_server(model_path, a.mem)
        except RuntimeError as e:
            print(f"LỖI load model {quant}: {e}")
            continue
        try:
            # warmup 1 câu ngắn cho JIT/allocator ổn định trước khi bấm giờ
            http_json(f"http://127.0.0.1:{PORT}/v1/chat/completions", timeout=600,
                      method="POST",
                      body={"messages": [{"role": "user",
                                          "content": PROMPT.format(zh="你好。")}],
                            "max_tokens": 64})
            results, peak_mb = translate(chapters)
        finally:
            if not a.keep:
                sh("docker", "rm", "-f", CONTAINER)
        for r in results:
            src = next((c for c in chapters
                        if c["novel_id"] == r["novel_id"]
                        and c["chapter_index"] == r["chapter_index"]), {})
            r["ref_head"] = src.get("ref_vi", "")[:600]
        write_report(out_dir, quant, results, peak)
        print(f"→ kết quả ghi ở {out_dir / 'report.md'}")

    print("\nXong. MỞ hymt2_bench_result/report.md ĐỌC SO SÁNH BẰNG MẮT trước khi quyết định.")


if __name__ == "__main__":
    main()
