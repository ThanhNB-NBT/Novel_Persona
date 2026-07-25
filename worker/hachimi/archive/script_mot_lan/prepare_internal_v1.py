"""Hợp nhất read-only các cặp nội bộ thành artifact để duyệt trước khi train."""
from __future__ import annotations

import argparse
import json
import re
import shutil
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).parent
DEFAULT_OUTPUT = ROOT / "prepared_v1"
SOURCES = (
    ("gold_approved_vnext", ROOT / "dataset" / "gold_approved_vnext.jsonl", "core_gold"),
    ("approved_gold", ROOT / "approved_gold.jsonl", "historical_gold"),
    ("register_gold", ROOT / "dataset" / "register_gold.jsonl", "historical_gold"),
    ("labeled_gold", ROOT / "dataset" / "labeled_gold.jsonl", "historical_gold"),
    ("booster", ROOT / "dataset" / "booster.jsonl", "synthetic"),
    ("train_v2", ROOT / "dataset" / "train_v2.jsonl", "replay"),
    ("replay_strict_vnext_e", ROOT / "dataset" / "replay_strict_vnext_e.jsonl", "derived_replay"),
    ("train_gold_vnext", ROOT / "dataset" / "train_gold_vnext.jsonl", "derived_manifest"),
)

HAN = re.compile(r"[\u3400-\u9fff]")
NUMBER = re.compile(r"\d+(?:\.\d+)?%?")
MOJIBAKE = re.compile(r"(?:\ufffd|Ãƒ|Ã‚(?=\s|[\"'.,;:!?])|Ã¢(?:â‚¬|â„¢|Å“|Å¾)|Ã„(?:â€˜|â€™))")
PLACEHOLDER = re.compile(r"(?:ZX\d{3}Q|⟦\d{3}⟧|(?<![A-Za-z])[JWZF]{2,4}(?![A-Za-z]))")
GAME_ENGLISH = re.compile(
    r"(?<![A-Za-z])(?:BOSS|NPC|PK|PVP|PVE|RPG|MMORPG|VIP|ID|GM|CD|EXP|HP|MP|BUFF|"
    r"DEBUFF|DPS|AOE|AFK|KDA|LOL|DOTA|FPS|MOBA|UI|APP|SERVER|RANK|TOP|ALL[- ]?IN)(?![A-Za-z])",
    re.I,
)
LATIN = re.compile(r"(?<![A-Za-z])[A-Za-z][A-Za-z0-9_-]{2,}(?![A-Za-z])")
QUOTE_PAIRS = (("\"", "\""), ("“", "”"), ("‘", "’"), ("「", "」"), ("『", "』"))
CORE_REQUIRED_FIELDS = {"zh", "vi", "status"}


def pair(row: dict) -> tuple[str, str]:
    return (
        str(row.get("zh") or row.get("source") or row.get("source_zh") or "").strip(),
        str(row.get("vi") or row.get("target") or row.get("target_vi") or row.get("proposed_vi") or "").strip(),
    )


def quotes_balanced(text: str) -> bool:
    return all(text.count(left) % 2 == 0 if left == right else text.count(left) == text.count(right)
               for left, right in QUOTE_PAIRS)


def reasons(zh: str, vi: str) -> list[str]:
    out: list[str] = []
    if not zh or not vi:
        out.append("missing_pair")
        return out
    if not HAN.search(zh):
        out.append("source_without_han")
    if HAN.search(vi):
        out.append("han_in_target")
    if not quotes_balanced(zh):
        out.append("source_quote_unbalanced")
    if not quotes_balanced(vi):
        out.append("target_quote_unbalanced")
    if NUMBER.findall(zh) != NUMBER.findall(vi):
        out.append("digits_mismatch")
    ratio = len(re.sub(r"\s+", "", vi)) / max(1, len(re.sub(r"\s+", "", zh)))
    if not 0.25 <= ratio <= 4:
        out.append("length_ratio")
    if MOJIBAKE.search(zh) or MOJIBAKE.search(vi):
        out.append("mojibake")
    if PLACEHOLDER.search(zh) or PLACEHOLDER.search(vi):
        out.append("placeholder_artifact")
    return out


def core_structural_reasons(zh: str, vi: str) -> list[str]:
    """Chỉ các lỗi phá cấu trúc mới được phép loại gold người dùng đã duyệt."""
    return [reason for reason in reasons(zh, vi) if reason in {
        "missing_pair", "han_in_target", "mojibake", "placeholder_artifact",
    }]


def game_or_latin(zh: str, vi: str) -> bool:
    if GAME_ENGLISH.search(zh) or GAME_ENGLISH.search(vi):
        return True
    source_words = {word.casefold() for word in LATIN.findall(zh)}
    target_words = {word.casefold() for word in LATIN.findall(vi)}
    return bool(source_words & target_words)


