"""Trích ca võng du/LitRPG từ DB để người dùng duyệt; không tự approved.

Chỉ lấy chương đã có đủ gốc Trung và bản Việt, căn dòng nghiêm ngặt, giữ
provenance và không tự bịa bản dịch đề xuất. Người duyệt mới điền proposed_vi.
"""
from __future__ import annotations

import hashlib
import json
import re
import argparse
from collections import Counter
from pathlib import Path

from novelworker import db
from hachimi_finetune.text_clean import clean_source


ROOT = Path(__file__).parent
DATASET = ROOT / "dataset"
EXPERIMENTS = ROOT.parent / "experiments"
OUT = DATASET / "db_game_litrpg_review_80.jsonl"
REPORT = EXPERIMENTS / "db_game_litrpg_review_80.md"
APPROVED_OUT = DATASET / "train_db_game_litrpg_approved.jsonl"
EVAL_BLOCKED_OUT = DATASET / "db_game_litrpg_eval_blocked.jsonl"
EDIT_PATHS = (
    DATASET / "db_game_litrpg_review_edits_a.jsonl",
    DATASET / "db_game_litrpg_review_edits_b.jsonl",
)

# Tám truyện võng du thật và sáu truyện hệ thống/LitRPG. Không trộn tier khi report.
NOVELS = {
    1320: "true_online_game", 1382: "true_online_game", 1561: "true_online_game",
    1564: "true_online_game", 1578: "true_online_game", 1582: "true_online_game",
    1598: "true_online_game", 1602: "true_online_game",
    24: "system_litrpg", 1380: "system_litrpg", 1735: "system_litrpg",
    1788: "system_litrpg", 1916: "system_litrpg", 1932: "system_litrpg",
}

CATEGORY_TERMS = {
    "bang_thuoc_tinh_ui": ("属性", "面板", "界面", "提示", "通知", "列表", "菜单", "栏位", "按钮", "背包", "仓库"),
    "chi_so": ("生命", "血量", "攻击", "防御", "力量", "敏捷", "智力", "体力", "经验", "伤害", "暴击", "命中", "闪避", "数值", "百分比"),
    "class_nghe": ("职业", "战士", "法师", "牧师", "刺客", "弓箭手", "骑士", "盗贼", "召唤师"),
    "skill_cd_buff": ("技能", "冷却", "天赋", "被动", "主动", "施法", "眩晕", "沉默", "中毒", "增益", "减益", "治疗", "仇恨"),
    "trang_bi_pham_cap": ("装备", "武器", "护甲", "戒指", "品质", "品级", "稀有", "史诗", "传说", "神话", "黑铁", "青铜", "白银", "黄金", "钻石"),
    "quest_dungeon_boss": ("任务", "副本", "地下城", "秘境", "关卡", "首杀", "BOSS", "boss", "怪物", "野怪", "首领", "新手村"),
    "rank_pvp": ("排名", "段位", "王者", "大师", "钻石", "白金", "青铜", "PK", "竞技", "对战", "联赛", "战队", "排位"),
    "economy_crafting": ("金币", "银币", "交易", "拍卖", "市场", "商店", "制作", "锻造", "材料", "配方", "货币", "价格", "购买", "出售"),
    "guild_chat_party": ("公会", "帮会", "队伍", "组队", "聊天", "频道", "好友", "私聊", "喊话", "团队"),
    "respawn_drop": ("复活", "重生", "掉落", "爆出", "刷新", "死亡", "尸体", "掉宝", "战利品", "回城"),
    "english_id": ("ID", "NPC", "BOSS", "PK", "PVP", "PVE", "RPG", "MMORPG", "VIP", "GM", "CD", "EXP", "HP", "MP", "BUFF"),
}
GARBAGE = re.compile(r"作者|本章完|求收藏|求推荐|求月票|QQ群|公众号|微信|http|www\.|不jing", re.I)


def digest(zh: str) -> str:
    return hashlib.sha256(clean_source(zh).encode("utf-8")).hexdigest()


def jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def blocked_hashes() -> set[str]:
    paths = (
        ROOT / "prepared_v1" / "core_gold.jsonl",
        DATASET / "eval_reference_60.jsonl",
        DATASET / "eval_game_english_locked.jsonl",
        DATASET / "train_game_english_approved.jsonl",
    )
    blocked = set()
    for path in paths:
        if not path.exists():
            continue
        for row in jsonl(path):
            zh = row.get("zh") or row.get("source_zh")
            if zh:
                blocked.add(row.get("source_hash") or digest(zh))
    return blocked


def categories(zh: str) -> list[str]:
    return [name for name, terms in CATEGORY_TERMS.items() if any(term in zh for term in terms)]


