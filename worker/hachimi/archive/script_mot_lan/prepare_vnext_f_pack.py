"""Đóng gói candidate F: gold đã duyệt và replay nghiêm streaming từ corpus gốc."""
from __future__ import annotations

import argparse
import zipfile
from pathlib import Path

from kaggle_train import load_approved_gold, load_eval_reference


ROOT = Path(__file__).parent
DATASET = ROOT / "dataset"
GOLD = DATASET / "gold_approved_vnext.jsonl"
EVAL = DATASET / "eval_reference_60.jsonl"
EXPERIMENTS = ROOT.parent / "experiments"
README = EXPERIMENTS / "hachimi_vnext_f_readme.md"
REPORT = EXPERIMENTS / "hachimi_vnext_f_data.md"
PACK = EXPERIMENTS / "hachimi-vnext-f-kaggle.zip"


def self_check() -> None:
    gold = load_approved_gold(GOLD)
    eval_rows = load_eval_reference(EVAL)
    assert len(gold) == 240
    assert len(eval_rows) == 60
    assert not ({row["zh"] for row in gold} & {row["zh"] for row in eval_rows})
    print("prepare_vnext_f_pack OK")


def main() -> None:
    self_check()
    with zipfile.ZipFile(PACK, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for source, name in (
            (ROOT / "kaggle_train.py", "kaggle_train.py"),
            (ROOT / "text_clean.py", "text_clean.py"),
            (GOLD, GOLD.name),
            (EVAL, EVAL.name),
            (README, README.name),
        ):
            archive.write(source, name)
    print(f"Đã tạo {PACK}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    self_check() if args.self_check else main()
