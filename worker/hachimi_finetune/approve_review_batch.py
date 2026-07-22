"""Append a user-approved Markdown review batch to approved_gold.jsonl."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


def _sections(text: str) -> list[str]:
    return re.split(r"(?m)^## \d+\. [^\n]+\n", text)[1:]


def _row(section: str) -> dict[str, str]:
    zh = re.search(r"\*\*ZH:\*\*\s*(.+)", section)
    # Hỗ trợ lấy toàn bộ đoạn Đề xuất (kể cả multi-line xuống dòng) cho đến hết mục
    vi = re.search(r"(?s)\*\*Đề xuất:\*\*[ \t]*(.*?)(?=\n##|\Z)", section)
    if vi is None:
        vi = re.search(r'Bản dịch chuẩn.*?:\*\*\s*"([^"]+)"', section)
    if not zh or not vi:
        raise ValueError("Thiếu ZH hoặc bản dịch đã duyệt trong một mục")
    return {"zh": zh.group(1).strip(), "vi": vi.group(1).strip()}



def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("batch", type=Path)
    parser.add_argument("--gold", type=Path, default=Path(__file__).with_name("approved_gold.jsonl"))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--skip-existing", action="store_true")
    parser.add_argument("--replace-existing", action="store_true")
    args = parser.parse_args()
    if args.batch.suffix == ".jsonl":
        rows = [
            {"zh": item["zh"], "vi": item.get("vi") or item["proposed_vi"]}
            for item in (json.loads(line) for line in args.batch.read_text(encoding="utf-8").splitlines())
            if item.get("status") == "approved" or item.get("status") == "needs_user_approval"
        ]
    else:
        rows = []
        for index, section in enumerate(_sections(args.batch.read_text(encoding="utf-8")), start=1):
            try:
                rows.append(_row(section))
            except ValueError as exc:
                raise ValueError(f"Mục {index}: {exc}") from exc
    if args.check:
        print(f"valid={len(rows)}")
        return
    old = [json.loads(line) for line in args.gold.read_text(encoding="utf-8").splitlines() if line.strip()]
    known = {row["zh"] for row in old}
    if args.replace_existing:
        incoming = {row["zh"]: row["vi"] for row in rows}
        replaced = 0
        for row in old:
            if row["zh"] in incoming:
                row["vi"] = incoming.pop(row["zh"])
                replaced += 1
        additions = [
            {"id": f"review-{hashlib.sha256(row['zh'].encode()).hexdigest()[:12]}", "domain": "review", **row, "status": "approved"}
            for row in rows if row["zh"] in incoming
        ]
        args.gold.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in old + additions), encoding="utf-8")
        print(f"replaced={replaced} approved={len(additions)} total={len(old) + len(additions)}")
        return
    duplicates = [row for row in rows if row["zh"] in known]
    additions = [
        {"id": f"review-{hashlib.sha256(row['zh'].encode()).hexdigest()[:12]}", "domain": "review", **row, "status": "approved"}
        for row in rows if row["zh"] not in known
    ]
    if duplicates and not args.skip_existing:
        raise SystemExit("Batch có câu đã tồn tại trong approved_gold; không tự ghi trùng")
    with args.gold.open("a", encoding="utf-8", newline="\n") as file:
        for row in additions:
            file.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"approved={len(additions)} duplicate={len(duplicates)} total={len(old) + len(additions)}")


if __name__ == "__main__":
    main()