def quotes_balanced(text: str) -> bool:
    return (
        text.count("“") == text.count("”")
        and text.count("‘") == text.count("’")
        and text.count("「") == text.count("」")
        and text.count("『") == text.count("』")
        and text.count('"') % 2 == 0
    )


def usable(zh: str, vi: str) -> bool:
    if not (12 <= len(zh) <= 220 and 12 <= len(vi) <= 560):
        return False
    if GARBAGE.search(zh) or GARBAGE.search(vi) or not quotes_balanced(zh):
        return False
    ratio = len(vi) / max(len(zh), 1)
    return 1.1 <= ratio <= 5.2


def context(lines: list[str], index: int) -> str:
    start, end = max(0, index - 1), min(len(lines), index + 2)
    return "\n".join(lines[start:end])


def merge_proposals(rows: list[dict], edits: list[dict]) -> list[dict]:
    by_hash = {row["source_hash"]: row for row in edits}
    if len(by_hash) != len(edits):
        raise RuntimeError("Edit đề xuất có source_hash trùng")
    row_hashes = {row["source_hash"] for row in rows}
    if set(by_hash) != row_hashes:
        missing = [
            (row["novel_id"], row["chapter_index"], row["zh"], row["current_vi"])
            for row in rows
            if row["source_hash"] not in by_hash
        ]
        raise RuntimeError(
            f"Edit không khớp review pack: thiếu {len(row_hashes - set(by_hash))}, "
            f"thừa {len(set(by_hash) - row_hashes)}; "
            f"missing={missing}"
        )
    return [
        {
            **row,
            "proposed_vi": by_hash[row["source_hash"]]["proposed_vi"],
            "issue": by_hash[row["source_hash"]]["issue"],
            "proposal_state": "ready_for_user_review",
        }
        for row in rows
    ]


def main() -> None:
    sb = db.sb()
    block = blocked_hashes()
    candidates = []
    for novel_id, tier in NOVELS.items():
        novel = sb.table("novels").select("id,title_vi,title_zh,genres").eq("id", novel_id).single().execute().data or {}
        chapters = (sb.table("chapters")
                    .select("chapter_index,content_zh,content_vi")
                    .eq("novel_id", novel_id).eq("translation_status", "done")
                    .not_.is_("content_zh", "null").not_.is_("content_vi", "null")
                    .order("chapter_index").limit(12).execute().data or [])
        for chapter in chapters:
            zh_lines = [line.strip() for line in chapter["content_zh"].splitlines() if line.strip()]
            vi_lines = [line.strip() for line in chapter["content_vi"].splitlines() if line.strip()]
            if len(zh_lines) != len(vi_lines):
                continue
            for line_index, (zh, vi) in enumerate(zip(zh_lines, vi_lines)):
                tags = categories(zh)
                source_hash = digest(zh)
                if not tags or source_hash in block or not usable(zh, vi):
                    continue
                candidates.append({
                    "status": "needs_user_review",
                    "tier": tier,
                    "category": tags,
                    "novel_id": novel_id,
                    "title_vi": novel.get("title_vi"),
                    "genres": novel.get("genres") or [],
                    "chapter_index": chapter["chapter_index"],
                    "line_index": line_index,
                    "source_hash": source_hash,
                    "context_zh": context(zh_lines, line_index),
                    "context_vi": context(vi_lines, line_index),
                    "zh": zh,
                    "current_vi": vi,
                    "proposed_vi": "",
                    "proposal_state": "needs_human_translation",
                })

    selected, covered, per_novel, per_tier, seen_zh = [], Counter(), Counter(), Counter(), set()
    while candidates and len(selected) < 80:
        candidates.sort(key=lambda row: (
            -sum(10 if covered[tag] == 0 else 2 if covered[tag] < 4 else 0 for tag in row["category"]),
            row["tier"] != "true_online_game" and per_tier["true_online_game"] < 40,
            per_novel[row["novel_id"]] >= 8,
            len(row["zh"]), row["source_hash"],
        ))
        row = candidates.pop(0)
        if (row["zh"] in seen_zh or per_novel[row["novel_id"]] >= 8
                or (row["tier"] == "system_litrpg" and per_tier[row["tier"]] >= 40)):
            continue
        selected.append(row)
        seen_zh.add(row["zh"])
        per_novel[row["novel_id"]] += 1
        per_tier[row["tier"]] += 1
        covered.update(row["category"])

    if len({row["novel_id"] for row in selected}) < 8:
        raise RuntimeError("Chưa đủ 8 truyện khác nhau có cặp căn dòng sạch")
    if per_tier["true_online_game"] < 40:
        raise RuntimeError("Chưa đủ 40 ca võng du thật")
    if any(len({row["novel_id"] for row in selected if row["tier"] == tier}) < 4
           for tier in ("true_online_game", "system_litrpg")):
        raise RuntimeError("Mỗi tier phải có ít nhất 4 truyện")
    if len(selected) < 60:
        raise RuntimeError(f"Chỉ tìm được {len(selected)} ca sạch, chưa đạt tối thiểu 60")
    edits = [row for path in EDIT_PATHS for row in jsonl(path)]
    selected = merge_proposals(selected, edits)
    OUT.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in selected), encoding="utf-8")
    lines = ["# DB game/LitRPG review pack", "", "> Chờ user duyệt; chưa có dòng nào được approved hay đưa vào train.", ""]
    lines += ["| # | Tier | Nhóm | Truyện/chương/dòng | ZH | VI hiện có | Vấn đề | VI đề xuất |", "|---:|---|---|---|---|---|---|---|"]
    for index, row in enumerate(selected, 1):
        compact = lambda value: value.replace("|", "\\|").replace("\n", " ")
        meta = f"{row['novel_id']} / c{row['chapter_index']} / l{row['line_index']}"
        lines.append(f"| {index} | {row['tier']} | {', '.join(row['category'])} | {meta} | {compact(row['zh'])} | {compact(row['current_vi'])} | {compact(row['issue'])} | {compact(row['proposed_vi'])} |")
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("review-pack", len(selected), "novels", len(per_novel), "tiers", dict(per_tier))
    print("coverage", dict(sorted(covered.items())))


