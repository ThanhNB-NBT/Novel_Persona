"""Cưỡng chế tên riêng cho engine Hachimi bằng placeholder SỐ.

Model MT câu→câu không có glossary: tên hiếm/nghĩa bị đoán bừa, mỗi chỗ một kiểu
(睚眦 → Mộ Tắc / Mão Tí / Mô Tễ...). Đã đo: chuỗi SỐ THUẦN được model copy
nguyên vẹn 100% qua mọi kiểu câu. Nên trước khi dịch, thay mỗi term glossary bằng
một mã số 4 chữ số duy nhất (`protect`); dịch xong thay ngược lại đúng bản Việt đã
duyệt (`restore`). Tên luôn đúng + nhất quán, không trông vào model.
"""
from __future__ import annotations

import re

# Mã 4 chữ số, cách nhau 137 để model không dính/nuốt (đo: gần nhau bị gộp).
_CODES = [str(n) for n in range(1000, 10000, 137)]


def _eligible(terms: list[dict], zh: str) -> list[dict]:
    """Term đủ điều kiện cưỡng chế: có term_zh (≥2 ký tự) + correct_vi + đang có trong zh.

    Cụm dài thay trước để không phá cụm con (甲乙 trước 甲)."""
    seen: set[str] = set()
    picked: list[dict] = []
    for t in sorted(terms, key=lambda t: -len(t.get("term_zh") or "")):
        z = (t.get("term_zh") or "").strip()
        vi = (t.get("correct_vi") or "").strip()
        if len(z) >= 2 and vi and z in zh and z not in seen:
            seen.add(z)
            picked.append({"term_zh": z, "correct_vi": vi})
    return picked


def protect(zh: str, terms: list[dict]) -> tuple[str, dict[str, str]]:
    """Thay mỗi term glossary trong zh bằng mã số duy nhất. Trả (zh_đã_thay, {mã: bản_Việt})."""
    # Bỏ mã trùng với số đã có sẵn trong nguồn để restore không đụng nhầm.
    codes = [c for c in _CODES if c not in zh]
    mapping: dict[str, str] = {}
    for term, code in zip(_eligible(terms, zh), codes):
        zh = zh.replace(term["term_zh"], code)
        mapping[code] = term["correct_vi"]
    return zh, mapping


def restore(vi: str, mapping: dict[str, str]) -> str:
    """Thay ngược mã số về bản Việt. Chịu được việc model chèn space giữa các chữ số."""
    for code, term_vi in mapping.items():
        pattern = r"\s*".join(re.escape(d) for d in code)  # "1137" -> "1\s*1\s*3\s*7"
        vi = re.sub(pattern, term_vi, vi)
    vi = re.sub(r"[ \t]{2,}", " ", vi)          # gộp space thừa quanh chỗ vừa thay
    vi = re.sub(r"\s+([,.;:!?…”’)])", r"\1", vi)  # bỏ space trước dấu câu
    return vi


def _self_check() -> None:
    terms = [{"term_zh": "睚眦", "correct_vi": "Nhai Tý"},
             {"term_zh": "冥想项链", "correct_vi": "Dây Chuyền Thiền Định"}]
    zh = "睚眦戴上了冥想项链，睚眦冷笑一声。"
    protected, mapping = protect(zh, terms)
    assert "睚眦" not in protected and "冥想项链" not in protected, "term phải bị thay hết"
    assert len(mapping) == 2
    # Giả lập model: giữ số, dịch phần còn lại + thử chèn space giữa số.
    fake_vi = protected
    for code in mapping:
        fake_vi = fake_vi.replace(code, " ".join(code), 1)  # chèn space 1 lần cho khắc nghiệt
    out = restore(fake_vi, mapping)
    assert "Nhai Tý" in out and "Dây Chuyền Thiền Định" in out, out
    assert not any(c.isdigit() for c in out), "không được sót mã số: " + out
    # Không có term nào trong zh → không đổi gì.
    assert protect("普通句子", terms) == ("普通句子", {})
    print("termguard OK:", out)


if __name__ == "__main__":
    _self_check()
