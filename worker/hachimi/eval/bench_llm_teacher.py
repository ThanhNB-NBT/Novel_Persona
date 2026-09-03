"""Đo LLM ứng viên làm THẦY: dịch bộ chương khoá rồi chấm bằng ĐÚNG thước của dự án.

Vì sao có file này (30/08/2026): kết luận cũ *"đừng chưng cất từ model free"* là kết luận về
**gemma-4-31b**, con đó đo được ngang trình v5 nên chưng cất chỉ nhân thiên kiến của v5. Đó là
phán quyết về CHẤT LƯỢNG THẦY, không phải về việc data do người hay máy sinh — chưng cất từ
thầy mạnh hơn trò là kỹ thuật chuẩn (Kim & Rush 2016; Kasai et al. 2021 ghi rõ model tự hồi
quy cũng hưởng lợi từ KD).

Nên câu hỏi đúng là: **model này có hơn v6 trên thước của dự án không?** Đo, đừng tin.

    python bench_llm_teacher.py --model moonshotai/kimi-k3 --limit 20
    python bench_llm_teacher.py --score-only out.jsonl        # chấm lại file đã dịch
    python bench_llm_teacher.py --self-check

Thước dùng lại nguyên `eval_project_metrics`: bịa chủ ngữ, đại từ hiện đại, Hán sót, lint.
Bộ test là `clean_testset.jsonl` — 55 chương có bản dịch NGƯỜI, và bộ này ĐÃ bị chặn khỏi
corpus train (mục 7 spec) nên model nhà chưa từng thấy.

⚠ Thước phải neo vào bản dịch NGƯỜI. Nếu cả data train lẫn bộ đo đều do LLM sinh thì không còn
cách nào phát hiện lỗi hệ thống của chính LLM đó.

⚠ NVIDIA trả 429 theo số request ĐANG BAY chứ không theo RPM (memory `nim-429-inflight`), nên
chạy tuần tự, đừng bắn song song.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENDPOINT = "https://integrate.api.nvidia.com/v1/chat/completions"
DEFAULT_TESTSET = Path.home() / "hachimi-work/clean_testset.jsonl"

PROMPT = """Dịch đoạn tiểu thuyết tiên hiệp Trung Quốc dưới đây sang tiếng Việt.

LUẬT BẮT BUỘC:
- Lời kể ngôi ba dùng "hắn" (nam) / "nàng" (nữ) / "y". TUYỆT ĐỐI CẤM: tôi, mình, cậu, anh ấy,
  cô ấy, anh ta, cô ta, ông ta, bà ta.
- Lời thoại: nhân vật tự xưng "ta", gọi đối phương "ngươi".
- Tên người, tên môn phái, tên công pháp, tên bảo vật: phiên âm Hán-Việt TRỌN CỤM
  (南宫正雄 → Nam Cung Chính Hùng, 九阳神功 → Cửu Dương Thần Công). Không dịch nghĩa, không pinyin.
- Giữ nguyên số dòng và thứ tự dòng của bản gốc.
- Văn phải là tiếng Việt trôi chảy, KHÔNG dịch máy móc từng chữ.
- Chỉ xuất bản dịch, không thêm lời giải thích hay tiêu đề.

