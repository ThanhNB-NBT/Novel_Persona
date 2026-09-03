"""Cổng LaBSE cho corpus v7 — lọc cặp căn lệch, chạy trên GPU, có thể chạy tiếp khi đứt.

Vì sao tách khỏi `15_score_labse.py`: script đó nạp CẢ file vào RAM
(`read_text().splitlines()`) — 8-9 triệu dòng / 3GB là chết ngay. Bản này chảy theo dòng, ghi
dần, và nhớ vị trí để chạy tiếp.

Chỗ đứng trong dây chuyền:

    28_build_scratch_corpus.py   (CPU, ở nhà)  → corpus10m.jsonl   (cổng `_replay_ok`)
    30_labse_filter_corpus.py    (GPU, Kaggle) → corpus_labse.jsonl (cổng LaBSE)
    train_scratch.py             (GPU, Kaggle) → model v7

Cổng LaBSE chấm cặp `(zh, vi)` TRẦN — không dính `ctx`. Dòng bị loại vẫn để nguyên `ctx` của
các dòng khác: ctx là nguồn TRUNG của câu liền trước, nó hợp lệ kể cả khi bản dịch của câu đó
hỏng (cùng lý lẽ với `28_build_scratch_corpus.novel_pairs`).

    # đo trước khi chốt ngưỡng — ĐỪNG tin thẳng con số 0,70 của bản bàn giao
    python 30_labse_filter_corpus.py --input corpus10m.jsonl --calibrate
    # lọc thật
    python 30_labse_filter_corpus.py --input corpus10m.jsonl --output corpus_labse.jsonl \
        --threshold 0.70
    python 30_labse_filter_corpus.py --self-check      # không cần GPU, không tải model

`--kaggle` bật chế độ kernel: tự cài thư viện, tự dò file trong /kaggle/input, ghi ra
/kaggle/working.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

MODEL = "sentence-transformers/LaBSE"
STATE_SUFFIX = ".state.json"


def cosine_scores(model, zh: list[str], vi: list[str], batch: int):
    """Nhúng hai phía rồi lấy tích vô hướng — vector đã chuẩn hoá nên đó chính là cosine."""
    import torch

    with torch.inference_mode():
        left = model.encode(zh, batch_size=batch, convert_to_tensor=True,
                            normalize_embeddings=True, show_progress_bar=False)
        right = model.encode(vi, batch_size=batch, convert_to_tensor=True,
                             normalize_embeddings=True, show_progress_bar=False)
        return (left * right).sum(dim=1).tolist()


def iter_batches(path: Path, size: int, skip: int = 0, stride: int = 1):
    """Nhả (chỉ_số_dòng_cuối, [row…]). Chỉ số để ghi state chạy tiếp.

    `stride > 1` lấy mỗi N dòng một — BẮT BUỘC khi hiệu chuẩn: corpus xếp theo TRUYỆN nên
    2000 dòng đầu chỉ là một truyện, chấm trên đó ra ngưỡng của riêng truyện ấy.
    """
    rows: list[dict] = []
    index = 0
    with path.open(encoding="utf-8") as handle:
        for index, line in enumerate(handle, 1):
            if index <= skip or (stride > 1 and index % stride):
                continue
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
            if len(rows) >= size:
                yield index, rows
                rows = []
    if rows:
        yield index, rows


def load_model(device: str | None):
    import torch
    from sentence_transformers import SentenceTransformer

    device = device or ("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Nạp {MODEL} trên {device}", flush=True)
    model = SentenceTransformer(MODEL, device=device)
    if device == "cuda":
        model = model.half()          # fp16: LaBSE 471M chạy gọn trên T4, nhanh gần gấp đôi
    model.eval()
    return model


def calibrate(args) -> None:
    """In phân vị điểm trên một mẫu + ví dụ ở từng mức, để CHỌN ngưỡng thay vì đoán.

    Bản bàn giao ghi 0,70 nhưng đó là ước tính chưa chạy. Ngưỡng sai 0,05 là mất hoặc giữ
    hàng triệu cặp."""
    import statistics as st

    model = load_model(args.device)
    scores: list[float] = []
    samples: list[tuple[float, str, str]] = []
    for _, rows in iter_batches(args.input, args.batch, stride=args.stride):
        values = cosine_scores(model, [r["zh"] for r in rows], [r["vi"] for r in rows],
                               args.encode_batch)
        scores.extend(values)
        samples.extend((v, r["zh"], r["vi"]) for v, r in zip(values, rows))
        if len(scores) >= args.calibrate_size:
            break
    scores.sort()
    print(f"\nMẫu {len(scores):,} cặp · trung vị {st.median(scores):.3f}")
    for pct in (1, 5, 10, 20, 30, 40, 50, 70, 90):
        print(f"  phân vị {pct:>2}%: {scores[int(len(scores) * pct / 100)]:.3f}")
    for cut in sorted(args.show_near or (0.60, 0.65, 0.70, 0.75, 0.80)):
        keep = sum(1 for s in scores if s >= cut)
        print(f"  ngưỡng {cut:.2f} → giữ {keep / max(1, len(scores)):.1%}")
    samples.sort(key=lambda item: item[0])
    # Cạnh OUTPUT chứ không cạnh INPUT: trên Kaggle `/kaggle/input` là read-only, ghi vào đó
    # là `OSError: [Errno 30]` — chết đúng sau khi đã chấm xong 20k cặp, phí cả lượt GPU.
    dump = Path(str(args.output) + ".calib.jsonl")
    dump.write_text("".join(
        json.dumps({"labse": round(s, 4), "zh": z, "vi": v}, ensure_ascii=False) + "\n"
        for s, z, v in samples), encoding="utf-8")
    print(f"\nĐã lưu {len(samples):,} cặp đã chấm → {dump}"
          " (soi lại dải khác khỏi phải chấm lại 10 phút CPU)")

    print("\n— 5 cặp ĐIỂM THẤP NHẤT (phải thấy rõ là căn lệch thì ngưỡng mới đáng tin):")
    for score, zh, vi in samples[:5]:
        print(f"  {score:.3f} | {zh[:60]}\n        | {vi[:70]}")
    # In quanh NHIỀU mức: chỗ dao cắt mới là chỗ phải nhìn bằng mắt, mà mức đúng thì chưa
    # biết trước. Đo 30/08: quanh 0,70 toàn cặp DỊCH ĐÚNG — LaBSE cho điểm thấp với câu ngắn
    # và với phiên âm Hán-Việt, tức đúng cái giọng dự án theo đuổi.
    for cut in args.show_near:
        print(f"\n— 4 cặp quanh {cut:.2f}:")
        near = sorted(samples, key=lambda item: abs(item[0] - cut))[:4]
        for score, zh, vi in near:
            print(f"  {score:.3f} | {zh[:60]}\n        | {vi[:70]}")


def filter_corpus(args) -> dict:
    state_path = Path(str(args.output) + STATE_SUFFIX)
    skip, kept, seen = 0, 0, 0
    mode = "w"
    if args.resume and state_path.is_file():
        state = json.loads(state_path.read_text(encoding="utf-8"))
        skip, kept, seen = state["line"], state["kept"], state["seen"]
        mode = "a"
        print(f"Chạy tiếp từ dòng {skip:,} (đã giữ {kept:,})", flush=True)

    model = load_model(args.device)
    histogram = {f"{k / 20:.2f}": 0 for k in range(21)}
    with Path(args.output).open(mode, encoding="utf-8") as out:
        for line_no, rows in iter_batches(args.input, args.batch, skip):
            values = cosine_scores(model, [r["zh"] for r in rows], [r["vi"] for r in rows],
                                   args.encode_batch)
            for row, score in zip(rows, values):
                seen += 1
                histogram[f"{min(1.0, max(0.0, round(score * 20) / 20)):.2f}"] += 1
                if score < args.threshold:
                    continue
                if args.keep_score:
                    row["labse"] = round(score, 4)
                out.write(json.dumps(row, ensure_ascii=False) + "\n")
                kept += 1
            out.flush()
            state_path.write_text(json.dumps({"line": line_no, "kept": kept, "seen": seen}),
                                  encoding="utf-8")
            if seen % (args.batch * 20) < args.batch:
                print(f"  {seen:,} cặp · giữ {kept:,} ({kept / max(1, seen):.1%})", flush=True)

    manifest = {"input": str(args.input), "output": str(args.output), "seen": seen,
                "kept": kept, "keep_rate": round(kept / max(1, seen), 4),
                "threshold": args.threshold, "model": MODEL, "histogram": histogram}
    Path(str(args.output) + ".manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def kaggle_setup(args) -> None:
    """Chế độ kernel: cài thư viện, dò file vào, đặt chỗ ghi ra."""
    subprocess.call([sys.executable, "-m", "pip", "-q", "install", "-U",
                     "sentence-transformers"])
    if args.input is None or not Path(args.input).exists():
        for root, _dirs, files in os.walk("/kaggle/input"):
            for name in files:
                if name.startswith("corpus") and name.endswith(".jsonl"):
                    args.input = Path(root) / name
                    break
            if args.input and Path(args.input).exists():
                break
    if args.input is None or not Path(args.input).exists():
        raise SystemExit("Không thấy corpus*.jsonl trong /kaggle/input")
    args.output = Path("/kaggle/working/corpus_labse.jsonl")
    print(f"input = {args.input}\noutput = {args.output}", flush=True)


def _self_check() -> None:
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "in.jsonl"
        rows = [{"zh": f"第{k}句", "ctx": ["前一句"], "ctx_len": 1, "vi": f"Câu {k}",
                 "novel": "A"} for k in range(250)]
        path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows),
                        encoding="utf-8")
        batches = list(iter_batches(path, 100))
        assert [len(rows) for _, rows in batches] == [100, 100, 50], [len(r) for _, r in batches]
        assert batches[0][0] == 100 and batches[-1][0] == 250
        # Chạy tiếp: bỏ 100 dòng đầu thì còn đúng 150.
        assert sum(len(r) for _, r in iter_batches(path, 100, skip=100)) == 150
        # stride: 250 dòng, lấy mỗi 10 dòng một → 25 dòng, rải đều chứ không dồn đầu file.
        strided = [r for _, batch in iter_batches(path, 100, stride=10) for r in batch]
        assert len(strided) == 25, len(strided)
        assert strided[0]["vi"] == "Câu 9" and strided[1]["vi"] == "Câu 19", strided[:2]

        # Điểm cosine của vector đã chuẩn hoá: dựng model giả để kiểm phần ghép, khỏi tải 1,8GB.
        class FakeTensor(list):
            def __mul__(self, other):
                return FakeTensor([[a * b for a, b in zip(x, y)] for x, y in zip(self, other)])

            def sum(self, dim=None):
                return FakeTensor([sum(x) for x in self])

            def tolist(self):
                return list(self)

        class FakeModel:
            def encode(self, texts, **kwargs):
                return FakeTensor([[1.0, 0.0] if "第" in t else [0.6, 0.8] for t in texts])

        import types

        fake_torch = types.SimpleNamespace(
            inference_mode=lambda: __import__("contextlib").nullcontext())
        saved = sys.modules.get("torch")
        sys.modules["torch"] = fake_torch
        try:
            scores = cosine_scores(FakeModel(), ["第一句"], ["Câu một"], 8)
        finally:
            if saved is None:
                sys.modules.pop("torch", None)
            else:
                sys.modules["torch"] = saved
        assert abs(scores[0] - 0.6) < 1e-9, scores
    print("30_labse_filter_corpus OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", type=Path)
    ap.add_argument("--output", type=Path,
                    default=Path.home() / "hachimi-work/scratch/corpus_labse.jsonl")
    ap.add_argument("--threshold", type=float, default=0.70)
    ap.add_argument("--batch", type=int, default=2048, help="số cặp đọc mỗi lượt ghi state")
    ap.add_argument("--encode-batch", type=int, default=256, help="batch đưa vào LaBSE")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--calibrate-size", type=int, default=20_000)
    ap.add_argument("--show-near", type=float, nargs="*", default=[0.40, 0.50, 0.55, 0.60, 0.70],
                    help="in vài cặp quanh từng mức này để nhìn dao cắt vào đâu")
    ap.add_argument("--stride", type=int, default=997,
                    help="hiệu chuẩn lấy mỗi N dòng một, rải khắp các truyện (số nguyên tố cho chắc)")
    ap.add_argument("--keep-score", action="store_true", help="ghi kèm trường `labse`")
    ap.add_argument("--resume", action="store_true", default=True)
    ap.add_argument("--no-resume", dest="resume", action="store_false")
    ap.add_argument("--device")
    ap.add_argument("--kaggle", action="store_true")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return
    if args.kaggle:
        kaggle_setup(args)
    if args.input is None:
        raise SystemExit("Thiếu --input")
    if args.calibrate:
        calibrate(args)
        return
    manifest = filter_corpus(args)
    print(json.dumps({k: v for k, v in manifest.items() if k != "histogram"},
                     ensure_ascii=False, indent=2))
    print(f"→ {args.output}")


if __name__ == "__main__":
    main()
