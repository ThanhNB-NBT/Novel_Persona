"""Loại khỏi replay teacher những dòng DẠY SAI NHỊP CÂU.

Thêm gold nhịp câu chỉ là một nửa việc: 9.677/10.000 dòng replay đang dạy dịch 1:1 theo
dấu câu tiếng Trung. Dòng nguy hiểm nhất là dòng nguồn có chuỗi phẩy dài mà đích vẫn gói
thành một câu — đó chính xác là hành vi cần bỏ. Bỏ tín hiệu xấu rẻ hơn nhiều so với đắp
thêm hàng nghìn gold để đè lên nó.

Dòng nguồn ngắn, không có chuỗi phẩy thì giữ nguyên: chúng vô hại và vẫn chống quên.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from importlib import import_module

gate = import_module("09_gate_rhythm_gold")


REPLAY = Path(__file__).resolve().parents[1] / "data" / "replay"
SOURCE = REPLAY / "general_candidate.jsonl"
OUT = REPLAY / "general_candidate_rhythm_screened.jsonl"
MIN_CHAIN_COMMAS = 3


def teaches_bad_rhythm(zh: str, vi: str) -> bool:
    return zh.count("，") + zh.count("、") >= MIN_CHAIN_COMMAS and gate.sentence_ratio(zh, vi) < gate.MIN_SENTENCE_RATIO


def main() -> None:
    rows = [json.loads(line) for line in SOURCE.read_text(encoding="utf-8").splitlines() if line.strip()]
    kept = [row for row in rows if not teaches_bad_rhythm(row["zh"], row["vi"])]
    OUT.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in kept), encoding="utf-8")
    dropped = len(rows) - len(kept)
    ratio = sum(gate.sentence_ratio(row["zh"], row["vi"]) for row in kept) / len(kept)
    print(f"Giữ {len(kept)}/{len(rows)} (bỏ {dropped} dòng gương 1:1 trên câu chuỗi phẩy)")
    print(f"Nhịp trung bình của replay sau sàng: {ratio:.2f} (trước: "
          f"{sum(gate.sentence_ratio(r['zh'], r['vi']) for r in rows) / len(rows):.2f})")
    print(f"→ {OUT}")


def self_check() -> None:
    assert teaches_bad_rhythm("甲，乙，丙，丁。", "Một câu dài duy nhất không ngắt.")
    assert not teaches_bad_rhythm("甲，乙，丙，丁。", "Câu một ở đây. Câu hai ở đây.")
    assert not teaches_bad_rhythm("甲乙丙。", "Một câu ngắn.")  # không có chuỗi phẩy
    print("10_screen_replay_rhythm OK")


if __name__ == "__main__":
    self_check() if "--self-check" in sys.argv else main()
