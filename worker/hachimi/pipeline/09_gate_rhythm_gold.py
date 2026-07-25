"""Cổng nghiệm thu gold NHỊP CÂU do thầy viết lại.

Đọc `dataset/rhythm_labeled.jsonl` (thầy điền trường `vi`) → `dataset/train_rhythm_approved.jsonl`
đúng định dạng `--clean-gold` của kaggle_train.

Cổng khác các vòng trước ở điều kiện CUỐI: bản dịch phải THỰC SỰ tách chuỗi phẩy thành
nhiều câu tiếng Việt (`câu VI / dấu 。 ZH ≥ 1,4`). Không có cổng đó thì thầy trả về đúng
kiểu 1:1 mà replay đang dạy và cả vòng train thành vô nghĩa.
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

from kaggle_train import _MODERN, _MOJIBAKE, _quotes_balanced


DATA = Path(__file__).resolve().parents[1] / "data"
LABELED = DATA / "source" / "rhythm_labeled_all.jsonl"
OUT = DATA / "gold" / "rhythm_labeled_all_approved.jsonl"
REJECTS = DATA / "source" / "rhythm_labeled_all_rejects.jsonl"
HAN = re.compile(r"[一-鿿]")
MIN_SENTENCE_RATIO = 1.4
# Hai ngưỡng dưới đây hiệu chỉnh từ chính 60 tham chiếu user chấm là đọc ổn:
# ratio p95 = 5,0 (median 1,69); độ dài câu trung bình p05 = 51 ký tự (median 84).
MAX_SENTENCE_RATIO = 5.0
MIN_SENTENCE_CHARS = 50
SPACE_BEFORE_PUNCT = re.compile(r"\s[.,;:!?]")
# Thầy từng thay mù "cậu"→"ngươi" để né cổng xưng hô, đẻ ra "một ngươi bé".
BLIND_PRONOUN = re.compile(r"(?i)\b(?:một|hai|ba|bốn|con|chú|cô)\s+(?:ta|ngươi|hắn|nàng)\b")
DOUBLE_PUNCT = re.compile(r"(?:\.\.(?!\.)|[?!,;:]\s*\.)")
DOUBLE_SPACE = re.compile(r"\S {2,}\S")  # chỗ chữ bị cắt/di dời để lại khoảng trắng đôi
LOWER_SENTENCE_START = re.compile(r"^[\W\d]*[a-zàáâãèéêìíòóôõùúăđĩũơưăạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ]")


def sentences(vi: str) -> int:
    return len([part for part in re.split(r"(?<=[.!?…])\s+", vi) if part.strip()])


def sentence_ratio(zh: str, vi: str) -> float:
    return sentences(vi) / (zh.count("。") + zh.count("！") + zh.count("？") or 1)


def reject_reason(row: dict, seen: set[str]) -> str | None:
    zh, vi = row.get("zh", ""), (row.get("vi") or "").strip()
    if not zh or not vi:
        return "thiếu zh hoặc vi"
    if zh in seen:
        return "trùng nguồn Trung"
    if HAN.search(vi):
        return "còn chữ Hán"
    if _MOJIBAKE.search(vi):
        return "mojibake"
    if not _quotes_balanced(vi):
        return "quote lệch"
    if _MODERN.search(vi):
        return "đại từ hiện đại"
    # Danh xưng thân tộc hiện đại: cổng đại từ không bắt được (user bắt ở chương thật).
    for zh_kin, modern_vi in (("哥哥", "anh trai"), ("姐姐", "chị gái"), ("妹妹", "em gái"),
                              ("弟弟", "em trai"), ("小孙", "Tiểu Tôn")):
        if zh_kin in zh and modern_vi.lower() in vi.lower():
            return f"danh xưng hiện đại ({zh_kin} → {modern_vi})"
    if any(mark in zh for mark in "“「『") and not any(mark in vi for mark in "“\"「『"):
        return "mất dấu thoại"
    if re.findall(r"\d+", zh) != re.findall(r"\d+", vi):
        return "số không khớp"
    if not 1.5 <= len(vi) / len(zh) <= 4.5:
        return "tỷ lệ dài bất thường"
    if vi == (row.get("vi_model") or "").strip():
        return "không sửa gì so với bản model"
    # "đè trên người mình" -> "đè trên người ta": né cổng "mình" nhưng đổi hẳn nghĩa.
    if "người mình" in (row.get("vi_model") or "") and "người ta" in vi:
        return "đổi phản thân 'người mình' thành 'người ta'"
    if SPACE_BEFORE_PUNCT.search(vi):
        return "space trước dấu câu (dấu hiệu thay máy móc)"
    if BLIND_PRONOUN.search(vi):
        return "thay mù đại từ (một ngươi bé)"
    if DOUBLE_PUNCT.search(vi):
        return "dấu câu nhân đôi (dấu hiệu thay máy móc)"
    if DOUBLE_SPACE.search(vi):
        return "khoảng trắng đôi (chữ bị cắt mất)"
    parts = [part for part in re.split(r"(?<=[.!?…])\s+", vi) if part.strip()]
    if any(LOWER_SENTENCE_START.match(part) for part in parts):
        return "câu mới không viết hoa (dấu hiệu thay phẩy bằng chấm)"
    ratio = sentence_ratio(zh, vi)
    if ratio < MIN_SENTENCE_RATIO:
        return "chưa tách chuỗi phẩy thành câu"
    if ratio > MAX_SENTENCE_RATIO or sum(len(part) for part in parts) / len(parts) < MIN_SENTENCE_CHARS:
        return "băm câu quá vụn"
    return None


def main(labeled: Path = LABELED) -> None:
    rows = [json.loads(line) for line in labeled.read_text(encoding="utf-8").splitlines() if line.strip()]
    # Soi shard riêng thì ghi kết quả cạnh shard đó, tránh nhiều phiên chạy song song đè nhau.
    out = OUT if labeled == LABELED else labeled.with_name(labeled.stem + "_approved.jsonl")
    rejects_path = REJECTS if labeled == LABELED else labeled.with_name(labeled.stem + "_rejects.jsonl")
    seen: set[str] = set()
    approved, rejects = [], []
    reasons: Counter[str] = Counter()
    for row in rows:
        reason = reject_reason(row, seen)
        if reason:
            reasons[reason] += 1
            rejects.append({**row, "reject_reason": reason})
            continue
        seen.add(row["zh"])
        approved.append({
            "zh": row["zh"], "vi": row["vi"].strip(), "status": "approved",
            "domain": "rhythm_gold", "novel_id": row.get("novel_id"),
            "chapter_index": row.get("chapter_index"),
        })
    out.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in approved), encoding="utf-8")
    rejects_path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rejects), encoding="utf-8")
    ratio = sum(sentence_ratio(row["zh"], row["vi"]) for row in approved) / max(1, len(approved))
    print(f"Đạt {len(approved)}/{len(rows)} — câu VI / dấu 。 ZH trung bình {ratio:.2f} (tham chiếu 2,06)")
    for reason, count in reasons.most_common():
        print(f"  loại {count:5d}: {reason}")
    print(f"→ {out}\n→ {rejects_path}")


def self_check() -> None:
    good = {
        "zh": "他握紧长枪，转身离去，风吹过山谷，落叶纷飞，天色渐晚。",
        "vi": "Hắn nắm chặt cây trường thương trong tay, ánh mắt lạnh lẽo. Rồi xoay người rời đi, gió thổi qua sơn cốc hoang vu.",
        "vi_model": "x",
    }
    assert reject_reason(good, set()) is None
    assert reject_reason({**good, "vi": good["vi"].replace(". Rồi", ", rồi")}, set()) == "chưa tách chuỗi phẩy thành câu"
    assert reject_reason({**good, "vi": good["vi"].replace("Hắn", "Tôi")}, set()) == "đại từ hiện đại"
    assert reject_reason(good, {good["zh"]}) == "trùng nguồn Trung"
    # Thầy từng gian lận: thay ", " bằng " . " để qua cổng đếm câu.
    assert reject_reason({**good, "vi": good["vi"].replace(", ánh", " .  ánh")}, set()) \
        == "space trước dấu câu (dấu hiệu thay máy móc)"
    assert reject_reason({**good, "vi": good["vi"].replace(", ánh", ". ánh")}, set()) \
        == "câu mới không viết hoa (dấu hiệu thay phẩy bằng chấm)"
    assert reject_reason({**good, "vi": "Hắn nắm thương. Xoay người. Rời đi. Gió thổi. Qua sơn cốc. Lạnh lẽo."}, set()) == "băm câu quá vụn"
    kin = {"zh": "他的哥哥走过来，姐姐也跟着，两人都不说话，只是静静看着他。",
           "vi": "Ca ca của hắn bước tới, tỷ tỷ cũng lặng lẽ đi theo phía sau. "
                 "Hai người đều không nói lời nào, chỉ đứng đó yên lặng nhìn hắn.",
           "vi_model": "x"}
    assert reject_reason(kin, set()) is None
    assert reject_reason({**kin, "vi": kin["vi"].replace("Ca ca", "Anh trai")}, set()) \
        == "danh xưng hiện đại (哥哥 → anh trai)"
    print("09_gate_rhythm_gold OK")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        self_check()
    else:
        # Cho phép soi riêng một shard: python 09_gate_rhythm_gold.py dataset/rhythm_labeled_101_200.jsonl
        main(Path(sys.argv[1]) if len(sys.argv) > 1 else LABELED)
