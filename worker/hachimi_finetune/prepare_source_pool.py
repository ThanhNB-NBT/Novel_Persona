"""Build a deduplicated Chinese-only pool for new gold translations.

No Vietnamese labels from dataset_game are read or copied.
"""

from __future__ import annotations

import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path

from text_clean import clean_source as clean


ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).with_name("source_pool.jsonl")


def rank(text: str) -> bytes:
    return hashlib.sha256(("hachimi-cophong-v1\0" + text).encode("utf-8")).digest()


def benchmark_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for folder in (ROOT / "worker" / "benchmark_out" / "hachimimt-60-zh-vi", ROOT / "worker" / "eval_out_v2"):
        if not folder.is_dir():
            continue
        for path in sorted(folder.glob("*.txt")):
            text = path.read_text(encoding="utf-8")
            for source in re.findall(r"^ZH:\s*(.+)$", text, re.M):
                source = clean(source)
                if 20 <= len(source) <= 500:
                    rows.append({"domain": "benchmark", "source_file": str(path.relative_to(ROOT)), "zh": source})
    return rows


def domain_for_title(title: str) -> str:
    if any(word in title for word in ("NBA", "足球", "篮球", "CSGO", "LOL", "联盟", "职业赛场")):
        return "sports_esports"
    if any(word in title for word in ("求生", "末世", "末日", "荒岛", "公路", "废土")):
        return "survival"
    if any(word in title for word in ("原神", "崩坏", "奥特曼", "宝可梦", "蜡笔小新", "小马宝莉", "网王", "明日方舟")):
        return "fandom"
    if any(word in title for word in ("网游", "游戏", "副本", "玩家", "领主")):
        return "game"
    if any(word in title for word in ("修仙", "仙", "剑", "宗", "帝", "道", "古代", "清穿", "寒门")):
        return "xianxia"
    if any(word in title for word in ("星际", "魔法", "无限", "异世", "魔", "神", "诡异")):
        return "fantasy_scifi"
    return "modern_other"


def restored_rows() -> list[dict[str, str]]:
    path = ROOT / "dataset_game" / "raw_zh.jsonl"
    rows: list[dict[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        title = str(row.get("title") or "")
        for source in row.get("zh_lines") or []:
            source = clean(str(source))
            if 20 <= len(source) <= 500:
                rows.append({
                    "domain": domain_for_title(title),
                    "source_file": "dataset_game/raw_zh.jsonl",
                    "book_id": str(row.get("book_id") or ""),
                    "title_zh": title,
                    "zh": source,
                })
    return rows


def select(rows: list[dict[str, str]], limit: int) -> list[dict[str, str]]:
    dedup: dict[str, dict[str, str]] = {}
    for row in rows:
        dedup.setdefault(row["zh"], row)
    return sorted(dedup.values(), key=lambda row: rank(row["zh"]))[:limit]


def main() -> None:
    restored = defaultdict(list)
    for row in restored_rows():
        restored[row["domain"]].append(row)
    quotas = {
        "xianxia": 800,
        "game": 800,
        "survival": 700,
        "sports_esports": 500,
        "fandom": 500,
        "fantasy_scifi": 500,
        "modern_other": 500,
    }
    groups = {"benchmark": select(benchmark_rows(), 500)}
    groups.update({name: select(restored[name], limit) for name, limit in quotas.items()})
    rows = [row for group in groups.values() for row in group]
    rows.sort(key=lambda row: (row["domain"], rank(row["zh"])))
    OUT.write_text("\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n", encoding="utf-8")
    print(" ".join(f"{name}={len(group)}" for name, group in groups.items()))
    print(f"wrote={len(rows)} {OUT}")


if __name__ == "__main__":
    main()
