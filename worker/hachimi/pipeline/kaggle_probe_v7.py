"""Kernel Kaggle: chạy TUẦN TỰ ba bậc probe P0/P1/P2 của vòng v7 trong MỘT lượt push.

Vì sao gộp (docs/train-scratch-v7.md mục 8): quota 30 giờ GPU/tuần, mỗi lượt push chờ 8-10
phút. Ba bậc ~2 giờ/bậc, gộp lại còn một lượt chờ.

Thứ tự trong kernel — theo đúng bài học "môi trường lạ thì lượt đầu để DÒ"
(docs/kaggle-cli.md): dò môi trường → smoke `--self-check` (nấu spm tí hon, train 50 bước,
xuất CT2, dịch thử) → mới tới ba bậc thật. Hỏng mắt xích nào thì lộ trong 5 phút chứ không
phải sau 2 giờ.

Ba bậc, mỗi bậc đổi ĐÚNG MỘT nút:
    P0  preset tiny       ctx-mode zero     → data người có đủ không?
    P1  preset tiny       ctx-mode corpus   → ngữ cảnh có hạ bịa chủ ngữ không?
    P2  preset tiny-deep  ctx-mode corpus   → sâu encoder có hơn rộng không? (param-matched)

Ra: /kaggle/working/{p0,p1,p2}/ (model + ct2 + training_mix.json) và `probe_report.json`
(chrF từng bậc + bản dịch dev để đọc tay). Chấm bằng thước dự án thì làm ở nhà — kernel chỉ
lo phần cần GPU.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

WORK = Path("/kaggle/working")
MARKER = "train_scratch.py"
PROBES = [
    {"name": "p0", "preset": "tiny", "ctx_mode": "zero"},
    {"name": "p1", "preset": "tiny", "ctx_mode": "corpus"},
    {"name": "p2", "preset": "tiny-deep", "ctx_mode": "corpus"},
]
DEV_SAMPLE = 500
# 2 epoch chứ không phải 1: model train từ SỐ 0 mà thiếu bước cập nhật thì ra một bản ngắc
# ngứ, và ta sẽ kết luận nhầm là "data không đủ" — đó là sai lầm đắt nhất của cả vòng này.
# 2M cặp / (96×2×2 GPU) ≈ 5,2k bước/epoch ⇒ ~10,4k bước, warmup 2k là 19%.
COMMON = ["--epochs", "2", "--per-device-batch", "96", "--grad-accum", "2"]


def run(command: list[str], **kwargs) -> int:
    print("$", " ".join(command), flush=True)
    return subprocess.call(command, **kwargs)


def find_file(name: str) -> Path | None:
    """Dò đệ quy trong /kaggle/input.

    Không đoán đường dẫn được: Kaggle mount ở `/kaggle/input/datasets/<user>/<slug>`, VÀ nó
    giải `data.zip` vào **thư mục `data/`** (trùng tên file zip) chứ không đổ ra gốc — đo được
    30/08 bằng `kaggle datasets files`. Dò là cách duy nhất khỏi sai.
    """
    for root, _dirs, files in os.walk("/kaggle/input"):
        if name in files:
            return Path(root) / name
    return None


def find_src() -> Path:
    marker = find_file(MARKER)
    if marker is None:
        raise SystemExit(f"Không thấy {MARKER} trong /kaggle/input — dataset chưa attach?")
    return marker.parent


def setup() -> None:
    """Công thức môi trường đã chạy được, chép từ docs/kaggle-cli.md — đừng chế lại."""
    import torch

    constraints = WORK / "constraints.txt"
    constraints.write_text(f"torch=={torch.__version__}\n")
    run([sys.executable, "-m", "pip", "-q", "install", "-U", "transformers<5",
         "sentencepiece", "ctranslate2", "sacrebleu", "accelerate",
         "-c", str(constraints)])


def dump_env() -> None:
    code = (
        "import torch, transformers, tokenizers, sentencepiece, ctranslate2, accelerate;"
        "print('torch', torch.__version__);"
        "print('transformers', transformers.__version__);"
        "print('tokenizers', tokenizers.__version__);"
        "print('sentencepiece', sentencepiece.__version__);"
        "print('ctranslate2', ctranslate2.__version__);"
        "print('accelerate', accelerate.__version__);"
        "print('cuda', torch.cuda.is_available(), torch.cuda.device_count(),"
        " torch.cuda.get_device_name(0) if torch.cuda.is_available() else '-');"
        "from transformers import Seq2SeqTrainingArguments as A;"
        "import inspect; p=inspect.signature(A).parameters;"
        "print('eval_strategy' if 'eval_strategy' in p else 'evaluation_strategy');"
        "print('has label_smoothing_factor', 'label_smoothing_factor' in p);"
        "print('has warmup_steps', 'warmup_steps' in p);"
        "print('has lr_scheduler_type', 'lr_scheduler_type' in p)"
    )
    run([sys.executable, "-c", code])


def launcher(script: Path) -> list[str]:
    """2 GPU thì DDP qua accelerate; 1 GPU (hoặc CPU) thì gọi thẳng."""
    import torch

    if torch.cuda.device_count() > 1:
        return ["accelerate", "launch", "--num_processes", str(torch.cuda.device_count()),
                "--multi_gpu", str(script)]
    return [sys.executable, str(script)]


def translate_dev(ct2_dir: Path, rows: list[dict], ctx_mode: str) -> list[str]:
    import ctranslate2
    import sentencepiece as spm

    translator = ctranslate2.Translator(str(ct2_dir), device="cpu", compute_type="int8")
    processor = spm.SentencePieceProcessor()
    processor.load(str(ct2_dir / "source.spm"))
    sep = "⟪ctx⟫"
    sources = []
    for row in rows:
        ctx = [c for c in (row.get("ctx") or []) if c]
        if ctx_mode == "zero" or not row.get("ctx_len"):
            text = row["zh"]
        else:
            text = sep.join([*ctx[-int(row["ctx_len"]):], row["zh"]])
        sources.append(processor.encode(text, out_type=str) + ["</s>"])
    results = translator.translate_batch(sources, beam_size=4, max_batch_size=16,
                                         max_decoding_length=180)
    # Bỏ cả `<s>`: đích được train dạng `<s> câu </s>` để decoder có token khởi đầu HỌC ĐƯỢC
    # mà vẫn khớp kiểu khởi động từ vector 0 của CT2 (xem `train_scratch.encode_rows`).
    drop = {"</s>", "<s>"}
    return [processor.decode([t for t in r.hypotheses[0] if t not in drop]) for r in results]


def main() -> None:
    setup()
    dump_env()
    src = find_src()
    print("SRC =", src, flush=True)
    script = src / MARKER
    # Mọi thứ nằm PHẲNG ở gốc dataset, kể cả spm. Lý do: `kaggle datasets create` mặc định
    # BỎ QUA thư mục con (`--dir-mode skip`) — để spm trong `spm24k/` là lên Kaggle mất sạch
    # mà không báo lỗi.
    spm_dir = src
    corpus, dev = find_file("corpus.jsonl"), find_file("dev.jsonl")
    if corpus is None or dev is None:
        # Dự phòng: nếu lần nào đó Kaggle KHÔNG giải nén hộ thì tự giải.
        unpacked = WORK / "data"
        for archive in sorted(src.glob("*.zip")):
            print(f"Tự giải nén {archive.name}", flush=True)
            shutil.unpack_archive(str(archive), str(unpacked))
        corpus, dev = unpacked / "corpus.jsonl", unpacked / "dev.jsonl"
    print(f"corpus = {corpus}\ndev = {dev}", flush=True)
    for path in (script, corpus, dev, spm_dir / "source.spm", spm_dir / "vocab.json"):
        if not path.exists():
            raise SystemExit(f"Thiếu {path}")

    if run([sys.executable, str(script), "--self-check"]) != 0:
        raise SystemExit("Smoke --self-check hỏng — dừng trước khi đốt giờ GPU")

    rows = [json.loads(line) for line in dev.read_text(encoding="utf-8").splitlines() if line.strip()]
    rows = rows[:DEV_SAMPLE]
    report = {"dev_rows": len(rows), "probes": {}}

    for probe in PROBES:
        out = WORK / probe["name"]
        code = run(launcher(script) + [
            "--corpus", str(corpus), "--dev", str(dev), "--spm", str(spm_dir),
            "--output-dir", str(out), "--preset", probe["preset"],
            "--ctx-mode", probe["ctx_mode"], "--export-ct2", *COMMON,
            *os.environ.get("PROBE_EXTRA", "").split(),
        ])
        if code != 0:
            report["probes"][probe["name"]] = {"error": f"exit {code}"}
            print(f"!! {probe['name']} lỗi exit {code} — chạy tiếp bậc sau", flush=True)
            continue
        mix = json.loads((out / "training_mix.json").read_text(encoding="utf-8"))
        hypotheses = translate_dev(out / "ct2-int8_float32", rows, probe["ctx_mode"])
        entry = {**probe, **mix, "sample": hypotheses[:20]}
        try:
            import sacrebleu

            entry["chrf"] = round(sacrebleu.corpus_chrf(
                hypotheses, [[row["vi"] for row in rows]]).score, 2)
        except Exception as error:  # pragma: no cover - chỉ mất điểm phụ, không mất model
            entry["chrf_error"] = repr(error)
        (WORK / f"hyp_{probe['name']}.json").write_text(
            json.dumps({"hyp": hypotheses, "ref": [r["vi"] for r in rows],
                        "zh": [r["zh"] for r in rows]}, ensure_ascii=False),
            encoding="utf-8")
        report["probes"][probe["name"]] = entry
        print(f"== {probe['name']}: chrF {entry.get('chrf')} · {entry['params_m']}M tham số",
              flush=True)

    (WORK / "probe_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: {"chrf": v.get("chrf"), "params_m": v.get("params_m"),
                          "error": v.get("error")}
                      for k, v in report["probes"].items()}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
