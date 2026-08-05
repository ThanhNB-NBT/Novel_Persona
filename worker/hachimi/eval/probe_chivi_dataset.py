"""Probe: dataset song ngữ chi-vi có đáng làm "mỏ neo người dịch" cho vòng train sau không?

Bối cảnh (memory hachimi-game-finetune): data train Hachimi hiện TOÀN máy-sinh → đúng kịch
bản model collapse, thiếu mỏ neo người dịch. chi-vi có >20GB cặp zh-vi NGƯỜI dịch (gated).
Nhưng gu user CẤM giọng "anh/em/cậu/tôi" sến trong lời kể cổ trang — nên phải ĐO trước khi
tin, không trộn mù (bài học: "kaihe là mỏ neo nhưng phải lọc anh/em, không dùng một mình").

Đây là PROBE, KHÔNG train, KHÔNG trộn corpus. Chỉ streaming N mẫu, đo tỉ lệ đại từ hiện đại
lọt vào bản Việt + in mẫu ngẫu nhiên để đọc tay. Kết quả là input cho PLAN_CHAT_LUONG_2026-08,
để user quyết — KHÔNG tự mở lại vòng data đã đóng.

Chạy:  HF_TOKEN=... python -m hachimi.eval.probe_chivi_dataset [n_mau]
Cần: pip install datasets ; và đã `huggingface-cli login` / accept điều kiện dataset gated.
"""
from __future__ import annotations

import os
import random
import re
import sys

DATASET = "chi-vi/hirashiba-mt-zh2vi"  # đổi sang -b-filtered để lấy bản đã lọc
# Đại từ/xưng hô "sến" so với gu cổ trang (lời kể nên hắn/nàng, thoại ta-ngươi):
_MODERN = re.compile(r"(?i)(?<!\w)(?:tôi|anh ta|cô ta|cô ấy|cậu|em ấy|anh ấy)(?!\w)")


def _pick_cols(features) -> tuple[str, str]:
    """Đoán cột zh và vi từ tên feature (README dataset để trống nên phải tự dò)."""
    names = list(features)
    zh = next((c for c in names if any(k in c.lower() for k in ("zh", "cn", "src", "chinese"))), names[0])
    vi = next((c for c in names if any(k in c.lower() for k in ("vi", "tgt", "viet"))), names[-1])
    return zh, vi


def main() -> None:
    if not os.environ.get("HF_TOKEN"):
        sys.exit("Cần HF_TOKEN (dataset gated). export HF_TOKEN=... rồi chạy lại.")
    try:
        from datasets import load_dataset
    except ImportError:
        sys.exit("Thiếu deps: pip install datasets")

    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    ds = load_dataset(DATASET, split="train", streaming=True, token=os.environ["HF_TOKEN"])
    zh_col, vi_col = _pick_cols(ds.features)
    print(f"{DATASET}: cột nguồn='{zh_col}', đích='{vi_col}' · lấy {n} mẫu\n")

    modern_hits = modern_lines = 0
    samples: list[tuple[str, str]] = []
    for i, row in enumerate(ds):
        if i >= n:
            break
        vi = str(row[vi_col])
        hits = _MODERN.findall(vi)
        modern_hits += len(hits)
        modern_lines += bool(hits)
        if len(samples) < 12 and random.random() < 0.05:
            samples.append((str(row[zh_col]), vi))

    print(f"Dòng có đại từ 'sến' (tôi/anh ta/cậu…): {modern_lines}/{n} "
          f"({100 * modern_lines / max(n, 1):.1f}%) · tổng {modern_hits} lượt")
    print("→ tỉ lệ CAO = phải lọc mạnh trước khi làm mỏ neo; THẤP = neo sạch, đáng trộn.\n")
    print("--- MẪU NGẪU NHIÊN (đọc tay: register có hợp gu cổ trang không?) ---")
    for zh, vi in samples:
        print(f"\nZH: {zh[:120]}\nVI: {vi[:120]}")


if __name__ == "__main__":
    main()
