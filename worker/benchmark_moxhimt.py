"""One-shot CTranslate2 CPU benchmark for Chinese-Vietnamese MT models.

Run from an activated worker virtualenv:
    python benchmark_moxhimt.py

Run five real chapters (one per existing corpus novel):
    python benchmark_moxhimt.py --input-glob 'corpus_translation/fresh_mix/*_c1.txt' \
      --repo ngocdang83/HachimiMT-60-zh-vi --ct2-dir ct2-int8_float32 \
      --compute-type int8_float32 --cpu-threads 2
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import re
import sys
import threading
import time
from pathlib import Path

# clean_source la single source of truth (text_clean.py) — bat buoc chay truoc khi
# dich de boc dau chong crawl bọc lẻ (『』…), giong het luc train.
sys.path.insert(0, str(Path(__file__).parent / "hachimi_finetune"))
from text_clean import clean_source


DEFAULT_INPUT = Path("eval_out_v2/n3487_c1.txt")


def _paragraphs_from_report(path: Path, max_chars: int) -> list[str]:
    text = path.read_text(encoding="utf-8")
    source = re.search(r"--- GỐC \(zh\) ---\s*(.*?)\s*--- DỊCH \(vi\) ---", text, re.S)
    if source:
        source_text = source.group(1)
    else:
        exported = re.findall(r"^ZH:\s*(.+)$", text, re.M)
        if not exported:
            raise ValueError(f"Không tìm thấy phần GỐC (zh) hoặc dòng ZH: trong {path}")
        source_text = "\n".join(exported)
    paragraphs = [cleaned for line in source_text.splitlines() if (cleaned := clean_source(line))]
    chosen: list[str] = []
    total = 0
    for paragraph in paragraphs:
        if total and total + len(paragraph) > max_chars:
            break
        chosen.append(paragraph)
        total += len(paragraph)
    if not chosen:
        raise ValueError("Mẫu benchmark rỗng")
    return chosen


def _self_check() -> None:
    sample = Path(__file__).with_suffix(".tmp")
    sample_dir = Path(__file__).with_suffix(".inputs")
    sample.write_text("--- GỐC (zh) ---\n甲\n乙\n--- DỊCH (vi) ---\na\n", encoding="utf-8")
    try:
        assert _paragraphs_from_report(sample, 1) == ["甲"]
        sample.write_text("ZH: 甲\nVI: a\nZH: 乙\nVI: b\n", encoding="utf-8")
        assert _paragraphs_from_report(sample, 2) == ["甲", "乙"]
        sample_dir.mkdir(exist_ok=True)
        (sample_dir / "a.txt").write_text("ZH: 甲\n", encoding="utf-8")
        (sample_dir / "b.txt").write_text("ZH: 乙\n", encoding="utf-8")
        assert [path.name for path in _input_paths(None, [str(sample_dir / "*.txt")])] == ["a.txt", "b.txt"]
    finally:
        sample.unlink(missing_ok=True)
        for path in sample_dir.glob("*"):
            path.unlink()
        sample_dir.rmdir()


def _input_paths(inputs: list[Path] | None, patterns: list[str]) -> list[Path]:
    paths = list(inputs or [])
    for pattern in patterns:
        paths.extend(sorted(Path(path) for path in glob.glob(pattern)))
    if not paths:
        paths = [DEFAULT_INPUT]
    unique = list(dict.fromkeys(path.resolve() for path in paths))
    missing = [path for path in unique if not path.is_file()]
    if missing:
        raise ValueError("Không có file input: " + ", ".join(map(str, missing)))
    return unique


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, action="append",
                        help="file chương; có thể dùng nhiều lần")
    parser.add_argument("--input-glob", action="append", default=[],
                        help="glob file chương, ví dụ corpus_translation/fresh_mix/*_c[1-2].txt")
    parser.add_argument("--repo", default="DanVP/MoxhiMT-60")
    parser.add_argument("--model-path", type=Path, help="thư mục model local, bỏ qua Hugging Face")
    parser.add_argument("--ct2-dir", default="ct2-int8")
    parser.add_argument("--compute-type", default="int8")
    parser.add_argument("--chars", type=int, default=5000)
    parser.add_argument("--beam-size", type=int, default=4)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--cpu-threads", type=int, default=0, help="0 = dùng toàn bộ core")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--out-dir", type=Path,
                        help="thư mục output khi chạy nhiều file")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        _self_check()
        print("OK")
        return

    try:
        import ctranslate2
        import psutil
        from huggingface_hub import snapshot_download
        from transformers import AutoTokenizer
    except ImportError as exc:
        raise SystemExit(
            "Thiếu dependency. Chạy: pip install ctranslate2 transformers sentencepiece psutil"
        ) from exc

    input_paths = _input_paths(args.input, args.input_glob)
    if len(input_paths) > 1 and args.out:
        raise SystemExit("--out chỉ dùng cho một input; dùng --out-dir khi chạy nhiều chương")
    samples = [(path, _paragraphs_from_report(path, args.chars)) for path in input_paths]
    total_chars = sum(sum(map(len, paragraphs)) for _, paragraphs in samples)
    print(f"Mẫu: {len(samples)} chương, {total_chars:,} chữ Trung")
    model_label = args.model_path.name if args.model_path else args.repo.rsplit("/", 1)[-1].lower()
    if args.out is None and len(samples) == 1:
        args.out = Path("benchmark_out") / f"{model_label}_output.txt"
    if len(samples) > 1:
        args.out_dir = args.out_dir or Path("benchmark_out") / model_label
    if args.model_path:
        model_root = args.model_path.resolve()
        if not model_root.is_dir():
            raise SystemExit(f"Không có thư mục model: {model_root}")
        print(f"Model local: {model_root}")
    else:
        print(f"Model: {args.repo}")
        print("Đang tải model (chỉ lần đầu)...")
        model_root = Path(snapshot_download(args.repo))

    process = psutil.Process()
    peak_rss = process.memory_info().rss
    done = threading.Event()

    def sample_rss() -> None:
        nonlocal peak_rss
        while not done.wait(0.05):
            peak_rss = max(peak_rss, process.memory_info().rss)

    monitor = threading.Thread(target=sample_rss, daemon=True)
    monitor.start()
    try:
        print("Đang nạp tokenizer...", flush=True)
        tokenizer = AutoTokenizer.from_pretrained(model_root)
        print("Đang nạp CTranslate2 INT8...", flush=True)
        translator_kwargs = {"device": "cpu", "compute_type": args.compute_type}
        if args.cpu_threads:
            translator_kwargs["intra_threads"] = args.cpu_threads
        translator = ctranslate2.Translator(str(model_root / args.ct2_dir), **translator_kwargs)
        print("Đang warm-up...", flush=True)
        # Warm model and thread pool; this is excluded from the speed figure.
        first_paragraph = samples[0][1][0]
        first_tokens = tokenizer.convert_ids_to_tokens(
            tokenizer(first_paragraph, truncation=True, max_length=512).input_ids
        )
        translator.translate_batch([first_tokens], beam_size=args.beam_size, max_decoding_length=512)

        started = time.perf_counter()
        outputs: list[tuple[Path, list[str], list[str]]] = []
        for path, paragraphs in samples:
            source_tokens = [
                tokenizer.convert_ids_to_tokens(
                    tokenizer(text, truncation=True, max_length=512).input_ids
                )
                for text in paragraphs
            ]
            hypotheses: list[list[str]] = []
            for start in range(0, len(source_tokens), args.batch_size):
                results = translator.translate_batch(
                    source_tokens[start : start + args.batch_size],
                    beam_size=args.beam_size,
                    max_decoding_length=512,
                )
                hypotheses.extend(result.hypotheses[0] for result in results)
            translations = [
                tokenizer.decode(tokenizer.convert_tokens_to_ids(tokens), skip_special_tokens=True)
                for tokens in hypotheses
            ]
            outputs.append((path, paragraphs, translations))
        elapsed = time.perf_counter() - started
    finally:
        done.set()
        monitor.join(timeout=1)

    peak_rss = max(peak_rss, process.memory_info().rss)
    threads = args.cpu_threads or "toàn bộ"
    print(f"Dịch: {elapsed:.2f}s | {total_chars / elapsed:.0f} chữ Trung/s | beam={args.beam_size} | CPU={threads}")
    print(f"Peak RAM tiến trình: {peak_rss / 1024**2:.0f} MiB")
    for path, paragraphs, translations in outputs:
        out = args.out if len(outputs) == 1 else args.out_dir / f"{path.stem}_output.txt"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(
            "\n\n".join(f"ZH: {source}\nVI: {translation}" for source, translation in zip(paragraphs, translations)),
            encoding="utf-8",
        )
        sample_id = hashlib.sha256("\n".join(paragraphs).encode()).hexdigest()[:12]
        print(f"Đã lưu {path.name}: {out} ({len(paragraphs)} đoạn, hash={sample_id})")
    first_path, first_paragraphs, first_translations = outputs[0]
    print(f"\n--- 3 đoạn đầu: {first_path.name} ---")
    for source, translation in zip(first_paragraphs[:3], first_translations[:3]):
        print(f"ZH: {source}\nVI: {translation}\n")


if __name__ == "__main__":
    main()
