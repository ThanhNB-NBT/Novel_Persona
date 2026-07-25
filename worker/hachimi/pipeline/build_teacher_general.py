"""Build fail-closed, line-level General candidates from tran-vi-teacher."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from collections import Counter
from pathlib import Path

from huggingface_hub import hf_hub_download
from huggingface_hub.errors import GatedRepoError
from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parent
FINETUNE = ROOT.parent
sys.path.insert(0, str(FINETUNE))
from text_clean import clean_source

DATASET_ID = "ngocdang83/tran-vi-teacher"
REVISION = "63525802de537b11eb28aacbe1d2a23769548758"
REMOTE_FILE = "tran_vi_teacher_strict_clean_dedup_source.jsonl"
RESULTS = FINETUNE.parent / "teacher_build_20260725"
OUTPUT = RESULTS / "general_candidate.jsonl"
GAME_OUTPUT = RESULTS / "game_high_confidence_candidate.jsonl"
MANIFEST = RESULTS / "manifest.json"
AUDIT = RESULTS / "audit_report.md"
REJECTS = RESULTS / "rejects.jsonl"
REVIEW = RESULTS / "review_pack.jsonl"
BLOCKED = RESULTS / "BLOCKED.md"

HAN = re.compile(r"[\u3400-\u9fff]")
MODERN = re.compile(r"(?i)(?<!\w)(?:tôi|mình|bạn|cậu|cháu|anh ta|cô ta|cô ấy|cậu ta|ông ta|bà ta)(?!\w)")
MOJIBAKE = re.compile(r"(?:�|Ã.|Â.|â€|â€™|â€œ|â€)")
AUTHOR = re.compile(
    r"(?:tác giả có lời|lời tác giả|bản chương chưa hết|xin hãy chờ|"
    r"作者有话说|本章未完|求票|求收藏|求推荐|求月票|感谢支持)",
    re.I,
)
PLACEHOLDER = re.compile(r"(?:<[^>]{1,40}>|\{\{[^}]{1,40}\}\}|\[\[.*?\]\])")
PINYIN = re.compile(r"(?i)(?<![a-z])[a-z]{1,8}[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ](?:[a-z]{0,8})(?![a-z])")
PLAIN_PINYIN = re.compile(r"(?i)(?<=[\u3400-\u9fff])(?:jing|xing|se|she|rou|jiao)(?=[\u3400-\u9fff])")
QUOTE_PAIRS = (("“", "”"), ("‘", "’"), ("「", "」"), ("『", "』"))
GAME_EXPLICIT = re.compile(
    r"(?:NPC|BOSS|副本|玩家|职业玩家|网游|网络游戏|电子游戏|游戏|"
    r"服务器|游戏币|世界频道|PK|PVP|PVE|RPG|MMORPG|MOBA|FPS)",
    re.I,
)
GAME_MECHANICS = re.compile(r"(?:技能|装备|等级|掉落|任务|血量|蓝量|生命值|魔法值|经验值|冷却|CD|HP|MP|buff|debuff|职业|转职)", re.I)


def source_hash(zh: str) -> str:
    return hashlib.sha256(clean_source(zh).encode("utf-8")).hexdigest()


def pair_hash(zh: str, vi: str) -> str:
    return hashlib.sha256(f"{clean_source(zh)}\0{vi.strip()}".encode("utf-8")).hexdigest()


def balanced_quotes(text: str) -> bool:
    return text.count('"') % 2 == 0 and all(text.count(left) == text.count(right) for left, right in QUOTE_PAIRS)


def line_ok(zh: str, vi: str) -> str | None:
    zh, vi = clean_source(zh), vi.strip()
    if not zh or not vi or not HAN.search(zh):
        return "empty_or_non_han_source"
    if HAN.search(vi):
        return "han_leak"
    if MOJIBAKE.search(zh) or MOJIBAKE.search(vi):
        return "mojibake"
    if not balanced_quotes(zh) or not balanced_quotes(vi):
        return "unbalanced_quotes"
    if MODERN.search(vi):
        return "modern_register"
    if AUTHOR.search(zh) or AUTHOR.search(vi):
        return "author_or_meta"
    if PLACEHOLDER.search(zh) or PLACEHOLDER.search(vi):
        return "placeholder"
    if PINYIN.search(zh) or PLAIN_PINYIN.search(zh):
        return "pinyin_in_source"
    if re.findall(r"\d+", zh) != re.findall(r"\d+", vi):
        return "number_mismatch"
    ratio = len(re.sub(r"\s+", "", vi)) / max(1, len(re.sub(r"\s+", "", zh)))
    if not 0.25 <= ratio <= 4.0:
        return "length_ratio"
    return None


def high_confidence_game(zh: str) -> bool:
    """Avoid the old one-keyword classifier: game needs two independent signals."""
    strong = len(GAME_EXPLICIT.findall(zh))
    mechanics = len(GAME_MECHANICS.findall(zh))
    return strong >= 1 and mechanics >= 1


def game_terms_ok(zh: str, vi: str) -> bool:
    target = vi.lower()
    return not (
        ("叮" in zh and re.search(r"(?<!\w)đinh(?!\w)", target))
        or ("副本" in zh and "phụ bản" in target)
    )


def blocked_hashes() -> set[str]:
    paths = [
        FINETUNE / "dataset" / "eval_reference_60.jsonl",
        FINETUNE / "dataset" / "eval_game_english_locked.jsonl",
        FINETUNE / "dataset" / "gold_approved_vnext.jsonl",
        FINETUNE / "prepared_v1" / "core_gold.jsonl",
        FINETUNE / "dataset" / "train_game_english_approved.jsonl",
        FINETUNE / "dataset" / "train_db_game_litrpg_approved.jsonl",
        FINETUNE.parent / "experiments" / "hachimi_vnext_e_fullchapters.jsonl",
    ]
    blocked: set[str] = set()
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(f"Thiếu tập khóa leakage: {path}")
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            row = json.loads(line)
            zh = clean_source(str(row.get("zh") or row.get("source_zh") or ""))
            if not zh:
                raise ValueError(f"{path}:{number} thiếu nguồn Trung")
            blocked.add(source_hash(zh))
            blocked.update(
                source_hash(source_line)
                for source_line in zh.splitlines()
                if clean_source(source_line)
            )
    return blocked


def download() -> Path:
    token = os.environ.get("HF_TOKEN") or dotenv_values(FINETUNE.parent / ".env").get("HF_TOKEN")
    path = hf_hub_download(
        DATASET_ID,
        REMOTE_FILE,
        repo_type="dataset",
        revision=REVISION,
        cache_dir=FINETUNE.parent / ".hf-cache-teacher",
        token=token or None,
    )
    return Path(path)


def valid_row(row: dict) -> tuple[str, str, dict] | str:
    meta = row.get("meta")
    if not isinstance(meta, dict):
        return "missing_metadata"
    tier, model = str(meta.get("teacher_tier") or "").lower(), str(meta.get("model") or "")
    if tier not in {"pro", "flash"} or not model.startswith("gemini-"):
        return "missing_or_disallowed_teacher"
    if meta.get("finish_reason") != "stop" or meta.get("quality_bucket") != "strict_clean":
        return "incomplete_teacher_row"
    zh, vi = str(row.get("source_zh") or row.get("source") or ""), str(row.get("target_vi") or row.get("target") or "")
    if not zh or not vi:
        return "missing_pair"
    zh_lines, vi_lines = zh.splitlines(), vi.splitlines()
    if not zh_lines or len(zh_lines) != len(vi_lines):
        return "line_alignment"
    if meta.get("source_line_count") != len(zh_lines) or meta.get("target_line_count") != len(vi_lines):
        return "metadata_line_count"
    return zh, vi, meta


def build(limit: int = 10_000, game_limit: int = 5_000) -> dict:
    if not 5_000 <= limit <= 10_000:
        raise ValueError("General candidate phải trong 5.000–10.000 dòng")
    RESULTS.mkdir(parents=True, exist_ok=True)
    source = download()
    blocked = blocked_hashes()
    candidates: dict[str, dict] = {}
    conflicts: set[str] = set()
    rejected = Counter()
    rejects: list[dict] = []
    with source.open("r", encoding="utf-8") as handle:
        for row_number, line in enumerate(handle, 1):
            row = json.loads(line)
            checked = valid_row(row)
            if isinstance(checked, str):
                rejected[checked] += 1
                continue
            zh_block, vi_block, meta = checked
            for line_index, (zh, vi) in enumerate(zip(zh_block.splitlines(), vi_block.splitlines())):
                zh, vi = clean_source(zh), vi.strip()
                reason = line_ok(zh, vi)
                digest = source_hash(zh)
                if not reason and digest in blocked:
                    reason = "leakage"
                if reason:
                    rejected[reason] += 1
                    if len(rejects) < 500:
                        rejects.append({"reason": reason, "id": row.get("id"), "line_index": line_index, "zh": zh, "vi": vi})
                    continue
                item = {
                    "status": "candidate_teacher",
                    "zh": zh,
                    "vi": vi,
                    "source_hash": digest,
                    "pair_hash": pair_hash(zh, vi),
                    "provenance": {
                        "dataset": DATASET_ID,
                        "revision": REVISION,
                        "file": REMOTE_FILE,
                        "row_id": row.get("id"),
                        "row_number": row_number,
                        "line_index": line_index,
                        "source_dataset": meta.get("source_dataset"),
                        "stem": meta.get("stem"),
                        "teacher_tier": meta["teacher_tier"],
                        "teacher_model": meta["model"],
                    },
                }
                old = candidates.get(digest)
                if old and old["vi"] != vi:
                    candidates.pop(digest, None)
                    conflicts.add(digest)
                    rejected["source_conflict"] += 1
                elif not old and digest not in conflicts:
                    candidates[digest] = item
    game_signal_pool = [item for item in candidates.values() if high_confidence_game(item["zh"])]
    game_pool = [item for item in game_signal_pool if game_terms_ok(item["zh"], item["vi"])]
    general_pool = [item for item in candidates.values() if not high_confidence_game(item["zh"])]
    ranked = sorted(
        general_pool,
        key=lambda item: (0 if item["provenance"]["teacher_tier"] == "pro" else 1, item["source_hash"]),
    )[:limit]
    if len(ranked) < limit:
        raise RuntimeError(f"Fail-closed: chỉ có {len(ranked)}/{limit} dòng Pro/Flash qua toàn bộ gate")
    OUTPUT.write_text("".join(json.dumps(item, ensure_ascii=False) + "\n" for item in ranked), encoding="utf-8")
    game = sorted(game_pool, key=lambda item: (0 if item["provenance"]["teacher_tier"] == "pro" else 1, item["source_hash"]))[:game_limit]
    GAME_OUTPUT.write_text("".join(json.dumps(item, ensure_ascii=False) + "\n" for item in game), encoding="utf-8")
    REJECTS.write_text("".join(json.dumps(item, ensure_ascii=False) + "\n" for item in rejects), encoding="utf-8")
    review: list[dict] = []
    for name, pool, tier, cap in (
        ("general_pro", ranked, "pro", 50),
        ("general_flash", ranked, "flash", 25),
        ("game_pro", game, "pro", 25),
        ("game_flash", game, "flash", 25),
    ):
        review.extend([
            {**item, "review_stratum": name}
            for item in pool
            if item["provenance"]["teacher_tier"] == tier
        ][:cap])
    REVIEW.write_text("".join(json.dumps(item, ensure_ascii=False) + "\n" for item in review), encoding="utf-8")
    manifest = {
        "status": "candidate_only_not_approved",
        "dataset": DATASET_ID,
        "revision": REVISION,
        "file": REMOTE_FILE,
        "rows": len(ranked),
        "tiers": dict(Counter(item["provenance"]["teacher_tier"] for item in ranked)),
        "game_high_confidence": {"rows": len(game), "tiers": dict(Counter(item["provenance"]["teacher_tier"] for item in game)), "rule": "explicit_game_signal_plus_game_mechanic"},
        "game_term_rejects": len(game_signal_pool) - len(game_pool),
        "review_strata": dict(Counter(item["review_stratum"] for item in review)),
        "blocked_source_hashes": len(blocked),
        "source_conflicts": len(conflicts),
        "candidate_sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        "filters": ["pro_or_flash_only", "strict_clean_stop", "equal_paragraph_line_count", "line_gates", "source_dedup_conflict", "exact_eval_gold_leakage"],
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    AUDIT.write_text(
        "# Audit candidate General từ tran-vi-teacher\n\n"
        f"- Trạng thái: `candidate_only_not_approved`\n- Dòng: **{len(ranked)}**\n"
        f"- Tier: `{manifest['tiers']}`\n- Game high-confidence: **{len(game)}** (ít nhất hai tín hiệu game độc lập)\n- Leakage exact: **0**\n- Source conflict: **{len(conflicts)}**\n"
        "- Corpus hoặc metadata thiếu sẽ làm pipeline fail-closed; không có fallback sang nguồn khác.\n\n"
        "## Bị loại\n\n" + "\n".join(f"- {key}: {value}" for key, value in rejected.most_common()) + "\n",
        encoding="utf-8",
    )
    return manifest


def write_blocker(error: GatedRepoError) -> None:
    """Persist the access failure; never substitute another corpus."""
    RESULTS.mkdir(parents=True, exist_ok=True)
    for path in (OUTPUT, GAME_OUTPUT, AUDIT, REJECTS, REVIEW):
        path.unlink(missing_ok=True)
    message = (
        "# Candidate General bị chặn\n\n"
        f"- Dataset bắt buộc: `{DATASET_ID}` @ `{REVISION}`\n"
        "- Trạng thái: **không tạo candidate**. File dữ liệu bị gated và phiên chạy không có `HF_TOKEN` hợp lệ.\n"
        "- Hành động cần thiết: tài khoản Hugging Face được cấp quyền dataset, sau đó đặt `HF_TOKEN` cho lệnh build.\n"
        "- Không có fallback sang MOA, Flash-Lite hay corpus khác.\n\n"
        f"Chi tiết kỹ thuật: `{type(error).__name__}`.\n"
    )
    BLOCKED.write_text(message, encoding="utf-8")
    MANIFEST.write_text(json.dumps({
        "status": "blocked_no_candidate_created",
        "dataset": DATASET_ID,
        "revision": REVISION,
        "reason": "gated_dataset_requires_authenticated_hf_token",
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def self_check() -> None:
    assert line_ok("他有12枚。", "Hắn có 12 viên.") is None
    assert line_ok("他有12枚。", "Hắn có 21 viên.") == "number_mismatch"
    assert line_ok("他说：\"好。", "Hắn nói: \"Được.") == "unbalanced_quotes"
    assert line_ok("他", "Tôi hiểu.") == "modern_register"
    assert line_ok("他", "Hắn nói tiếng 中文.") == "han_leak"
    assert line_ok("他的属xing很高。", "Thuộc tính của hắn rất cao.") == "pinyin_in_source"
    assert high_confidence_game("玩家使用技能击败BOSS")
    assert not high_confidence_game("这个赌命游戏又要开始了")
    assert not high_confidence_game("法术公会发布内门任务")
    assert not high_confidence_game("系统提示任务完成")
    assert not game_terms_ok("叮！任务完成", "Đinh! Hoàn thành nhiệm vụ.")
    assert not game_terms_ok("进入副本", "Tiến vào phụ bản.")
    assert game_terms_ok("进入副本", "Tiến vào phó bản.")
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "eval.jsonl"
        path.write_text('{"zh":"甲","reference_vi":"Ất"}\n', encoding="utf-8")
        assert source_hash("甲") != source_hash("乙")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--limit", type=int, default=10_000)
    parser.add_argument("--game-limit", type=int, default=5_000)
    args = parser.parse_args()
    if args.self_check:
        self_check()
        print("OK")
    else:
        try:
            print(json.dumps(build(args.limit, args.game_limit), ensure_ascii=False, indent=2))
        except GatedRepoError as error:
            write_blocker(error)
            raise SystemExit("Dataset gated: cần HF_TOKEN có quyền; không tạo candidate fallback.") from error
