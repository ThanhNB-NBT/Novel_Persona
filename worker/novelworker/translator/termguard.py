"""Giữ glossary và chữ số khi dịch Hachimi mà không làm mất nội dung.

Dịch thường trước. Chỉ những dòng còn thiếu thuật ngữ mới được thử lại bằng
placeholder; chỉ nhận kết quả khi mọi placeholder sống đủ số lượng. Nếu các họ
mã đều hỏng thì giữ bản dịch thường, tuyệt đối không xóa mảnh mã theo phỏng đoán.
"""
from __future__ import annotations

import itertools
import re
from collections.abc import Callable

# Mã chữ HOA hiếm 2-4 ký tự, chỉ dùng chữ không xuất hiện trong tiếng Việt thuần.
_L = "JWZF"
_CODES = ["JW"] + [
    code for r in (2, 3, 4)
    for code in ("".join(p) for p in itertools.product(_L, repeat=r))
    if code != "JW"
]
_ALNUM_CODES = [f"ZX{i:03d}Q" for i in range(1000)]
_BRACKET_CODES = [f"⟦{i:03d}⟧" for i in range(1000)]
_NUMBER = re.compile(r"\d+(?:\.\d+)?%?")


def _eligible(terms: list[dict], zh: str) -> list[dict]:
    """Term đủ điều kiện cưỡng chế: có term_zh (≥2 ký tự) + correct_vi + đang có trong zh.

    Cụm dài thay trước để không phá cụm con (甲乙 trước 甲)."""
    seen: set[str] = set()
    picked: list[dict] = []
    for t in sorted(
        terms,
        key=lambda t: (not bool(t.get("approved")), -len(t.get("term_zh") or "")),
    ):
        z = (t.get("term_zh") or "").strip()
        vi = (t.get("correct_vi") or "").strip()
        if "nghi sai" in (t.get("note") or ""):
            continue  # đừng ép-inject cứng term mình đã ngờ sai — thà để CT2 tự dịch
        if len(z) >= 2 and vi and z in zh and z not in seen:
            seen.add(z)
            picked.append({**t, "term_zh": z, "correct_vi": vi})
    return picked


def _protect_with_codes(
    zh: str, terms: list[dict], codes: list[str],
) -> tuple[str, dict[str, str]]:
    # Bỏ mã trùng với nội dung đã có sẵn trong nguồn để restore không đụng nhầm.
    codes = [c for c in codes if c not in zh]
    mapping: dict[str, str] = {}
    for term, code in zip(_eligible(terms, zh), codes):
        if term["term_zh"] not in zh:
            continue
        # Bọc space: nguồn Trung không có dấu cách nên 2 term sát nhau ('白银级BOSS')
        # thành 2 mã dính ('12741000'), CT2 fuse/rớt số → 'boss1111'. Space giữ mã tách rời.
        zh = zh.replace(term["term_zh"], f" {code} ")
        mapping[code] = term["correct_vi"]
    return zh, mapping


def _pattern(code: str, alphabet: str) -> re.Pattern[str]:
    body = r"[ \t]*".join(re.escape(char) for char in code)
    return re.compile(
        rf"(?<![{re.escape(alphabet)}]){body}(?![{re.escape(alphabet)}])"
    )


def _restore_complete(
    raw: str, protected: str, mapping: dict[str, str], alphabet: str,
) -> str | None:
    out = raw
    for code, correct_vi in sorted(mapping.items(), key=lambda item: -len(item[0])):
        pattern = _pattern(code, alphabet)
        if len(pattern.findall(raw)) != protected.count(code):
            return None
        out = pattern.sub(correct_vi, out)
    return re.sub(r"[ \t]{2,}", " ", out).strip()


def _line_terms(
    source: str, terms: list[dict], include_numbers: bool = True,
) -> list[dict]:
    if not include_numbers:
        return terms
    numbers: list[dict] = []
    seen: set[str] = set()
    for match in _NUMBER.finditer(source):
        raw = match.group(0)
        if len(raw) < 2 or (match.end() < len(source) and source[match.end()] in "万亿"):
            continue
        if raw not in seen:
            seen.add(raw)
            numbers.append({
                "term_zh": raw, "correct_vi": raw, "approved": True,
            })
    return [*numbers, *terms]