def lock_user_approval() -> None:
    rows = jsonl(OUT)
    if len(rows) != 76 or any(
        row.get("status") != "needs_user_review"
        or row.get("proposal_state") != "ready_for_user_review"
        or not row.get("proposed_vi")
        for row in rows
    ):
        raise RuntimeError("Review pack phải đúng 76 đề xuất sẵn sàng trước khi khóa")
    eval_rows = [
        row
        for path in (
            DATASET / "eval_reference_60.jsonl",
            DATASET / "eval_game_english_locked.jsonl",
            EXPERIMENTS / "hachimi_vnext_e_fullchapters.jsonl",
        )
        for row in jsonl(path)
    ]
    eval_hashes = {
        digest(str(row.get("zh") or row.get("source_zh") or ""))
        for row in eval_rows
    }
    eval_groups = {
        (row.get("novel_id"), row.get("chapter_index"))
        for row in eval_rows
        if row.get("novel_id") is not None and row.get("chapter_index") is not None
    }
    approved_rows = [
        row for row in rows
        if row["source_hash"] not in eval_hashes
        and (row["novel_id"], row["chapter_index"]) not in eval_groups
    ]
    blocked_rows = [row for row in rows if row not in approved_rows]
    if len(approved_rows) != 63 or len(blocked_rows) != 13:
        raise RuntimeError(
            f"Phân tách train/eval đã đổi: train={len(approved_rows)}, blocked={len(blocked_rows)}"
        )
    approved = [
        {
            "zh": row["zh"],
            "vi": row["proposed_vi"],
            "status": "approved",
            "source": "user_review_db_game_litrpg",
            "source_hash": row["source_hash"],
            "tier": row["tier"],
            "category": row["category"],
            "novel_id": row["novel_id"],
            "chapter_index": row["chapter_index"],
        }
        for row in approved_rows
    ]
    APPROVED_OUT.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in approved),
        encoding="utf-8",
    )
    EVAL_BLOCKED_OUT.write_text(
        "".join(
            json.dumps(
                {
                    **row,
                    "status": "approved_but_eval_blocked",
                    "block_reason": "same_eval_source_or_chapter",
                },
                ensure_ascii=False,
            )
            + "\n"
            for row in blocked_rows
        ),
        encoding="utf-8",
    )
    print(f"locked train={len(approved)} eval_blocked={len(blocked_rows)}")


def self_check() -> None:
    assert categories("属性面板显示HP") == ["bang_thuoc_tinh_ui", "english_id"]
    assert usable("角色击杀怪物后获得大量经验值", "Nhân vật nhận được rất nhiều điểm kinh nghiệm sau khi hạ quái.")
    assert not usable("作者求收藏", "Tác giả xin theo dõi.")
    assert not usable("请领取装备……’", "Hãy nhận trang bị.")
    assert context(["a", "b", "c"], 1) == "a\nb\nc"
    merged = merge_proposals(
        [{"source_hash": "a", "proposed_vi": "", "proposal_state": "needs_human_translation"}],
        [{"source_hash": "a", "proposed_vi": "B", "issue": "C"}],
    )
    assert merged[0]["proposed_vi"] == "B" and merged[0]["proposal_state"] == "ready_for_user_review"
    print("prepare_db_game_review_pack OK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--lock-user-approval", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
    elif args.lock_user_approval:
        lock_user_approval()
    else:
        main()
