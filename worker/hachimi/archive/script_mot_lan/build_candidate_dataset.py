"""Tạo candidate Hachimi từ nguồn paired đã có trong cache, không tự duyệt gold."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path


HAN = re.compile(r"[\u3400-\u9fff]")
BAD = re.compile(r"[\x00\ufffd]|(?:\?{2,}|Ã.|Â.)")
MODERN = re.compile(r"\b(?:tôi|anh|em|cậu|bạn|mình|anh ấy|cô ấy|cậu ấy|cháu)\b", re.I)
LATIN_NAME = re.compile(r"\b[A-Z][a-z]{2,}\b")
PLACEHOLDER = re.compile(r"(?:\[/?(?:ZH|VI|UNK|MASK)\]|<[^>]+>|\{\{.+?\}\})", re.I)
GAME_WORDS = re.compile(r"(?:游戏|玩家|副本|技能|装备|任务|等级|升级|系统|属性|公会|战队|网游|Boss|NPC|服务器)", re.I)


def digest(text: str | bytes) -> str:
    payload = text if isinstance(text, bytes) else text.encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def source_hash(text: str) -> str:
    return digest(text.strip())


def pair_hash(zh: str, vi: str) -> str:
    return digest(zh.strip() + "\0" + vi.strip())


def balanced(text: str) -> bool:
    return all(text.count(a) == text.count(b) for a, b in (("“", "”"), ("「", "」"), ("『", "』"))) and text.count('"') % 2 == 0


def numbers(text: str) -> list[str]:
    return re.findall(r"\d+(?:[.:/]\d+)*", text)


def load_blocked(root: Path) -> set[str]:
    blocked: set[str] = set()
    paths = [
        root / "approved_gold.jsonl",
        root / "dataset" / "train_gold_vnext.jsonl",
        root / "dataset" / "gold_approved_vnext.jsonl",
        root / "dataset" / "train_game_english_approved.jsonl",
        root / "dataset" / "train_db_game_litrpg_approved.jsonl",
        root / "dataset" / "eval_reference_60.jsonl",
        root / "dataset" / "eval_game_english_locked.jsonl",
        root / "dataset" / "eval_vnext_300.jsonl",
    ]
    for path in paths:
        if not path.exists():
            continue
        for line in path.open(encoding="utf-8"):
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            zh = str(row.get("zh") or row.get("source_zh") or "").strip()
            if zh:
                blocked.add(source_hash(zh))
    return blocked


def classify(zh: str) -> str:
    return "game" if GAME_WORDS.search(zh) else "general"


def inspect(zh: str, vi: str, blocked: set[str]) -> list[str]:
    reasons: list[str] = []
    if not HAN.search(zh): reasons.append("source_without_han")
    if HAN.search(vi): reasons.append("target_han_leak")
    if BAD.search(zh) or BAD.search(vi): reasons.append("mojibake_or_null")
    if PLACEHOLDER.search(zh) or PLACEHOLDER.search(vi): reasons.append("placeholder")
    if not 8 <= len(zh) <= 500: reasons.append("source_length")
    if not 0.8 <= len(vi) / max(len(zh), 1) <= 6.0: reasons.append("length_ratio")
    if not balanced(zh) or not balanced(vi): reasons.append("unbalanced_quotes")
    if numbers(zh) != numbers(vi): reasons.append("number_mismatch")
    if re.sub(r"\W", "", zh.lower()) == re.sub(r"\W", "", vi.lower()): reasons.append("source_copy")
    if source_hash(zh) in blocked: reasons.append("leakage_blocked_source")
    return reasons


def self_check() -> None:
    assert balanced('“Ta đi.”') and not balanced('“Ta đi.')
    assert numbers("8:00 đến 10/12") == ["8:00", "10/12"]
    assert "target_han_leak" in inspect("这是测试句子", "Còn chữ 中", set())
    assert "number_mismatch" in inspect("测试 năm 2", "Bản dịch năm 3", set())
    print("build_candidate_dataset OK")


def main(parquet: Path, out: Path, root: Path, limit: int, shard_size: int) -> None:
    import pyarrow.parquet as pq

    out.mkdir(parents=True, exist_ok=True)
    blocked = load_blocked(root)
    seen_pairs: set[str] = set()
    seen_zh: dict[str, str] = {}
    raw_rows: list[tuple[int, str, str]] = []
    candidates: list[dict] = []
    rejects: list[dict] = []
    stats = Counter()
    flags = Counter()
    conflicts: set[str] = set()
    table = pq.ParquetFile(parquet)
    revision = digest(parquet.read_bytes())
    row_id = 0
    for batch in table.iter_batches(columns=["zh", "vi"], batch_size=8192):
        for zh_raw, vi_raw in zip(batch.column("zh").to_pylist(), batch.column("vi").to_pylist()):
            row_id += 1
            zh, vi = str(zh_raw or "").strip(), str(vi_raw or "").strip()
            stats["source_rows"] += 1
            raw_rows.append((row_id, zh, vi))
            if zh and zh in seen_zh and seen_zh[zh] != vi:
                conflicts.add(zh)
            else:
                seen_zh.setdefault(zh, vi)
    for row_id, zh, vi in raw_rows:
            reasons = inspect(zh, vi, blocked)
            if zh in conflicts:
                reasons.append("same_zh_conflict")
            key = pair_hash(zh, vi)
            if key in seen_pairs:
                reasons.append("duplicate_pair")
            if reasons:
                stats.update(reasons)
                rejects.append({"row_id": row_id, "source_hash": source_hash(zh), "pair_hash": key, "reasons": sorted(set(reasons))})
                continue
            seen_pairs.add(key)
            category = classify(zh)
            row_flags = {
                "quote_issue": not balanced(zh) or not balanced(vi),
                "numeric_issue": numbers(zh) != numbers(vi),
                "latin_name": bool(LATIN_NAME.search(vi)),
                "pronoun_modern": bool(MODERN.search(vi)),
                "artefact": bool(BAD.search(zh) or BAD.search(vi) or PLACEHOLDER.search(zh) or PLACEHOLDER.search(vi)),
                "game_keyword": category == "game",
            }
            flags.update(name for name, present in row_flags.items() if present)
            item = {
                "zh": zh, "vi": vi, "category": category,
                "source_dataset": "moa/Chinese-Vietnamese-literature",
                "source_revision": revision,
                "teacher_tier": "unknown",
                "teacher_model": "unknown",
                "row_id": row_id, "line_index": 0,
                "source_hash": source_hash(zh), "pair_hash": key,
                "flags": row_flags,
                "status": "candidate",
            }
            candidates.append(item)
    candidates.sort(key=lambda row: row["pair_hash"])
    eligible_rows = len(candidates)
    general = [r for r in candidates if r["category"] == "general"][:limit]
    game = [r for r in candidates if r["category"] == "game"][:5000]
    # Modern register is retained as a review signal, never silently relabeled as xianxia gold.
    selected = general + game
    for i in range(0, len(selected), shard_size):
        path = out / f"candidate_{i // shard_size:03d}.jsonl"
        path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in selected[i:i + shard_size]), encoding="utf-8")
    (out / "rejects.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rejects), encoding="utf-8")
    review = selected[::max(1, len(selected) // 120)][:120]
    (out / "review_pack.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in review), encoding="utf-8")
    manifest = {
        "status": "candidate_only", "source_path": str(parquet), "source_sha256": digest(parquet.read_bytes()),
        "source_rows": stats["source_rows"], "eligible_rows": eligible_rows, "candidate_rows": len(selected),
        "general_rows": len(general), "game_rows": len(game), "game_target": "2000-5000; unavailable from paired teacher source",
        "blocked_source_hashes": len(blocked), "conflict_source_count": len(conflicts),
        "teacher_priority": ["Gemini Pro", "Gemini Flash"], "teacher_tier_note": "Cache lacks tran-vi-teacher and teacher model metadata; all selected rows are unknown tier.",
        "shards": [p.name for p in sorted(out.glob("candidate_*.jsonl"))], "rejects": "rejects.jsonl", "review_pack": "review_pack.jsonl",
    }
    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = ["# Candidate data audit", "", "- Trạng thái: candidate chưa duyệt, không được nhập train.", f"- Dòng nguồn: **{stats['source_rows']:,}**; qua gate: **{eligible_rows:,}**; lấy mẫu: **{len(selected):,}**.", f"- General: **{len(general):,}**; game keyword provisional: **{len(game):,}**.", f"- Leakage: **0** (đã chặn {len(blocked):,} source hash).", f"- Conflict ZH: **{len(conflicts):,}**; reject records: **{len(rejects):,}**.", "", "## Reject reasons", ""]
    report.extend(f"- `{k}`: {v:,}" for k, v in stats.most_common() if k != "source_rows")
    report += ["", "## Accepted flags", ""]
    report.extend(f"- `{k}`: {flags[k]:,}" for k in ("quote_issue", "numeric_issue", "latin_name", "pronoun_modern", "artefact", "game_keyword"))
    report += ["", "## Blocker", "", "`ngocdang83/tran-vi-teacher` không có trong cache và không đọc được metadata teacher tier; cache model chỉ chứa tokenizer/model. Vì vậy không thể chứng minh ưu tiên Gemini Pro/Flash. 4.022 dòng game hiện chỉ là phân loại keyword của nguồn văn học, không phải game teacher đã xác nhận; cần nguồn paired game có provenance riêng trước khi dùng.", "", "## Provenance", "", "Mỗi dòng giữ dataset, revision hash của parquet, teacher tier/model, row_id, line_index, source_hash và pair_hash."]
    (out / "audit_report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--parquet", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).parent)
    parser.add_argument("--limit", type=int, default=10000)
    parser.add_argument("--shard-size", type=int, default=1000)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
    elif not args.parquet or not args.out:
        parser.error("cần --parquet và --out")
    else:
        main(args.parquet, args.out, args.root, args.limit, args.shard_size)
