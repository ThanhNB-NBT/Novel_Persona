"""Create readable, genre-balanced review queues from the clean source pool."""

from __future__ import annotations

import json
import re
import argparse
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).parent
POOL = ROOT / "source_pool.jsonl"
APPROVED = ROOT / "approved_gold.jsonl"
OUT = ROOT / "review_queue"
QUOTAS = {
    "benchmark": 5,
    "xianxia": 9,
    "game": 9,
    "survival": 7,
    "sports_esports": 5,
    "fandom": 5,
    "fantasy_scifi": 5,
    "modern_other": 5,
}


def source_key(text: str) -> str:
    return re.sub(r"[\s\"“”‘’'，。！？、：；,.!?…]", "", text)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--start-version", type=int, default=5)
    parser.add_argument("--batches", type=int, default=8)
    parser.add_argument("--offset", type=int, default=0,
                        help="số nhóm đã bỏ qua sau khi lọc nguồn đã duyệt")
    args = parser.parse_args()
    approved = {
        source_key(json.loads(line)["zh"])
        for line in APPROVED.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    for review in OUT.glob("v*.md"):
        approved.update(source_key(match) for match in re.findall(
            r"(?m)^\*\*ZH:\*\*\s*(.+)$", review.read_text(encoding="utf-8")
        ))
    rows = []
    seen = set(approved)
    for row in (json.loads(line) for line in POOL.read_text(encoding="utf-8").splitlines()):
        key = source_key(row["zh"])
        if key in seen:
            continue
        seen.add(key)
        rows.append(row)
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        groups[row["domain"]].append(row)
    OUT.mkdir(exist_ok=True)
    for batch in range(args.batches):
        selected: list[dict] = []
        for domain, count in QUOTAS.items():
            start = (args.offset + batch) * count
            selected.extend(groups[domain][start:start + count])
        lines = [f"# Gold review V{args.start_version + batch} ({len(selected)} câu)", ""]
        for index, row in enumerate(selected, start=1):
            lines.extend([
                f"## {index}. {row['domain']}",
                "", f"**ZH:** {row['zh'].replace(chr(10), ' ').strip()}", "", "**Đề xuất:**", "",
            ])
        (OUT / f"v{args.start_version + batch}.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote={args.batches} batches rows_per_batch={sum(QUOTAS.values())}")


if __name__ == "__main__":
    main()
