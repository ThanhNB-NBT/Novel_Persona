"""PROBE: continued-finetune v5 trên bó DictDis + replay chống-quên (CPU). Đo giả thuyết mức B.

Câu hỏi: chỉ THÊM DATA nghĩa hiếm (không đổi kiến trúc) có đủ để Marian tự chọn nghĩa theo
manh mối trong câu (打麻将->tự ù, 喝瓶->Mizone) mà KHÔNG quên nghĩa cũ?

Cách: nạp v5 HF (models/hachimi-v5-hf), trộn [DictDis ×repeat] + [replay kaihe sạch] để
khỏi catastrophic-forget, train ít epoch LR thấp, export CT2. Eval bằng script riêng trên
câu TƯƠI (không trùng train). Tái dùng _export_ct2 của kaggle_train cho khớp quirk Marian.
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from kaggle_train import _export_ct2  # noqa: E402

ROOT = HERE.parents[1]  # worker/
V5_HF = ROOT / "models" / "hachimi-v5-hf"
DICTDIS = ROOT / "hachimi" / "data" / "gold" / "dictdis_polysemy.jsonl"
REPLAY = ROOT / "hachimi" / "data" / "kaihe_anchor.jsonl"  # cặp CÂU zh/vi (train_data.jsonl là doc-level, sai)
OUT = ROOT / "models" / "hachimi-v5-dictdis"


def load_dictdis() -> list[dict]:
    return [json.loads(l) for l in DICTDIS.open(encoding="utf-8") if l.strip()]


def load_replay(n: int, seed: int = 42) -> list[dict]:
    rows: list[dict] = []
    for l in REPLAY.open(encoding="utf-8"):
        if not l.strip():
            continue
        r = json.loads(l)
        zh, vi = r.get("zh"), r.get("vi")
        if zh and vi and 6 <= len(zh) <= 120:
            rows.append({"zh": zh, "vi": vi})
    random.Random(seed).shuffle(rows)
    return rows[:n]


def load_extra(paths: list[str]) -> list[dict]:
    """Booster bổ sung (date/name/idiom…): mỗi dòng {zh, vi}, không repeat."""
    rows: list[dict] = []
    for p in paths:
        path = Path(p)
        if not path.exists():
            print(f"cảnh báo: thiếu {path} — bỏ qua", flush=True)
            continue
        n0 = len(rows)
        for l in path.open(encoding="utf-8"):
            if not l.strip():
                continue
            r = json.loads(l)
            zh, vi = r.get("zh"), r.get("vi")
            if zh and vi and 6 <= len(zh) <= 200:
                rows.append({"zh": zh, "vi": vi})
        print(f"extra {path.name}: +{len(rows) - n0}", flush=True)
    return rows


def main(dictdis_repeat: int, replay_n: int, epochs: float, lr: float, batch: int,
         extra_jsonl: list[str]) -> None:
    import torch
    from transformers import (
        AutoModelForSeq2SeqLM,
        AutoTokenizer,
        DataCollatorForSeq2Seq,
        Seq2SeqTrainer,
        Seq2SeqTrainingArguments,
    )

    dd = load_dictdis()
    replay = load_replay(replay_n)
    extra = load_extra(extra_jsonl)
    rows = dd * dictdis_repeat + extra + replay
    random.Random(0).shuffle(rows)
    print(f"train rows: {len(rows)} = DictDis {len(dd)}×{dictdis_repeat} "
          f"+ extra {len(extra)} + replay {len(replay)}", flush=True)

    tok = AutoTokenizer.from_pretrained(str(V5_HF))
    model = AutoModelForSeq2SeqLM.from_pretrained(str(V5_HF))

    def tokenize(items: list[dict]) -> list[dict]:
        enc = tok([r["zh"] for r in items], text_target=[r["vi"] for r in items],
                  truncation=True, max_length=256)
        return [{k: enc[k][i] for k in enc} for i in range(len(items))]

    class DS(torch.utils.data.Dataset):
        def __init__(self, it): self.it = it
        def __len__(self): return len(self.it)
        def __getitem__(self, i): return self.it[i]

    ds = DS(tokenize(rows))
    OUT.mkdir(parents=True, exist_ok=True)
    ta = Seq2SeqTrainingArguments(
        output_dir=str(OUT), learning_rate=lr, num_train_epochs=epochs,
        per_device_train_batch_size=batch, gradient_accumulation_steps=1,
        warmup_ratio=0.05, weight_decay=0.01, lr_scheduler_type="cosine",
        logging_steps=25, save_strategy="no", report_to="none", seed=0, fp16=False,
    )
    tr = Seq2SeqTrainer(
        model=model, args=ta, train_dataset=ds,
        data_collator=DataCollatorForSeq2Seq(tok, model=model), processing_class=tok,
    )
    tr.train()
    tr.save_model(str(OUT))
    tok.save_pretrained(str(OUT))
    print("finetune xong, export CT2…", flush=True)
    _export_ct2(OUT)
    print("DONE ->", OUT / "ct2-int8_float32", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dictdis-repeat", type=int, default=8)
    ap.add_argument("--replay-n", type=int, default=2500)
    ap.add_argument("--epochs", type=float, default=2.0)
    ap.add_argument("--lr", type=float, default=1e-5)
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--extra-jsonl", nargs="*", default=[
        str(ROOT / "hachimi" / "data" / "gold" / "date_booster.jsonl"),
        str(ROOT / "hachimi" / "data" / "gold" / "name_booster.jsonl"),
        str(ROOT / "hachimi" / "data" / "gold" / "idiom_oversample.jsonl"),
    ], help="booster bổ sung gộp vào tập dạy (mặc định: date+name+idiom)")
    ap.add_argument("--smoke", action="store_true", help="dry-run bé: 1 epoch, replay 60, repeat 1")
    a = ap.parse_args()
    if a.smoke:
        main(dictdis_repeat=1, replay_n=60, epochs=1.0, lr=1e-5, batch=8,
             extra_jsonl=a.extra_jsonl[:1] if a.extra_jsonl else [])
    else:
        main(a.dictdis_repeat, a.replay_n, a.epochs, a.lr, a.batch,
             extra_jsonl=a.extra_jsonl)
