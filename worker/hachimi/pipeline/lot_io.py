"""Đọc file lô dịch, vá được dòng JSON hỏng vì nháy chưa thoát.

Vì sao cần: model dịch tiểu thuyết thì câu nào cũng có thoại, và nó hay đổi nháy cong “ ”
của nguồn thành nháy thẳng " rồi quên thoát — vỡ ngay dòng JSON của chính nó.

Đo 02/09 trên cùng lô 0000:
    Sonnet 5      0/120 dòng hỏng
    Sonnet 4.6   33/120
    Sonnet 4.5   33/120
    Haiku 4.5    34/120
Sonnet 5 vẫn dính lẻ tẻ (lô 0041: 52/120). Cấu trúc dòng thì còn nguyên, nên vá bằng máy
được — rẻ hơn dịch lại cả lô, và không phải đánh đổi gì vì nội dung không đổi.

BẪY: đừng dùng thước "thiếu dòng" cho ca này. Bản chấm cũ bỏ qua dòng không parse được rồi
báo "lệch số dòng", đúng kết quả nhưng sai nguyên nhân — suýt đi dịch lại lô 0041 trong khi
chỉ cần thoát ký tự.
"""
from __future__ import annotations

import json
import re

# Neo hai đầu nên `(.*)` tham lam ăn trọn phần giữa, kể cả nháy chưa thoát bên trong.
_LOOSE = re.compile(r'^\s*\{\s*"n"\s*:\s*(\d+)\s*,\s*"vi"\s*:\s*"(.*)"\s*\}\s*,?\s*$', re.S)
# Kiểu hỏng thứ hai (lô 0041, 32/120 dòng): mất luôn dấu `}` đóng. Vẫn vá được, nhưng CHỈ
# khi dòng kết thúc bằng nháy đóng chuỗi — đó là bằng chứng câu đã viết trọn, chỉ rụng dấu
# đóng object. Dòng cụt giữa câu không có nháy cuối nên rơi xuống nhánh chịu thua.
_NO_BRACE = re.compile(r'^\s*\{\s*"n"\s*:\s*(\d+)\s*,\s*"vi"\s*:\s*"(.*)"\s*$', re.S)


def parse_row(line: str) -> tuple[dict | None, bool]:
    """Trả (bản ghi, có_phải_vá_không). Không đọc nổi thì (None, False)."""
    line = line.strip()
    if not line:
        return None, False
    try:
        row = json.loads(line)
    except json.JSONDecodeError:
        pass
    else:
        return (row, False) if isinstance(row, dict) else (None, False)
    m = _LOOSE.match(line) or _NO_BRACE.match(line)
    if not m:
        return None, False
    # `\"` trong nguồn là nháy đã thoát đúng; phần còn lại là nháy trần, giữ nguyên cả hai.
    return {"n": int(m.group(1)), "vi": m.group(2).replace('\\"', '"')}, True


def read_out(path) -> tuple[dict[int, str], int, int]:
    """Trả (map n→vi, số dòng đã vá, số dòng chịu thua)."""
    got: dict[int, str] = {}
    fixed = lost = 0
    for line in open(path, encoding="utf-8"):
        if not line.strip():
            continue
        row, was_fixed = parse_row(line)
        if row is None or not str(row.get("n", "")).isdigit():
            lost += 1
            continue
        got[int(row["n"])] = str(row.get("vi", ""))
        fixed += was_fixed
    return got, fixed, lost


def _self_check() -> None:
    ok, f = parse_row('{"n": 1, "vi": "bình thường"}')
    assert ok == {"n": 1, "vi": "bình thường"} and not f
    bad = '{"n": 6, "vi": "Hắn nói: "Bản quan là văn thư, phải ngươi hát không?""}'
    row, f = parse_row(bad)
    assert f and row["n"] == 6, row
    assert row["vi"] == 'Hắn nói: "Bản quan là văn thư, phải ngươi hát không?"', row["vi"]
    # Dòng cụt giữa chừng (thiếu dấu đóng) thì PHẢI chịu thua, đừng đoán bừa —
    # đoán bừa ở đây là cách chắc chắn để nhét nửa câu vào corpus.
    assert parse_row('{"n": 4, "vi": "câu bị cắt ngang') == (None, False)
    # Mất dấu `}` nhưng câu viết trọn (có nháy cuối) thì vá được
    row, f = parse_row('{"n": 9, "vi": "quát lớn: "Đứng lại!""')
    assert f and row == {"n": 9, "vi": 'quát lớn: "Đứng lại!"'}, row
    print("lot_io self-check OK")


if __name__ == "__main__":
    _self_check()