def _repair_numbers(source: str, vi: str) -> tuple[str, bool]:
    source_numbers = list(_NUMBER.finditer(source))
    target_numbers = list(_NUMBER.finditer(vi))
    if len(source_numbers) != len(target_numbers):
        return vi, False
    out = vi
    for source_match, target_match in reversed(list(zip(source_numbers, target_numbers))):
        # Số kèm 万/亿 cần model quy đổi đơn vị: 82亿 -> 8,2 tỷ.
        if source_match.end() < len(source) and source[source_match.end()] in "万亿":
            continue
        out = out[:target_match.start()] + source_match.group(0) + out[target_match.end():]
    for ratio in re.finditer(r"(\d+(?:\.\d+)?)比(\d+(?:\.\d+)?)", source):
        left, right = map(re.escape, ratio.groups())
        out = re.sub(
            rf"(?<!\d){left}\s*[-:：/]\s*{right}(?!\d)",
            f"{ratio.group(1)} trên {ratio.group(2)}",
            out,
            count=1,
        )
    return out, True


def _count_correct(text: str, value: str) -> int:
    if any(char.isdigit() for char in value):
        return len(re.findall(rf"(?<!\d){re.escape(value)}(?!\d)", text))
    return text.casefold().count(value.casefold())


def translate_text(
    zh: str, terms: list[dict], translator: Callable[[str], str],
) -> str:
    """Dịch thường trước; chỉ cưỡng chế lại các dòng còn thiếu term chuẩn."""
    source_lines = zh.split("\n")
    normal_lines = translator(zh).split("\n")
    if len(normal_lines) != len(source_lines):
        raise RuntimeError("Hachimi làm thay đổi số dòng khi dịch thường")

    failed: list[int] = []
    needed_by_line: list[list[dict]] = []
    for index, (source, vi) in enumerate(zip(source_lines, normal_lines)):
        vi, numbers_preserved = _repair_numbers(source, vi)
        normal_lines[index] = vi
        line_terms = _line_terms(source, terms, include_numbers=not numbers_preserved)
        needed = [
            term for term in _eligible(line_terms, source)
            if (
            _count_correct(vi, term["correct_vi"])
            < source.count(term["term_zh"])
            )
        ]
        needed_by_line.append(needed)
        if not numbers_preserved or needed:
            failed.append(index)
    if not failed:
        return "\n".join(normal_lines)

    remaining = failed
    for codes, alphabet, approved_only in (
        (_ALNUM_CODES, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", False),
        (_CODES, _L, False),
        (_BRACKET_CODES, "⟦0123456789⟧", False),
        (_ALNUM_CODES, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", True),
        (_CODES, _L, True),
        (_BRACKET_CODES, "⟦0123456789⟧", True),
    ):
        attempted = [
            index for index in remaining
            if not approved_only or any(
                term.get("approved") for term in needed_by_line[index]
            )
        ]
        untouched = [index for index in remaining if index not in attempted]
        if not attempted:
            continue
        protected_rows: list[str] = []
        mappings: list[dict[str, str]] = []
        for index in attempted:
            retry_terms = needed_by_line[index]
            if approved_only:
                retry_terms = [term for term in retry_terms if term.get("approved")]
            protected, mapping = _protect_with_codes(
                source_lines[index],
                retry_terms,
                codes,
            )
            protected_rows.append(protected)
            mappings.append(mapping)
        raw_rows = translator("\n".join(protected_rows)).split("\n")
        if len(raw_rows) != len(protected_rows):
            raise RuntimeError("Hachimi làm thay đổi số dòng khi retry termguard")

        next_remaining: list[int] = []
        for index, protected, mapping, raw in zip(
            attempted, protected_rows, mappings, raw_rows
        ):
            restored = _restore_complete(raw, protected, mapping, alphabet)
            if restored is None:
                next_remaining.append(index)
            else:
                normal_lines[index] = restored
        remaining = [*untouched, *next_remaining]
        if not remaining:
            break
    # Mọi họ mã đều lỗi: giữ bản dịch thường để tên có thể lệch nhưng không mất câu.
    return "\n".join(normal_lines)


def _self_check() -> None:
    terms = [{"term_zh": "睚眦", "correct_vi": "Nhai Tý"},
             {"term_zh": "冥想项链", "correct_vi": "Dây Chuyền Thiền Định"}]
    zh = "睚眦戴上了冥想项链，睚眦冷笑一声。"
    protected, mapping = _protect_with_codes(zh, terms, _CODES)
    assert "睚眦" not in protected and "冥想项链" not in protected, "term phải bị thay hết"
    assert len(mapping) == 2
    assert len(_CODES) >= 66
    assert all(c.isalpha() for c in mapping), "mã phải là chữ, không số: " + str(list(mapping))
    # Giả lập model: giữ hoa và chèn space giữa các ký tự mã.
    fake_vi = protected
    for code in mapping:
        fake_vi = fake_vi.replace(code, " ".join(code), 1)
    out = _restore_complete(fake_vi, protected, mapping, _L)
    assert out is not None
    assert "Nhai Tý" in out and "Dây Chuyền Thiền Định" in out, out
    # Không được sót mã (chữ HOA hiếm JWZF) — đã restore hết.
    assert not any(c in out for c in mapping), "còn sót mã: " + out
    # Không có term nào trong zh → không đổi gì.
    assert _protect_with_codes("普通句子", terms, _CODES) == ("普通句子", {})
    # Term đã ngờ sai không được ép-inject.
    assert _protect_with_codes("睚眦来了", [{
        "term_zh": "睚眦", "correct_vi": "Sai Bừa", "note": "nghi sai",
    }], _CODES) == ("睚眦来了", {})
    # Hai term SÁT NHAU trong nguồn: mã tách space, không dính → không rớt mảnh.
    adj_terms = [{"term_zh": "白银级", "correct_vi": "bạch ngân cấp"},
                 {"term_zh": "BOSS", "correct_vi": "boss"}]
    p2, m2 = _protect_with_codes("白银级BOSS吞噬", adj_terms, _CODES)
    r2 = _restore_complete(p2, p2, m2, _L)
    assert r2 is not None
    assert not any(c in r2 for c in m2), "còn sót mã: " + r2
    assert "bạch ngân cấp" in r2 and "boss" in r2, r2
    # Dịch thường đúng thì không inject; sai thì alnum lỗi và JWZF cứu, không xoá tên.
    calls: list[str] = []

    def fake_translate(text: str) -> str:
        calls.append(text)
        if "ZX000Q" in text:
            return text.replace("ZX000Q", "ZX00Q")
        if "JW" in text:
            return text
        return text.replace("睚眦", "Xương Tí")

    guarded = translate_text("睚眦来了", [
        {"term_zh": "睚眦", "correct_vi": "Nhai Tý", "approved": True}
    ], fake_translate)
    assert "Nhai Tý" in guarded and len(calls) == 3, (guarded, calls)
    assert [t["term_zh"] for t in _line_terms("82亿、5000、5%", [])] == ["5000", "5%"]
    assert _count_correct("hơn 10000000 năm", "1000000") == 0
    repaired, ok = _repair_numbers("1比1000000，82亿，5%", "1-10000000, 800 triệu, 5")
    assert ok and repaired == "1 trên 1000000, 800 triệu, 5%", repaired
    overlap, overlap_map = _protect_with_codes("睚眦必报", [
        {"term_zh": "睚眦必报", "correct_vi": "Nhai Tí Tất Báo", "approved": False},
        {"term_zh": "睚眦", "correct_vi": "Nhai Tý", "approved": True},
    ], _ALNUM_CODES)
    assert list(overlap_map.values()) == ["Nhai Tý"] and "必报" in overlap
    print("termguard OK:", out)


if __name__ == "__main__":
    _self_check()
