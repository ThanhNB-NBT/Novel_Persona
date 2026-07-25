"""Gói train v4 = mix v3 sau khi siết cổng và mở rộng booster theo lỗi user đọc thấy.

Khác v3:
- booster 672 → 715 câu: thêm danh xưng thân tộc cổ phong (ca ca/tỷ tỷ/muội muội/đệ đệ),
  小孙 = "cháu ta", 高中 = "trường cấp ba", 冷却 = CD, và các biến thể động từ của 枪.
- gold nhịp câu chấm lại bằng cổng có thêm luật "danh xưng hiện đại" (2.492 → 2.478 dòng).
- replay và eval giữ nguyên để so được với v3.
"""
from __future__ import annotations

import json
from pathlib import Path

from prepare_teacher_v3_pack import build as build_v3


PACK = Path(__file__).resolve().parents[1] / "packs" / "hachimi-teacher-v4-kaggle.zip"


def build() -> dict:
    import prepare_teacher_v3_pack as v3

    original, v3.PACK = v3.PACK, PACK
    try:
        return build_v3()
    finally:
        v3.PACK = original


if __name__ == "__main__":
    result = build()
    assert result["leakage"] == 0
    print(json.dumps(result, ensure_ascii=False, indent=2))
