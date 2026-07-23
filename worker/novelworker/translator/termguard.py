"""Cưỡng chế tên riêng cho engine Hachimi bằng placeholder CHỮ HOA hiếm.

Model MT câu→câu không có glossary: tên hiếm/nghĩa bị đoán bừa, mỗi chỗ một kiểu
(睚眦 → Mộ Tắc / Mão Tí / Mô Tễ...). Nên trước khi dịch, thay mỗi term glossary bằng
một mã duy nhất (`protect`); dịch xong thay ngược lại đúng bản Việt đã duyệt (`restore`).

Trước dùng mã SỐ 4 chữ số nhưng khi nhiều term tier nằm dày trong 1 câu (末世 LitRPG:
黄金级别BOSS 白银级别BOSS...) CT2 mangle số thành MẢNH RỚT nhìn thấy được ('boss1111',
số 11/1 lạc giữa câu). Đo trên model thật (5 chương tier-nặng): mã CHỮ để lại 0 mảnh
rớt, mã số 1-3 mảnh/chương — vì mã chữ hỏng thì HOẶC sống nguyên HOẶC biến mất sạch
(term không được ép, MT tự dịch — vô hại), không để lại rác như số. Dùng phụ âm hiếm
né B/O/S/L/V/I/P để không đụng 'BOSS'/'LV'/'VIP' và không tự khớp nhầm chữ thật.
"""
from __future__ import annotations

import itertools
import re

# Mã chữ HOA hiếm 2-3 ký tự (49 + 343 = 392 mã, dư cho chương nhiều term).
_L = "QXZJWKF"
_CODES = ["".join(p) for r in (2, 3) for p in itertools.product(_L, repeat=r)]


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
    """Thay ngược mã về bản Việt. Chịu được model chèn space giữa các ký tự mã ('Q X'),
    đổi hoa/thường (re.I), và chèn space khi mã dính liền chữ cái ('QXcười' -> 'Nhai Tý
    cười') — nguồn Trung không có dấu cách nên CT2 hay dán mã sát từ kế bên."""
    for code, term_vi in mapping.items():
        pattern = r"\s*".join(re.escape(d) for d in code)  # "QX" -> "Q\s*X"

        def repl(m: re.Match, t: str = term_vi) -> str:
            s, e, whole = m.start(), m.end(), m.string
            lead = " " if s > 0 and whole[s - 1].isalnum() and t[:1].isalnum() else ""
            trail = " " if e < len(whole) and whole[e].isalnum() and t[-1:].isalnum() else ""
            return lead + t + trail

        vi = re.sub(pattern, repl, vi, flags=re.I)
    # Dọn mã SÓT: CT2 NHÁI kiểu mã — thấy token 2-3 chữ HOA hiếm thì tự chế thêm cho tên
    # game/vật phẩm nó không dịch được (thường trong ngoặc: '"JQ"'). Token bịa không nằm
    # trong mapping nên không restore được. Tổ hợp QXZJWKF không phải từ Việt/Latin tự
    # nhiên → xoá sạch cả mã thật chưa khớp lẫn mã model bịa.
    vi = re.sub(rf"\b[{_L}]{{2,3}}\b", "", vi)  # HOA-only: mã model bịa đều HOA; né chữ thường Việt
    vi = re.sub(r'"\s*"|“\s*”|「\s*」|【\s*】', "", vi)  # ngoặc rỗng còn lại sau khi xoá mã
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
    assert all(c.isalpha() for c in mapping), "mã phải là chữ, không số: " + str(list(mapping))
    # Giả lập model: giữ mã, chèn space + đổi case giữa mã cho khắc nghiệt.
    fake_vi = protected
    for code in mapping:
        fake_vi = fake_vi.replace(code, " ".join(code).lower(), 1)
    out = restore(fake_vi, mapping)
    assert "Nhai Tý" in out and "Dây Chuyền Thiền Định" in out, out
    # Không được sót mã (chữ HOA hiếm QXZJWKF) — đã restore hết.
    assert not any(c in out for c in mapping), "còn sót mã: " + out
    # Không có term nào trong zh → không đổi gì.
    assert protect("普通句子", terms) == ("普通句子", {})
    # Mã dán sát chữ cái (CT2 hay ra vậy) phải được tách space, không ra "Nhai TýXX".
    glued = restore("QXcười lạnh", {"QX": "Nhai Tý"})
    assert glued == "Nhai Tý cười lạnh", glued
    assert restore("đeoQX", {"QX": "Nhai Tý"}) == "đeo Nhai Tý"
    # Term đã ngờ sai không được ép-inject.
    assert protect("睚眦来了", [{"term_zh": "睚眦", "correct_vi": "Sai Bừa",
                              "note": "nghi sai"}]) == ("睚眦来了", {})
    # Hai term SÁT NHAU trong nguồn: mã tách space, không dính → không rớt mảnh.
    adj_terms = [{"term_zh": "白银级", "correct_vi": "bạch ngân cấp"},
                 {"term_zh": "BOSS", "correct_vi": "boss"}]
    p2, m2 = protect("白银级BOSS吞噬", adj_terms)
    r2 = restore(p2, m2)
    assert not any(c in r2 for c in m2), "còn sót mã: " + r2
    assert "bạch ngân cấp" in r2 and "boss" in r2, r2
    # Mã model BỊA (không có trong mapping) phải bị dọn, kể cả ngoặc rỗng theo sau.
    assert restore('cầm "JQ" lên', {}) == "cầm lên", restore('cầm "JQ" lên', {})
    assert "FZ" not in restore("một chai FZ của thanh đồng", {}), "mã bịa phải bị xoá"
    # KHÔNG được nuốt chữ thường tiếng Việt bình thường.
    assert restore("xa xôi quạnh quẽ", {}) == "xa xôi quạnh quẽ"
    print("termguard OK:", out)


if __name__ == "__main__":
    _self_check()
