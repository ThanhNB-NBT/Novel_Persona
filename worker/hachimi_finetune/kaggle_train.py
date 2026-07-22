"""Fine-tune HachimiMT-60 with high-quality replay and reviewed gold repairs.

Optimized for 2x T4 (Kaggle). Uses accelerate DDP for multi-GPU.
Run with --self-check before uploading, then follow README.md on Kaggle.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import re
import shutil
import tempfile
from pathlib import Path

from text_clean import clean_source


MODEL_ID = "ngocdang83/HachimiMT-60-zh-vi"
DATASET_ID = "ngocdang83/tran-vi-teacher"


def _pair(row: dict) -> tuple[str, str] | None:
    zh = clean_source(str(row.get("zh") or row.get("source") or row.get("source_zh") or ""))
    vi = str(row.get("vi") or row.get("proposed_vi") or row.get("target") or row.get("target_vi") or "").strip()
    if not zh or not vi:
        return None
    return zh, vi


def load_approved_gold(path: Path) -> list[dict[str, str]]:
    approved: list[dict[str, str]] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        row = json.loads(line)
        if row.get("status") != "approved":
            raise ValueError(f"{path}:{number} chưa có status=approved")
        pair = _pair(row)
        if pair is None:
            raise ValueError(f"{path}:{number} thiếu zh hoặc vi")
        approved.append({"zh": pair[0], "vi": pair[1]})
    if not approved:
        raise ValueError("approved_gold.jsonl rỗng; không train với gold chưa duyệt")
    return approved


def load_extra_replay(path: Path, limit: int) -> list[dict[str, str]]:
    """Load additional replay pairs from a local JSONL file (e.g. train_v2.jsonl)."""
    if not path.exists():
        return []
    rows: list[dict[str, str]] = []
    rng = random.Random(42)
    all_lines = path.read_text(encoding="utf-8").splitlines()
    rng.shuffle(all_lines)
    for line in all_lines:
        if not line.strip():
            continue
        row = json.loads(line)
        pair = _pair(row)
        if pair is None:
            continue
        rows.append({"zh": pair[0], "vi": pair[1]})
        if len(rows) >= limit:
            break
    return rows


def _teacher_tier(row: dict) -> str:
    meta = row.get("meta") or {}
    return str(row.get("teacher_tier") or meta.get("teacher_tier") or "").lower()


def load_replay(token: str | None, pro_limit: int, replay_limit: int) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    from datasets import load_dataset

    stream = load_dataset(DATASET_ID, split="train", streaming=True, token=token)
    pro: list[dict[str, str]] = []
    replay: list[dict[str, str]] = []
    for row in stream:
        pair = _pair(row)
        if pair is None:
            continue
        item = {"zh": pair[0], "vi": pair[1]}
        if _teacher_tier(row) == "pro":
            if len(pro) < pro_limit:
                pro.append(item)
        elif len(replay) < replay_limit:
            digest = hashlib.sha256(item["zh"].encode("utf-8")).digest()
            if int.from_bytes(digest[:2], "big") % 7 == 0:
                replay.append(item)
        if len(pro) >= pro_limit and len(replay) >= replay_limit:
            break
    if len(pro) < pro_limit:
        raise RuntimeError(f"Chỉ lấy được {len(pro)}/{pro_limit} hàng Pro từ corpus gốc")
    if len(replay) < replay_limit:
        raise RuntimeError(f"Chỉ lấy được {len(replay)}/{replay_limit} hàng replay từ corpus gốc")
    return pro, replay


def build_train_rows(
    gold: list[dict[str, str]],
    pro: list[dict[str, str]],
    replay: list[dict[str, str]],
    gold_repeat: int,
    extra_replay: list[dict[str, str]] | None = None,
) -> list[dict[str, str]]:
    rows = [*pro, *replay, *(gold * gold_repeat)]
    if extra_replay:
        rows.extend(extra_replay)
    random.Random(20260719).shuffle(rows)
    return rows


def _self_check() -> None:
    assert clean_source("脸上『露』出神『色』") == "脸上露出神色"
    assert _pair({"source_zh": "甲", "target_vi": "Ất"}) == ("甲", "Ất")
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "approved.jsonl"
        path.write_text('{"zh":"甲","vi":"Ất","status":"approved"}\n', encoding="utf-8")
        assert load_approved_gold(path) == [{"zh": "甲", "vi": "Ất"}]
    assert len(build_train_rows([{"zh": "甲", "vi": "Ất"}], [], [], 3)) == 3
    assert len(build_train_rows([{"zh": "甲", "vi": "Ất"}], [], [], 3, [{"zh": "乙", "vi": "B"}])) == 4


def _export_ct2(output_dir: Path) -> None:
    """Xuất CT2 int8. Base HachimiMT-60 không có hàng <pad> thừa ở cuối vocab,
    nên vô hiệu 2 bước cắt pad của CT2 (nếu để mặc định sẽ lệch 24000 vs 23999).
    Dùng Python API thay CLI để monkeypatch có hiệu lực trong cùng tiến trình.
    """
    import ctranslate2.converters.transformers as ct2t
    from ctranslate2.converters import TransformersConverter

    ct2t.MarianMTLoader._remove_pad_weights = lambda self, spec: None
    ct2t.MarianMTLoader.get_vocabulary = ct2t.BartLoader.get_vocabulary

    ct2_dir = output_dir / "ct2-int8_float32"
    TransformersConverter(str(output_dir)).convert(
        str(ct2_dir), quantization="int8_float32", force=True
    )
    for name in ("source.spm", "target.spm", "vocab.json", "tokenizer_config.json"):
        source = output_dir / name
        if source.exists():
            shutil.copy2(source, ct2_dir / name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gold", type=Path, required=False)
    parser.add_argument("--extra-replay", type=Path, default=None,
                        help="Optional local JSONL with extra replay pairs (e.g. train_v2.jsonl)")
    parser.add_argument("--extra-replay-limit", type=int, default=20_000)
    parser.add_argument("--output-dir", type=Path, default=Path("/kaggle/working/hachimi-60-cophong"))
    parser.add_argument("--hf-token", default=os.environ.get("HF_TOKEN"))
    parser.add_argument("--pro-limit", type=int, default=9_000)
    parser.add_argument("--replay-limit", type=int, default=24_000)
    parser.add_argument("--gold-repeat", type=int, default=5,
                        help="Gold repeat factor. 5 is optimal for 5000 gold pairs.")
    parser.add_argument("--epochs", type=float, default=3.0)
    parser.add_argument("--lr", type=float, default=3e-5)
    parser.add_argument("--per-device-batch", type=int, default=8)
    parser.add_argument("--grad-accum", type=int, default=4)
    parser.add_argument("--warmup-ratio", type=float, default=0.05)
    parser.add_argument("--weight-decay", type=float, default=0.01)
    parser.add_argument("--export-ct2", action="store_true")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        _self_check()
        print("OK")
        return
    if args.gold is None:
        raise SystemExit("Cần --gold approved_gold.jsonl")
    if not args.hf_token:
        raise SystemExit("Thiếu HF_TOKEN: chấp nhận dataset trên Hugging Face rồi thêm Kaggle Secret")

    from datasets import Dataset
    from transformers import (
        AutoModelForSeq2SeqLM,
        AutoTokenizer,
        DataCollatorForSeq2Seq,
        Seq2SeqTrainer,
        Seq2SeqTrainingArguments,
    )

    gold = load_approved_gold(args.gold)
    print(f"Gold đã duyệt: {len(gold)}")
    pro, replay = load_replay(args.hf_token, args.pro_limit, args.replay_limit)

    extra_replay: list[dict[str, str]] = []
    if args.extra_replay:
        extra_replay = load_extra_replay(args.extra_replay, args.extra_replay_limit)
        print(f"Extra replay từ {args.extra_replay.name}: {len(extra_replay)}")

    rows = build_train_rows(gold, pro, replay, args.gold_repeat, extra_replay)
    print(f"Train: Pro={len(pro)}, replay={len(replay)}, extra={len(extra_replay)}, gold-weighted={len(gold) * args.gold_repeat}")
    print(f"Total rows: {len(rows)}")

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, token=args.hf_token)
    model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_ID, token=args.hf_token)
    model.gradient_checkpointing_enable()
    model.config.use_cache = False

    dataset = Dataset.from_list(rows).train_test_split(test_size=0.02, seed=20260719)

    def tokenize(batch: dict[str, list[str]]) -> dict:
        inputs = tokenizer(batch["zh"], truncation=True, max_length=448)
        labels = tokenizer(text_target=batch["vi"], truncation=True, max_length=448)
        inputs["labels"] = labels["input_ids"]
        return inputs

    tokenized = dataset.map(tokenize, batched=True, remove_columns=["zh", "vi"])
    args.output_dir.mkdir(parents=True, exist_ok=True)
    training_args = Seq2SeqTrainingArguments(
        output_dir=str(args.output_dir),
        learning_rate=args.lr,
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.per_device_batch,
        per_device_eval_batch_size=args.per_device_batch,
        gradient_accumulation_steps=args.grad_accum,
        fp16=True,
        warmup_ratio=args.warmup_ratio,
        weight_decay=args.weight_decay,
        lr_scheduler_type="cosine",
        evaluation_strategy="steps",
        eval_steps=200,
        save_strategy="steps",
        save_steps=200,
        save_total_limit=3,
        logging_steps=20,
        predict_with_generate=True,
        generation_max_length=448,
        report_to="none",
        seed=20260719,
        dataloader_num_workers=2,
        ddp_find_unused_parameters=False,
    )
    trainer = Seq2SeqTrainer(
        model=model,
        args=training_args,
        train_dataset=tokenized["train"],
        eval_dataset=tokenized["test"],
        data_collator=DataCollatorForSeq2Seq(tokenizer, model=model),
        tokenizer=tokenizer,
    )
    trainer.train()
    trainer.save_model(str(args.output_dir))
    tokenizer.save_pretrained(str(args.output_dir))
    (args.output_dir / "training_mix.json").write_text(
        json.dumps({
            "model": MODEL_ID,
            "pro": len(pro),
            "replay": len(replay),
            "extra_replay": len(extra_replay),
            "gold": len(gold),
            "gold_repeat": args.gold_repeat,
            "total_rows": len(rows),
            "epochs": args.epochs,
            "lr": args.lr,
            "effective_batch": args.per_device_batch * args.grad_accum,
        }, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    if args.export_ct2:
        _export_ct2(args.output_dir)
    print(f"Xong: {args.output_dir}")


if __name__ == "__main__":
    main()