Đoạn cần dịch:
"""


def _metrics_module():
    spec = importlib.util.spec_from_file_location("epm", HERE / "eval_project_metrics.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["epm"] = module
    spec.loader.exec_module(module)
    return module


def call_llm(model: str, text: str, key: str, timeout: int, retries: int = 3) -> str:
    body = json.dumps({"model": model,
                       "messages": [{"role": "user", "content": PROMPT + text}],
                       "max_tokens": 8000, "temperature": 0.2}).encode()
    for attempt in range(retries):
        request = urllib.request.Request(
            ENDPOINT, data=body,
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data = json.load(response)
            return (data["choices"][0]["message"].get("content") or "").strip()
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == retries - 1:
                raise
            time.sleep(8 * (attempt + 1))       # 429 = request đang bay, chờ rồi thử lại
        except TimeoutError:
            if attempt == retries - 1:
                raise
            time.sleep(4)
    return ""


def score(rows: list[dict], label: str) -> dict:
    """Chấm bằng ĐÚNG thước của `eval_project_metrics`, trên cặp (câu nguồn, câu dịch)."""
    epm = _metrics_module()
    from novelworker.translator import lint

    n_sent = invents = modern = han = lint_hits = 0
    for row in rows:
        units = [m.group(0).strip() for line in row["zh"].split("\n") if line.strip()
                 for m in epm.SENT.finditer(line) if m.group(0).strip()]
        vi = row["vi_hyp"]
        vi_units = [line.strip() for line in vi.split("\n") if line.strip()]
        n_sent += len(units)
        # Bịa chủ ngữ chấm theo DÒNG ghép được; dòng lệch thì bỏ qua chứ không đoán.
        for zh_unit, vi_unit in zip(units, vi_units):
            invents += epm._invents_subject(zh_unit, vi_unit)
        modern += len(epm.MODERN.findall(vi))
        han += len(epm.HAN.findall(vi))
        lint_hits += lint.lint_score(None, vi)
    n = len(rows) or 1
    return {"model": label, "chương": n, "câu": n_sent,
            "bịa chủ ngữ/100 câu": round(invents / max(1, n_sent) * 100, 2),
            "đại từ hiện đại/chương": round(modern / n, 2),
            "Hán sót/chương": round(han / n, 2),
            "lint/chương": round(lint_hits / n, 2)}


def report(results: list[dict]) -> None:
    keys = [k for k in results[0] if k not in ("model", "chương", "câu")]
    width = max(len(r["model"]) for r in results) + 2
    print(f"\n{'model':{width}}" + " ".join(f"{k:>24s}" for k in keys))
    for row in results:
        print(f"{row['model']:{width}}" + " ".join(f"{row[k]:24.2f}" for k in keys))
    print(f"\n({results[0]['chương']} chương · {results[0]['câu']} câu)")
    print("Thấp hơn là tốt hơn ở cả bốn cột.")


def run(args) -> None:
    key = args.key or os.environ.get("NVIDIA_API_KEY")
    if not key:
        env = Path(__file__).resolve().parents[2] / ".env"
        for line in env.read_text(encoding="utf-8").splitlines() if env.is_file() else []:
            if line.startswith("NVIDIA_API_KEY="):
                key = line.split("=", 1)[1].strip()
            elif line.startswith("NVIDIA_API_KEYS=") and not key:
                key = line.split("=", 1)[1].split(",")[0].strip()
    if not key:
        raise SystemExit("Thiếu NVIDIA_API_KEY")

    rows = [json.loads(line) for line in
            args.testset.read_text(encoding="utf-8").splitlines() if line.strip()]
    rows = rows[:args.limit] if args.limit else rows
    out_rows = []
    started = time.time()
    for index, row in enumerate(rows, 1):
        try:
            hypothesis = call_llm(args.model, row["zh"], key, args.timeout)
        except Exception as error:            # noqa: BLE001 - hỏng 1 chương thì bỏ, chạy tiếp
            print(f"  [{index}/{len(rows)}] LỖI {type(error).__name__}: {str(error)[:80]}",
                  flush=True)
            continue
        if not hypothesis:
            print(f"  [{index}/{len(rows)}] trả về rỗng", flush=True)
            continue
        out_rows.append({"zh": row["zh"], "vi_hyp": hypothesis,
                         "vi_human": row.get("vi_human", "")})
        if index % 5 == 0:
            print(f"  [{index}/{len(rows)}] {(time.time()-started)/index:.1f}s/chương", flush=True)
    args.out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in out_rows),
                        encoding="utf-8")
    print(f"→ {args.out} ({len(out_rows)} chương)")
    if out_rows:
        results = [score(out_rows, args.model)]
        human = [{"zh": r["zh"], "vi_hyp": r["vi_human"]} for r in out_rows if r["vi_human"]]
        if human:
            results.append(score(human, "BẢN DỊCH NGƯỜI (mốc)"))
        report(results)


def _self_check() -> None:
    epm = _metrics_module()
    assert hasattr(epm, "MODERN") and hasattr(epm, "_invents_subject")
    rows = [{"zh": "他走进房间。\n开口说道。",
             "vi_hyp": "Hắn bước vào phòng.\nMở miệng nói."}]
    clean = score(rows, "sạch")
    assert clean["đại từ hiện đại/chương"] == 0, clean
    assert clean["Hán sót/chương"] == 0, clean
    dirty = score([{"zh": "他走进房间。", "vi_hyp": "Anh ấy bước vào phòng, 房间 rất tối."}], "bẩn")
    assert dirty["đại từ hiện đại/chương"] >= 1, dirty
    assert dirty["Hán sót/chương"] >= 2, dirty
    assert "Dịch đoạn tiểu thuyết" in PROMPT and "CẤM" in PROMPT
    print("bench_llm_teacher OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="moonshotai/kimi-k3")
    ap.add_argument("--testset", type=Path, default=DEFAULT_TESTSET)
    ap.add_argument("--out", type=Path,
                    default=Path.home() / "hachimi-work/scratch/llm_teacher.jsonl")
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--key")
    ap.add_argument("--score-only", type=Path)
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return
    if args.score_only:
        rows = [json.loads(line) for line in
                args.score_only.read_text(encoding="utf-8").splitlines() if line.strip()]
        results = [score(rows, args.model)]
        human = [{"zh": r["zh"], "vi_hyp": r["vi_human"]} for r in rows if r.get("vi_human")]
        if human:
            results.append(score(human, "BẢN DỊCH NGƯỜI (mốc)"))
        report(results)
        return
    run(args)


if __name__ == "__main__":
    main()
