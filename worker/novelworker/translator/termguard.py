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
        if "nghi sai" in (t.get("note") or ""):
            continue  # đừng ép-inject cứng term mình đã ngờ sai — thà để CT2 tự dịch
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
        # Bọc space: nguồn Trung không có dấu cách nên 2 term sát nhau ('白银级BOSS')
        # thành 2 mã dính ('12741000'), CT2 fuse/rớt số → 'boss1111'. Space giữ mã tách rời.
        zh = zh.replace(term["term_zh"], f" {code} ")
        mapping[code] = term["correct_vi"]
    return zh, mapping


def restore(vi: str, mapping: dict[str, str]) -> str:
    """Thay ngược mã số về bản Việt. Chịu được việc model chèn space giữa các chữ số,
    và chèn space khi mã dính liền chữ cái ('1137cười' -> 'Nhai Tý cười') — nguồn Trung
    không có dấu cách nên CT2 hay dán mã sát từ kế bên, thiếu pad là ra 'Nhai Týcười'."""
    for code, term_vi in mapping.items():
        pattern = r"\s*".join(re.escape(d) for d in code)  # "1137" -> "1\s*1\s*3\s*7"

        def repl(m: re.Match, t: str = term_vi) -> str:
            s, e, whole = m.start(), m.end(), m.string
            lead = " " if s > 0 and whole[s - 1].isalnum() and t[:1].isalnum() else ""
            trail = " " if e < len(whole) and whole[e].isalnum() and t[-1:].isalnum() else ""
            return lead + t + trail

        vi = re.sub(pattern, repl, vi)
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
    # Mã dán sát chữ cái (CT2 hay ra vậy) phải được tách space, không ra "Nhai Týcười".
    glued = restore("1137cười lạnh", {"1137": "Nhai Tý"})
    assert glued == "Nhai Tý cười lạnh", glued
    assert restore("đeo1137", {"1137": "Nhai Tý"}) == "đeo Nhai Tý"
    # Term đã ngờ sai không được ép-inject.
    assert protect("睚眦来了", [{"term_zh": "睚眦", "correct_vi": "Sai Bừa",
                              "note": "nghi sai"}]) == ("睚眦来了", {})
    # Hai term SÁT NHAU trong nguồn: mã không được dính (nếu không CT2 fuse → rớt số).
    adj_terms = [{"term_zh": "白银级", "correct_vi": "bạch ngân cấp"},
                 {"term_zh": "BOSS", "correct_vi": "boss"}]
    p2, m2 = protect("白银级BOSS吞噬", adj_terms)
    assert not re.search(r"\d{5,}", p2.replace(" ", "X")), "mã bị dính: " + p2
    # model giữ nguyên mã (kèm khoảng trắng) → restore ra sạch, không rớt digit.
    assert not any(c.isdigit() for c in restore(p2, m2)), restore(p2, m2)
    print("termguard OK:", out)


if __name__ == "__main__":
    _self_check()