def load_source(name: str, path: Path, tier: str) -> list[dict]:
    rows: list[dict] = []
    for line, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        row = json.loads(raw)
        zh, vi = pair(row)
        rows.append({
            "source": name,
            "source_tier": tier,
            "source_line": line,
            "zh": zh,
            "vi": vi,
        })
    return rows


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def prepare(output: Path) -> dict[str, int]:
    all_rows = [row for source in SOURCES for row in load_source(*source)]
    by_pair: dict[tuple[str, str], list[dict]] = defaultdict(list)
    by_zh: dict[str, set[str]] = defaultdict(set)
    for row in all_rows:
        by_pair[(row["zh"], row["vi"])].append(row)
        by_zh[row["zh"]].add(row["vi"])
    core_rows = [row for row in all_rows if row["source_tier"] == "core_gold"]
    core_pairs = {(row["zh"], row["vi"]) for row in core_rows}
    core_zh = {row["zh"] for row in core_rows}
    non_core_conflicts = {
        zh for zh, targets in by_zh.items()
        if zh and zh not in core_zh and len(targets) > 1
    }

    output.mkdir(parents=True, exist_ok=True)
    core, game_review, replay_pool, quarantine = [], [], [], []
    accepted_pairs: set[tuple[str, str]] = set()
    for row in core_rows:
        key = row["zh"], row["vi"]
        row_reasons = core_structural_reasons(*key)
        if row_reasons:
            quarantine.append({**row, "reasons": sorted(set(row_reasons))})
            continue
        accepted_pairs.add(key)
        flags = [reason for reason in reasons(*key) if reason not in row_reasons]
        if len(by_pair[key]) > 1:
            flags.append("lower_tier_exact_duplicate")
        if len(by_zh[row["zh"]]) > 1:
            flags.append("lower_tier_same_zh_conflict")
        core.append({**row, "status": "approved", "flags": sorted(set(flags))})

    for row in (row for row in all_rows if row["source_tier"] != "core_gold"):
        key = row["zh"], row["vi"]
        row_reasons = reasons(*key)
        if row["zh"] in core_zh:
            row_reasons.append("exact_duplicate" if key in core_pairs else "same_zh_conflict")
        elif row["zh"] in non_core_conflicts:
            row_reasons.append("same_zh_conflict")
        elif key in accepted_pairs:
            row_reasons.append("exact_duplicate")
        if row_reasons:
            quarantine.append({**row, "reasons": sorted(set(row_reasons))})
            continue
        accepted_pairs.add(key)
        if game_or_latin(*key):
            game_review.append({**row, "status": "review_required"})
        else:
            replay_pool.append(row)

    write_jsonl(output / "core_gold.jsonl", core)
    write_jsonl(output / "game_english_review.jsonl", game_review)
    write_jsonl(output / "replay_review_pool.jsonl", replay_pool)
    write_jsonl(output / "train_replay.jsonl", [])
    write_jsonl(output / "quarantine.jsonl", quarantine)
    assert all(CORE_REQUIRED_FIELDS <= row.keys() and row["status"] == "approved" for row in core)
    source_counts = Counter(row["source"] for row in all_rows)
    reason_counts = Counter(reason for row in quarantine for reason in row["reasons"])
    manifest = {
        "scope": "paired internal gold/replay only; eval, raw source and candidate-only files are excluded",
        "sources": [{"name": name, "path": str(path.relative_to(ROOT)), "tier": tier,
                     "rows": source_counts[name]} for name, path, tier in SOURCES],
        "outputs": {"core_gold": len(core), "game_english_review": len(game_review),
                    "replay_review_pool": len(replay_pool), "train_replay": 0,
                    "quarantine": len(quarantine)},
        "quarantine_reasons": dict(sorted(reason_counts.items())),
        "same_zh_conflicts_outside_core": len(non_core_conflicts),
        "notes": [
            "game_english_review là hàng đợi duyệt, không phải dữ liệu train tự động.",
            "replay_review_pool chỉ qua gate cơ học; tuyệt đối không dùng làm train_replay trước khi duyệt alignment nghĩa.",
            "train_replay rỗng có chủ ý: chưa có replay nội bộ nào chứng minh được alignment nghĩa ở quy mô đủ train.",
            "Gold core người dùng đã duyệt là canonical: chỉ lỗi rỗng, Hán ở đích, mojibake hoặc placeholder mới bị loại.",
            "Bản sao hoặc biến thể cùng ZH ở tầng thấp bị cách ly, không được ghi đè core gold.",
        ],
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest["outputs"]


def self_check() -> None:
    assert quotes_balanced('“Ta nói: "được".”')
    assert not quotes_balanced('“Ta nói.')
    assert reasons("甲12", "Ất13") == ["digits_mismatch"]
    assert core_structural_reasons("甲12", "Ất13") == []
    assert CORE_REQUIRED_FIELDS <= {"zh": "甲", "vi": "Ất", "status": "approved"}.keys()
    assert game_or_latin("ID叫zhoKing", "ID tên zhoKing")
    assert "placeholder_artifact" in reasons("甲", "ZX001Q")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
        print("prepare_internal_v1 OK")
        return
    if args.output.exists():
        shutil.rmtree(args.output)
    counts = prepare(args.output)
    print(json.dumps(counts, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
