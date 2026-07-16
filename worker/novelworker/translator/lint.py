"""Lint nhanh bản dịch, không gọi LLM."""
from __future__ import annotations

from collections import defaultdict
import re

from .prompts import self_reference_omissions


_RULES: list[tuple[str, re.Pattern]] = [
    ("'X một cái' kiểu convert", re.compile(r"(?:cười|nhìn|liếc|gật đầu|thở dài|vỗ|đá|đấm|lắc đầu|hôn|ôm|cắn|nhảy|hét|quét)\s+một cái", re.I)),
    ("'tiến hành/thực hiện + động từ'", re.compile(r"\b(?:tiến hành|thực hiện)\s+(?:tấn công|phòng ngự|tu luyện|điều tra|chữa trị|luyện chế|thăm dò|so sánh)", re.I)),
    ("'đối với X tới nói'", re.compile(r"đối với\s+[^,.;!?]{1,30}\s+(?:tới|mà)\s+nói", re.I)),
    ("'trên thực tế'", re.compile(r"\btrên thực tế\b", re.I)),
    ("markdown lọt (** # ```)", re.compile(r"\*\*|^#{1,3}\s|```", re.M)),
    ("phiên âm gạch nối (An-đê-ri-an)", re.compile(r"\b[A-ZĐ][a-zà-ỹ]+(?:-[a-zà-ỹ]+){2,}\b")),
    ("'Lão Chủ' (老板 dịch sai)", re.compile(r"\bLão Chủ\b")),
    ("gọi nhân vật 'cậu/bạn' trong lời kể", re.compile(r"(?:^|\. )[^\"“\n]{0,80}\bkỳ vọng (?:cậu|bạn)\b")),
    ("'Anh/Cô' trần đầu câu kể (nghi vấn)", re.compile(r"(?:^|[.!?…]\s+)(?:Anh|Cô)\s+(?!ta\b|ấy\b|trai\b|hùng\b|nương\b|gái\b|em\b)[a-zà-ỹ]+")),
    ("convert 'không khỏi'", re.compile(r"\bkhông khỏi\b", re.I)),
    ("convert 'căn bản là'", re.compile(r"\bcăn bản là\b", re.I)),
    ("convert 'rốt cuộc là'", re.compile(r"\brốt cuộc là\b", re.I)),
    ("convert 'trực tiếp + động từ'", re.compile(r"\btrực tiếp\s+(?:đi|đến|nói|hỏi|ra tay|đánh|giết|ném|đẩy|mở|đóng)\b", re.I)),
    ("lượng từ 'một đầu' (一头)", re.compile(r"\bmột đầu\b(?!\s+tiên)", re.I)),
    ("pinyin lọt (ā ǎ ē...)", re.compile(r"[āēīōūǖǎěǐǒǔǘǚǜ]")),
    ("'gia tộc X' (nên 'X Gia/X thị')", re.compile(r"\b[Gg]ia tộc\s+[A-ZĐ][a-zà-ỹ]*\b")),
    ("tượng thanh tiếng Anh", re.compile(r"\b(?:cough|sigh|ahem|gasp|hmph|tsk)\b", re.I)),
    ("convert 'tổng cảm thấy' (总感觉)", re.compile(r"\btổng cảm thấy\b", re.I)),
    ("chữ Hán sót lẻ", re.compile(r"[一-鿿㐀-䶿]+")),
]
_CHANG_THRESHOLD = 4
_DIALOGUE = re.compile(r'"[^"\n]*"|“[^”]*”|「[^」]*」|^[ \t]*[—–-]\s+[^\n]*', re.M)
_NARRATOR_TERMS = re.compile(r"\b(?:hắn|nàng|y|gã|lão|tôi|(?<!chúng\s)(?<!người\s)ta|anh(?:\s+ta)?|cậu\s+ta|cô(?:\s+ấy|\s+ta)?|ông\s+ta)\b", re.I)


def _han_repeat_density(vi: str) -> list[str]:
    return [sent.strip()[:90] for sent in re.split(r"[.!?…][\"”’]*\s+|\n+", vi)
            if len(re.findall(r"\bhắn\b", sent, re.I)) >= 3]


def _exclaim_density(vi: str) -> int:
    return sum(1 for paragraph in vi.split("\n") if paragraph.count("!") > 2)


def narrator_terms(vi: str) -> dict[str, int]:
    out: dict[str, int] = defaultdict(int)
    for term in _NARRATOR_TERMS.findall(_DIALOGUE.sub(" ", vi)):
        out[term.lower()] += 1
    return dict(out)


def _self_reference_omissions(zh: str | None, vi: str) -> list[str]:
    return self_reference_omissions(zh, vi) if zh else []


def _self_reference_warnings(zh: str | None, vi: str) -> list[str]:
    return [f"[xưng hô] {missing}" for missing in _self_reference_omissions(zh, vi)]


def _narrator_mix_warnings(vi: str) -> list[str]:
    """Lời kể trôi đại từ: cùng chương vừa 'hắn' vừa 'y' dày đặc gần như luôn là drift.
    Chỉ xét cặp hắn/y — gã/lão thường là nhân vật phụ được gọi chủ ý."""
    counts = narrator_terms(vi)
    han, y = counts.get("hắn", 0), counts.get("y", 0)
    if han >= 3 and y >= 3:
        return [f"[xưng hô] lời kể trộn 'hắn' ×{han} với 'y' ×{y} — nghi trôi đại từ nhân vật chính"]
    return []


def _dialogue_self_minh(vi: str) -> list[str]:
    hits = []
    for match in _DIALOGUE.finditer(vi):
        segment = match.group(0)
        if re.search(r"(?:^|[\"“,.!?…:]\s*)[Mm]ình\s+(?:đã|chắc|sẽ|không|chẳng|phải|cũng|còn|vừa|mới|chết|bị|đang)", segment):
            hits.append(segment[:60])
    return hits


def _style_warnings(vi: str) -> list[str]:
    problems = []
    for name, pattern in _RULES:
        hits = pattern.findall(vi)
        if hits:
            problems.append(f"[lint] {name}: {len(hits)} lần (vd '{str(hits[0])[:40]}')")
    for sentence in _han_repeat_density(vi)[:3]:
        problems.append(f"[lint] lặp 'hắn' ≥3/câu: {sentence}")
    exclaims = _exclaim_density(vi)
    if exclaims:
        problems.append(f"[lint] {exclaims} đoạn quá 2 dấu '!'")
    chang = len(re.findall(r"\bchẳng\b", vi, re.I))
    if chang >= _CHANG_THRESHOLD:
        problems.append(f"[văn phong] 'chẳng' ×{chang} — mặc định dùng 'không'")
    for segment in _dialogue_self_minh(vi)[:3]:
        problems.append(f"[xưng hô] 'mình' tự xưng trong thoại (nghi vấn): {segment}")
    problems += _narrator_mix_warnings(vi)
    return problems


def lint_warnings(zh: str | None, vi: str) -> list[str]:
    """Danh sách cảnh báo regex; thiếu nguồn thì bỏ luật đối chiếu nguồn."""
    return _self_reference_warnings(zh, vi) + _style_warnings(vi)


def lint_score(zh: str | None, vi: str) -> int:
    """Số cảnh báo lint; 0 là sạch."""
    return len(lint_warnings(zh, vi))
