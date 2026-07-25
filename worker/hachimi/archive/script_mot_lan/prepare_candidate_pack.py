"""Tạo candidate shards Hachimi từ các cặp đã có, không phê duyệt hay train."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


HAN = re.compile(r"[\u3400-\u9fff]")
MOJIBAKE = re.compile(r"(?:Ã.|Â.|â€|�|\\u00[a-f0-9]{2})")
PLACEHOLDER = re.compile(r"(?:\*{2,}|\[/?(?:ZH|VI|UNK|MASK)\]|<[^>]+>|\{\{.+?\}\})", re.I)
MODERN = re.compile(r"\b(?:tôi|mình|cậu|bạn|cháu|anh ấy|cô ấy|cậu ấy)\b", re.I)
GAME = re.compile(r"(?:游戏|玩家|副本|技能|装备|任务|等级|升级|系统|属性|公会|战队|网游|服务器|NPC|Boss|BOSS|RPG)")
AD = re.compile(r"(?:求票|求收藏|求推荐|求月票|作者的话|感谢支持|请投票|PS：|P\.S\.)", re.I)


def digest(text: str | bytes) -> str:
    payload = text if isinstance(text, bytes) else text.encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def source_hash(text: str) -> str:
    return digest(" ".join(text.split()))


def pair_hash(zh: str, vi: str) -> str:
    return digest(" ".join(zh.split()) + "\0" + " ".join(vi.split()))


def numbers(text: str) -> list[str]:
    return re.findall(r"\d+(?:[.:/]\d+)*", text)


def balanced(text: str) -> bool:
    return all(text.count(a) == text.count(b) for a, b in (("“", "”"), ("「", "」"), ("『", "』"))) and text.count('"') % 2 == 0


def category(row: dict) -> str:
    text = " ".join(str(row.get(k) or "") for k in ("zh", "domain", "genre", "category", "tags"))
    return "game" if GAME.search(text) else "literary"


def read_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as handle:
        for line_index, line in enumerate(handle):
            if line.strip():
                row = json.loads(line)
                row["_line_index"] = line_index
                rows.append(row)
    return rows


def eval_hashes(root: Path) -> set[str]:
    paths = [
        root / "dataset" / "eval_reference_60.jsonl",
        root / "dataset" / "eval_game_english_locked.jsonl",
        root / "dataset" / "eval_vnext_300.jsonl",
        root / "dataset" / "db_game_litrpg_eval_blocked.jsonl",
    ]
    blocked = set()
    for path in paths:
        if path.exists():
            for row in read_jsonl(path):
                zh = str(row.get("zh") or row.get("source_zh") or "").strip()
                if zh:
                    blocked.add(source_hash(zh))
    return blocked


def self_check() -> None:
    assert balanced('“Ta đi.”') and not balanced('“Ta đi.')
    assert numbers("8:00 đến 10/12") == ["8:00", "10/12"]
    assert category({"zh": "玩家打开系统任务"}) == "game"
    assert "source_copy" in inspect("测试句子", "测试句子", set())
    print("prepare_candidate_pack OK")


def inspect(zh: str, vi: str, blocked: set[str]) -> list[str]:
    reasons = []
    if not HAN.search(zh): reasons.append("source_without_han")
    if HAN.search(vi): reasons.append("target_han_leak")
    if MOJIBAKE.search(zh) or MOJIBAKE.search(vi): reasons.append("mojibake")
    if PLACEHOLDER.search(zh) or PLACEHOLDER.search(vi): reasons.append("placeholder")
    if AD.search(zh) or AD.search(vi): reasons.append("author_or_advertisement")
    if not 4 <= len(zh) <= 700: reasons.append("source_length")
    if not 0.35 <= len(vi) / max(len(zh), 1) <= 8: reasons.append("length_ratio")
    if not balanced(zh) or not balanced(vi): reasons.append("unbalanced_quotes")
    if numbers(zh) != numbers(vi): reasons.append("number_mismatch")
    if source_hash(zh) in blocked: reasons.append("leakage_blocked")
    if "".join(re.findall(r"[\u4e00-\u9fffA-Za-z0-9]", zh)) == "".join(re.findall(r"[\u4e00-\u9fffA-Za-z0-9]", vi)):
        reasons.append("source_copy")
    return reasons


def normalise(row: dict, source_file: str, source_revision: str, source_dataset: str) -> dict:
    zh = str(row.get("zh") or row.get("source_zh") or "").strip()
    vi = str(row.get("vi") or row.get("current_vi") or row.get("proposed_vi") or "").strip()
    return {
        "zh": zh,
        "vi": vi,
        "category": category(row),
        "source_dataset": source_dataset,
        "source_file": source_file,
        "source_revision": source_revision,
        "teacher_model": str(row.get("teacher_model") or row.get("source_model") or "unknown"),
        "teacher_tier": str(row.get("teacher_tier") or "unknown"),
        "row_id": row.get("row_id") or row.get("id") or f"line-{row['_line_index']}",
        "line_index": row.get("line_index", row["_line_index"]),
        "source_hash": source_hash(zh),
        "pair_hash": pair_hash(zh, vi),
        "status": "candidate",
        "alignment": {"mode": "row_atomic", "safe": True},
        "flags": {"modern_register": bool(MODERN.search(vi)), "game_keyword": category(row) == "game"},
    }


def main(root: Path, out: Path, target_literary: int, target_game: int, shard_size: int, prefix: str) -> None:
    inputs = [
        (root / "dataset" / "gold_approved_vnext.jsonl", "gold_approved_vnext", "human_reviewed"),
        (root / "dataset" / "train_db_game_litrpg_approved.jsonl", "user_review_db_game_litrpg", "human_reviewed"),
        (root / "dataset" / "train_game_english_approved.jsonl", "user_review_game_english", "human_reviewed"),
        (root.parent / "experiments" / "literature_replay_screened_2000.jsonl", "moa/Chinese-Vietnamese-literature", "unknown"),
        (root / "_kaggle_upload" / "historical_replay.jsonl", "local_historical_subset_of_tran-vi-teacher", "unknown"),
        (root / "dataset" / "train_v2.jsonl", "local_train_v2", "unknown"),
        (root / "dataset" / "train_game_english_review_200.jsonl", "review_candidate_game_english", "unknown"),
    ]
    blocked = eval_hashes(root)
    gold_hashes = set()
    for path, _, _ in inputs[:3]:
        for row in read_jsonl(path):
            zh = str(row.get("zh") or "").strip()
            if zh: gold_hashes.add(source_hash(zh))
    all_rows = []
    rejects = []
    stats = Counter()
    source_stats = Counter()
    conflicts = defaultdict(set)
    for path, dataset, tier in inputs:
        if not path.exists():
            continue
        revision = digest(path.read_bytes())
        for row in read_jsonl(path):
            item = normalise(row, str(path.relative_to(root.parent.parent)), revision, dataset)
            item["teacher_tier"] = tier if item["teacher_tier"] == "unknown" else item["teacher_tier"]
            conflicts[item["source_hash"]].add(item["vi"])
            all_rows.append(item)
    seen_pair = set()
    seen_source = set()
    for item in all_rows:
        is_gold = item["source_dataset"] in {"gold_approved_vnext", "user_review_db_game_litrpg", "user_review_game_english"}
        reasons = inspect(item["zh"], item["vi"], blocked if is_gold else blocked | gold_hashes)
        if len(conflicts[item["source_hash"]]) > 1:
            reasons.append("same_zh_conflict")
        if item["pair_hash"] in seen_pair:
            reasons.append("duplicate_pair")
        if item["source_hash"] in seen_source:
            reasons.append("duplicate_source")
        if item["source_hash"] in gold_hashes and item["source_dataset"] not in {"gold_approved_vnext", "user_review_db_game_litrpg", "user_review_game_english"}:
            reasons.append("gold_overlap")
        if reasons:
            item["reasons"] = sorted(set(reasons))
            rejects.append(item)
            stats.update(item["reasons"])
            source_stats[(item["source_dataset"], "rejected")] += 1
        else:
            seen_pair.add(item["pair_hash"])
            seen_source.add(item["source_hash"])
            source_stats[(item["source_dataset"], "candidate")] += 1
    candidates = [r for r in all_rows if r["pair_hash"] in seen_pair and "reasons" not in r]
    # Gold được giữ nguyên trong input; candidate mới chỉ lấy sau khi khóa 323 gold.
    gold = [r for r in candidates if r["source_dataset"] in {"gold_approved_vnext", "user_review_db_game_litrpg", "user_review_game_english"}]
    non_gold = [r for r in candidates if r not in gold]
    literary = [r for r in non_gold if r["category"] == "literary"][:target_literary]
    game = [r for r in non_gold if r["category"] == "game"][:target_game]
    selected = gold + literary + game
    out.mkdir(parents=True, exist_ok=True)
    for offset in range(0, len(selected), shard_size):
        (out / f"{prefix}_{offset // shard_size:03d}.jsonl").write_text(
            "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in selected[offset:offset + shard_size]), encoding="utf-8"
        )
    (out / f"{prefix}_rejects.jsonl").write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rejects), encoding="utf-8")
    review = selected[::max(1, len(selected) // 160)][:160]
    (out / f"{prefix}_review_pack.jsonl").write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in review), encoding="utf-8")
    manifest = {
        "status": "candidate_only",
        "base_model": "ngocdang83/HachimiMT-60-zh-vi",
        "candidate_rows": len(selected), "gold_rows_reused": len(gold),
        "literary_rows": len(literary), "game_rows": len(game),
        "rejected_rows": len(rejects), "eval_blocked_source_hashes": len(blocked),
        "teacher_priority": ["Gemini Pro", "Gemini Flash"],
        "teacher_provenance_note": "Không gán Pro/Flash cho dòng local khi chưa có metadata HF; unknown cần chạy lại sau khi có HF_TOKEN.",
        "hf_dataset": {"id": "ngocdang83/tran-vi-teacher", "revision": "63525802de537b11eb28aacbe1d2a23769548758", "license": "cc-by-4.0", "access": "blocked_without_HF_TOKEN"},
        "shards": [p.name for p in sorted(out.glob(f"{prefix}_*.jsonl")) if "rejects" not in p.name and "review_pack" not in p.name],
        "reject_list": f"{prefix}_rejects.jsonl", "review_pack": f"{prefix}_review_pack.jsonl",
        "counts_by_source_and_status": {f"{source}|{status}": count for (source, status), count in sorted(source_stats.items())},
    }
    (out / f"{prefix}_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = ["# Candidate pack audit", "", "- Trạng thái: candidate chưa duyệt; không phải manifest train.", f"- Candidate: **{len(selected):,}** (gold giữ lại **{len(gold):,}**, văn học **{len(literary):,}**, game **{len(game):,}**).", f"- Bị loại: **{len(rejects):,}**; eval/full-chapter hashes bị chặn: **{len(blocked):,}**.", "", "## Lý do loại", ""]
    report.extend(f"- `{reason}`: {count:,}" for reason, count in stats.most_common())
    report += ["", "## Provenance caveat", "", "HF `ngocdang83/tran-vi-teacher` đã xác nhận revision và license nhưng file gated không tải được vì môi trường thiếu `HF_TOKEN`. Các dòng local không có metadata teacher được giữ `teacher_tier=unknown`; không được coi là Gemini Pro/Flash và không được tự động approved.", "", "## File kiểm duyệt", "", "`review_pack.jsonl` có mẫu đại diện theo nhóm; `rejects.jsonl` giữ lý do từng dòng."]
    (out / f"{prefix}_audit_report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).parent)
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "prepared_v1")
    parser.add_argument("--prefix", default="candidate_pack")
    parser.add_argument("--literary", type=int, default=6000)
    parser.add_argument("--game", type=int, default=2500)
    parser.add_argument("--shard-size", type=int, default=1000)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
    else:
        main(args.root, args.out, args.literary, args.game, args.shard_size, args.prefix)
