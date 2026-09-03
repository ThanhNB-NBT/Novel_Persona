"""Cổng chất lượng dùng chung cho MỌI nguồn data zh→vi, gác theo LÔ chứ không theo câu.

Vì sao có file này: dự án vốn phân loại nguồn bằng "người dịch hay máy dịch", đo bằng mật độ
hư từ (`eval/scan_epub_corpus.py`). Đo lại 01/09 trên các bộ **đã biết chắc nguồn gốc** thì
thước đó **ngược dấu** — bản Gemini (máy) ăn điểm CAO HƠN kaihe (người), vì nó đo "văn có tự
nhiên như tiếng Việt không", đúng thứ LLM tối ưu. Xem `docs/ban-giao-2026-09-01-prose.md`.

Ba thước CẤU TRÚC dưới đây xếp hạng nhất quán và đo đúng thứ cần đo — **mức bám sát chữ Hán**:

| bộ (01/09) | convert/1k | POSS/10k | phiên âm % | hư từ/1k |
|---|---|---|---|---|
| epub trung vị — convert | 4,25 | 0,7 | 47,5 | 7,3 |
| epub ≥14 — "dịch tay" | 2,79 | 0,5 | 43,2 | 15,2 |
| kaihe — NGƯỜI | 1,86 | 0,5 | 38,5 | 14,4 |
| Gemini prose — MÁY | 1,11 | 0,1 | 29,2 | 16,1 |
| Gemini teacher — MÁY | 1,06 | 0,1 | 30,9 | 18,1 |

⇒ Trục thật không phải người/máy mà là **literal ↔ tự do**. Nên cổng gác HAI ĐẦU:

- **Quá bám chữ** (`convert_per_1k` cao / `translit_pct` cao) = convert, train vào là dạy hỏng.
- **Quá thoát** (`translit_pct` thấp) = dịch nghĩa cả những cụm lẽ ra giữ Hán-Việt, làm trôi
  register tiên hiệp mà dự án đã chốt (`[[translation-tuning]]`). Chỉ CẢNH BÁO chứ không loại
  — data Gemini vẫn dùng được ở liều thấp, miễn đừng để nó lấn phần người.

⚠ Gác theo LÔ, không theo câu: cả ba đều là mật độ, một câu 20 từ thì `convert_per_1k` chỉ ra
0 hoặc 50 — vô nghĩa. Dùng cho cả shard hoặc cả truyện.

    from quality_gate import audit, verdict
    m = audit(pairs)              # pairs = [(zh, vi), ...]
    print(m, verdict(m))
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))   # worker/ để import novelworker

# Ba biểu thức lấy nguyên từ `eval/scan_epub_corpus.py` — CỐ Ý dùng chung, đừng chép lại:
# sửa một đầu mà quên đầu kia là hai thước cùng tên cho hai kết quả.
CONVERT = re.compile(
    r"\b(một cái|không khỏi|căn bản là|rốt cuộc là|trên thực tế|tổng cảm thấy|"
    r"đối với .{1,25} tới nói|thế nhưng là|chính mình|nói giỡn|có thể nói là)\b", re.I)
POSS = re.compile(r"\b(ta|ngươi|hắn|nàng|mình|bọn hắn|các ngươi)\s+"
                  r"(chân thân|tâm cảnh|bộ dáng|thân thể|trong lòng|trên người|khuôn mặt|"
                  r"ánh mắt|thanh âm|thần sắc|lời nói|đôi mắt)\b", re.I)
_WORD = re.compile(r"[a-zà-ỹđ]+", re.IGNORECASE)

# Ngưỡng đặt giữa "convert đã gọt" (2,79 · 43,2) và "người" (1,86 · 38,5) — hai nhóm gần nhau
# nhất trong bảng, nên đây là chỗ khó nhất và cũng là chỗ đáng đặt vạch.
MAX_CONVERT_PER_1K = 2.4
MAX_TRANSLIT_PCT = 41.0
MIN_TRANSLIT_PCT = 27.0    # dưới mức này là thoát ly Hán-Việt hơn cả Gemini (29,2) ⇒ cảnh báo
MIN_WORDS = 20_000         # dưới ngưỡng này mật độ chưa ổn định, đừng phán


def audit(pairs, sample: int | None = 40_000) -> dict:
    """[(zh, vi)] → {convert_per_1k, poss_per_10k, translit_pct, words, pairs}.

    `translit_pct` = % âm tiết trong bản dịch trùng phiên âm Hán-Việt của chính câu nguồn.
    Bỏ qua cặp không có `zh` khi tính riêng chỉ số đó (vẫn tính hai chỉ số kia).
    """
    from novelworker.translator import hanviet

    table = hanviet._load()
    words = convert = poss = 0
    hit = total = 0
    seen = 0
    for zh, vi in pairs:
        if sample and seen >= sample:
            break
        seen += 1
        vi = vi or ""
        if not vi:
            continue
        words += max(1, len(vi.split()))
        convert += len(CONVERT.findall(vi))
        poss += len(POSS.findall(vi))
        if zh:
            readings: set[str] = set()
            for ch in zh:
                for r in table.get(ch) or ():
                    readings.add(r.lower())
            tokens = [t.lower() for t in _WORD.findall(vi)]
            total += len(tokens)
            hit += sum(1 for t in tokens if t in readings)
    return {
        "pairs": seen,
        "words": words,
        "convert_per_1k": round(convert / max(1, words) * 1000, 2),
        "poss_per_10k": round(poss / max(1, words) * 10000, 1),
        "translit_pct": round(hit / total * 100, 1) if total else None,
    }


def verdict(metrics: dict, min_translit: float = MIN_TRANSLIT_PCT) -> tuple[str, list[str]]:
    """(`ok` | `warn` | `reject`, lý do) — xem ngưỡng và bảng hiệu chuẩn ở đầu file.

    ⚠ `min_translit` hiệu chuẩn theo VĂN XUÔI. Thơ nằm dưới sàn đó một cách CHÍNH ĐÁNG:
    `poem_corpus` ra 19,8% và đó đúng là thứ muốn có — cả mục đích của bộ thơ mới là hạ phiên
    âm thô (bộ gemma cũ 32,4% chính là data đang dạy model dịch thô). Chấm thơ thì hạ sàn
    xuống ~15, đừng để cổng "sửa" ngược lại việc vừa làm.
    """
    reasons: list[str] = []
    if metrics["words"] < MIN_WORDS:
        return "warn", [f"mới {metrics['words']:,} từ (<{MIN_WORDS:,}), mật độ chưa ổn định"]

    tl = metrics.get("translit_pct")
    if metrics["convert_per_1k"] >= MAX_CONVERT_PER_1K:
        reasons.append(f"cụm convert {metrics['convert_per_1k']}/1k ≥ {MAX_CONVERT_PER_1K}")
    if tl is not None and tl >= MAX_TRANSLIT_PCT:
        reasons.append(f"phiên âm thô {tl}% ≥ {MAX_TRANSLIT_PCT}%")
    if reasons:
        return "reject", reasons

    if tl is not None and tl < min_translit:
        return "warn", [f"phiên âm thô {tl}% < {min_translit}% — thoát ly Hán-Việt, "
                        f"để liều thấp kẻo trôi register"]
    return "ok", []


def _self_check() -> None:
    """Đối chứng bằng chính bảng hiệu chuẩn: thứ tự phải giữ, và cổng phải phán đúng."""
    convert = [("他不禁一笑", "hắn không khỏi một cái mỉm cười, chính mình trên thực tế "
                             "rốt cuộc là ngươi thân thể")] * 1500
    nguoi = [("他不禁一笑", "Hắn bật cười, trong lòng thầm nghĩ rằng chuyện này "
                          "quả thực là do mình gây ra")] * 1500
    m_c, m_n = audit(convert), audit(nguoi)
    assert m_c["convert_per_1k"] > m_n["convert_per_1k"], (m_c, m_n)
    assert m_c["poss_per_10k"] > m_n["poss_per_10k"], (m_c, m_n)
    assert verdict(m_c)[0] == "reject", verdict(m_c)
    # Đối chứng ÂM: lô quá nhỏ thì không được phán bừa
    assert verdict(audit(convert[:2]))[0] == "warn", "lô nhỏ mà vẫn dám kết luận"
    print("self-check OK:", m_c, verdict(m_c)[0], "|", m_n, verdict(m_n)[0])


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        _self_check()
    else:
        import argparse
        import json

        ap = argparse.ArgumentParser(description="Chấm chất lượng một shard jsonl zh/vi")
        ap.add_argument("path", type=Path)
        ap.add_argument("--zh", default="zh")
        ap.add_argument("--vi", default="vi")
        ap.add_argument("--sample", type=int, default=40_000)
        a = ap.parse_args()
        rows = []
        for line in a.path.open(encoding="utf-8"):
            if line.strip():
                o = json.loads(line)
                rows.append((o.get(a.zh, ""), o.get(a.vi, "")))
            if len(rows) >= a.sample:
                break
        m = audit(rows, sample=a.sample)
        state, why = verdict(m)
        print(json.dumps({**m, "verdict": state, "reasons": why}, ensure_ascii=False, indent=2))
