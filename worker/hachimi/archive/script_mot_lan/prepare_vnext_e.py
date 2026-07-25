"""Chuẩn bị replay v-next E: lọc văn phong nghiêm và thêm booster nhỏ, cân bằng."""
from __future__ import annotations

import argparse
import json
import random
import re
from collections import defaultdict
from pathlib import Path

from kaggle_train import _pair, _register_ok, load_approved_gold, load_eval_reference


ROOT = Path(__file__).parent
DATASET = ROOT / "dataset"
GOLD = DATASET / "gold_approved_vnext.jsonl"
EVAL = DATASET / "eval_reference_60.jsonl"
HISTORICAL = ROOT / "approved_gold.jsonl"
BOOSTER = DATASET / "booster.jsonl"
REPLAY_OUT = DATASET / "replay_strict_vnext_e.jsonl"
REPORT_OUT = ROOT.parent / "experiments" / "hachimi_vnext_e_data.md"

BANNED_STYLE = re.compile(
    r"(?i)(?<!\w)(?:tôi|bạn|cậu|cháu|anh ta|cô ta|cô ấy|cậu ta|ông ta|bà ta)(?!\w)"
)
SUBJECTS = {"他": "hắn", "她": "nàng", "我": "ta"}
PREFIXES = ("此时，", "片刻后，", "闻言，", "下一刻，", "想到这里，", "说到这里，")


def load_rows(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def subject_of(source: str) -> str | None:
    text = source
    for prefix in PREFIXES:
        if text.startswith(prefix):
            text = text[len(prefix):]
            break
    return text[0] if text and text[0] in SUBJECTS else None


def strict_style_ok(target: str) -> bool:
    return _register_ok(target) and not BANNED_STYLE.search(target)


def historical_replay(blocked_zh: set[str]) -> tuple[list[dict], int]:
    rows: list[dict] = []
    removed = 0
    for row in load_rows(HISTORICAL):
        pair = _pair(row)
        if pair is None or pair[0] in blocked_zh or not strict_style_ok(pair[1]):
            removed += 1
            continue
        rows.append({"zh": pair[0], "vi": pair[1], "source_type": "historical_strict"})
    return rows, removed


def balanced_booster(blocked_zh: set[str], per_subject: int = 60) -> list[dict]:
    # 756 dòng đầu của artifact hiện hành là câu đơn: 7 tiền tố × 3 chủ ngữ × 36 động từ.
    singles = load_rows(BOOSTER)[:756]
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in singles:
        subject = subject_of(row["zh"])
        if (
            subject
            and row["zh"] not in blocked_zh
            and strict_style_ok(row["vi"])
        ):
            groups[subject].append(row)
    rng = random.Random(20260724)
    selected: list[dict] = []
    for subject in SUBJECTS:
        rows = groups[subject]
        if len(rows) < per_subject:
            raise RuntimeError(
                f"Booster chủ ngữ {subject} chỉ có {len(rows)}/{per_subject} dòng"
            )
        rng.shuffle(rows)
        selected.extend(
            {
                "zh": row["zh"],
                "vi": row["vi"],
                "source_type": f"register_booster_{SUBJECTS[subject]}",
            }
            for row in rows[:per_subject]
        )
    return selected


def self_check() -> None:
    assert not strict_style_ok('“Tôi hiểu rồi.”')
    assert not strict_style_ok("Cậu đi trước đi.")
    assert strict_style_ok("Hắn siết chặt song quyền.")
    assert subject_of("Lúc này không hợp.") is None
    assert subject_of("此时，她皱起眉头。") == "她"
    print("prepare_vnext_e OK")


def main() -> None:
    gold = load_approved_gold(GOLD)
    eval_rows = load_eval_reference(EVAL)
    blocked = {row["zh"] for row in gold} | {row["zh"] for row in eval_rows}
    historical, removed = historical_replay(blocked)
    booster = balanced_booster(blocked | {row["zh"] for row in historical})
    replay = historical + booster

    pairs = {(row["zh"], row["vi"]) for row in replay}
    sources = {row["zh"] for row in replay}
    if len(pairs) != len(replay) or len(sources) != len(replay):
        raise RuntimeError("Replay E còn cặp trùng hoặc cùng ZH nhiều bản VI")
    if sources & blocked:
        raise RuntimeError("Replay E trùng gold/eval")
    if any(not strict_style_ok(row["vi"]) for row in replay):
        raise RuntimeError("Replay E còn văn phong hiện đại bị cấm")

    REPLAY_OUT.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in replay),
        encoding="utf-8",
    )
    booster_counts = {
        subject: sum(
            row["source_type"] == f"register_booster_{target}"
            for row in booster
        )
        for subject, target in SUBJECTS.items()
    }
    REPORT_OUT.write_text(
        "\n".join([
            "# Dữ liệu ứng viên Hachimi v-next E",
            "",
            "Đây là artifact nghiên cứu; chưa train và không thay model production.",
            "",
            f"- Gold đã duyệt: {len(gold)} cặp, dự kiến lặp 3 lần.",
            f"- Eval khóa: {len(eval_rows)} cặp, không nằm trong train.",
            f"- Replay lịch sử giữ lại: {len(historical)} cặp; loại {removed} dòng "
            "do trùng holdout hoặc không qua cổng văn phong nghiêm.",
            f"- Booster nhỏ: {len(booster)} cặp; cân bằng {booster_counts}.",
            f"- Tổng replay E: {len(replay)}; tổng lượt train dự kiến: "
            f"{len(replay) + len(gold) * 3}.",
            "",
            "Recipe: train từ base Hachimi, 1 epoch, learning rate `1e-5`; đánh giá "
            "bằng chiến lược giữ nguyên dòng tối đa 448 token và output tối đa 448.",
            "",
            "Không dùng `register_gold`, `train_gold_vnext`, booster 1.200 dòng nguyên "
            "khối hoặc replay ngoài miền.",
        ]) + "\n",
        encoding="utf-8",
    )
    print(
        f"gold={len(gold)} eval={len(eval_rows)} historical={len(historical)} "
        f"booster={len(booster)} replay={len(replay)} "
        f"weighted_total={len(replay) + len(gold) * 3}"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    self_check() if args.self_check else main()
