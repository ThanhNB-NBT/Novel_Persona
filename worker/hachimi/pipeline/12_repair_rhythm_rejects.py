"""Sửa MÁY MÓC các dòng bị cổng loại vì lỗi định dạng, không gọi model nào.

31% sản phẩm của thầy bị loại, mà phần lớn là artifact khi nó chèn dấu chấm: `..`,
`?.`, space trước dấu câu, khoảng trắng đôi, câu mới không viết hoa. Những thứ đó sửa
bằng quy tắc là đủ — chỉ lỗi NỘI DUNG (chưa tách nhịp, băm vụn, rớt số, thay mù đại từ)
mới phải trả lại cho thầy.

Dòng sửa xong vẫn phải đi qua đúng cổng cũ; cái nào còn trượt thì để nguyên trong file
rejects cho vòng thầy sửa.
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from importlib import import_module
from pathlib import Path


gate = import_module("09_gate_rhythm_gold")

DATA = Path(__file__).resolve().parents[1] / "data"
REJECTS = DATA / "source" / "rhythm_labeled_all_rejects.jsonl"
LABELED = DATA / "source" / "rhythm_labeled_all.jsonl"
STILL_BROKEN = DATA / "source" / "rhythm_rejects_for_teacher.jsonl"
SENTENCE_END = re.compile(r"([.!?…])\s+([a-zàáâãèéêìíòóôõùúăđĩũơư])")


def repair(vi: str) -> str:
    vi = re.sub(r"\s+([,.;:!?])", r"\1", vi)          # space trước dấu câu
    vi = re.sub(r"(?<!\.)\.{2}(?!\.)", ".", vi)        # ".." nhưng giữ "..."
    vi = re.sub(r"([?!,;:])\s*\.", r"\1", vi)          # "?.", ",."
    vi = re.sub(r"([!?])\1+", r"\1", vi)               # "!!", "??" do chèn thừa (giữ "...")
    vi = re.sub(r" {2,}", " ", vi)                     # khoảng trắng đôi
    # Câu mới phải viết hoa (thầy thay phẩy bằng chấm nhưng quên hoa).
    while True:
        fixed = SENTENCE_END.sub(lambda m: f"{m.group(1)} {m.group(2).upper()}", vi)
        if fixed == vi:
            break
        vi = fixed
    return vi.strip()


def main() -> None:
    rejects = [json.loads(line) for line in REJECTS.read_text(encoding="utf-8").splitlines() if line.strip()]
    labeled = [json.loads(line) for line in LABELED.read_text(encoding="utf-8").splitlines() if line.strip()]
    by_zh = {row["zh"]: row for row in labeled}
    seen = {row["zh"] for row in labeled if gate.reject_reason(row, set()) is None}

    healed, still = [], []
    before, after = Counter(), Counter()
    for row in rejects:
        before[row.get("reject_reason", "?")] += 1
        candidate = {**row, "vi": repair(row.get("vi") or "")}
        candidate.pop("reject_reason", None)
        reason = gate.reject_reason(candidate, seen)
        if reason is None:
            healed.append(candidate)
            seen.add(candidate["zh"])
        else:
            after[reason] += 1
            still.append({**candidate, "reject_reason": reason})

    for row in healed:
        by_zh[row["zh"]] = row
    LABELED.write_text(
        "".join(json.dumps(by_zh[row["zh"]], ensure_ascii=False) + "\n" for row in labeled),
        encoding="utf-8",
    )
    STILL_BROKEN.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in still), encoding="utf-8",
    )
    print(f"Cứu được {len(healed)}/{len(rejects)} dòng bằng quy tắc; còn {len(still)} dòng cần thầy sửa.")
    print("Lý do còn lại:")
    for reason, count in after.most_common():
        print(f"  {count:5d}  {reason}  (trước: {before.get(reason, 0)})")
    print(f"→ {LABELED}\n→ {STILL_BROKEN}")


def self_check() -> None:
    assert repair("Hắn đi .  nhà tan") == "Hắn đi. Nhà tan"
    assert repair("Hắn đi.. nhà tan") == "Hắn đi. Nhà tan"
    assert repair("Hắn đi?. nhà tan") == "Hắn đi? Nhà tan"
    assert repair("Hắn nói...  rồi đi") == "Hắn nói... Rồi đi"
    assert repair("Hắn  đi chơi") == "Hắn đi chơi"
    print("12_repair_rhythm_rejects OK")


if __name__ == "__main__":
    self_check() if "--self-check" in sys.argv else main()
