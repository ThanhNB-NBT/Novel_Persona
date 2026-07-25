"""Engine dịch CT2 (HachimiMT) — thay LLM cho truyện đặt engine 'hachimi'.

Model MT câu→câu (60M): dịch theo TỪNG DÒNG (đoạn), giữ khung xuống dòng của
chương. Nhẹ RAM: tokenize thẳng bằng sentencepiece, KHÔNG cần transformers.
Singleton lazy — nạp CT2 + spm một lần cho mỗi tiến trình worker.
"""
from __future__ import annotations

import re
import threading

from ..config import settings
from .text_clean import clean_source

_EOS = "</s>"
_lock = threading.Lock()
_engine: "_Engine | None" = None
_SOFT_END = re.compile(r'.+?(?:[，,、：:]+|$)')
_SPACE_BEFORE = re.compile(r'\s+([,.;:!?…。，！？；：”’」』】）》）])')
_SPACE_AFTER = re.compile(r'([“‘「『【《（(])\s+')
_HAN = re.compile(r"[一-鿿㐀-䶿]")
# Model viết hoa đầu MỖI mảnh; chỉ giữ hoa khi mảnh trước thật sự kết câu.
_SENT_END = re.compile(r'[.!?:…。！？：][”’"\'」』）)\]]*$')


def _decap(part: str) -> str:
    """Hạ chữ hoa đầu mảnh khi mảnh đó chỉ là vế sau dấu phẩy, trừ khi trông như tên riêng."""
    index = next((i for i, char in enumerate(part) if char.isalpha()), None)
    if index is None:
        return part
    word, _, rest = part[index:].partition(" ")
    # BOSS/NPC, mã placeholder termguard (ZX001Q) và tên riêng 2 âm tiết ("Ngạo Thiên") giữ nguyên.
    if not word[:1].isupper() or word.isupper() or any(c.isdigit() for c in word) or rest[:1].isupper():
        return part
    return part[:index] + word[:1].lower() + part[index + 1:]


def _join_translations(parts: list[str]) -> str:
    joined: list[str] = []
    for part in (part.strip() for part in parts):
        if not part:
            continue
        joined.append(_decap(part) if joined and not _SENT_END.search(joined[-1]) else part)
    text = " ".join(joined)
    return _SPACE_AFTER.sub(r"\1", _SPACE_BEFORE.sub(r"\1", text))


_MODERN_VI = re.compile(r"(?i)(?<!\w)(?:tôi|mình|bạn|cậu|cháu|anh ta|cô ta|cô ấy|ông ta|bà ta)(?!\w)")
_DIGITS = re.compile(r"\d+")
# Danh xưng thân tộc: nguồn có 哥哥 mà đích ra "anh trai" là lệch văn phong cổ.
_KINSHIP = (("哥哥", "anh trai"), ("姐姐", "chị gái"), ("妹妹", "em gái"), ("弟弟", "em trai"))
# Cụm 1-3 từ lặp liền ("ngu ngốc đến mức ngu ngốc", "một một") — tật cố hữu của model nhỏ.
_REPEAT = re.compile(r"(?i)\b([\wÀ-ỹ]+(?:\s+[\wÀ-ỹ]+){0,2})\s+\1\b")


def _rank_penalty(source: str, candidate: str) -> float:
    """Điểm phạt để chọn trong n-best. Beam search đã tính sẵn 4 giả thuyết, lấy hết ra
    gần như không tốn thêm gì — nên dùng chính các cổng chất lượng của dự án để chọn,
    thay vì luôn nhận giả thuyết có xác suất cao nhất."""
    penalty = 10.0 * len(_MODERN_VI.findall(candidate))
    penalty += 10.0 * len(_HAN.findall(candidate))
    penalty += 5.0 * (_DIGITS.findall(source) != _DIGITS.findall(candidate))
    # Ngoặc kép: chỉ phạt khi NGUỒN cân mà đích lệch. Câu dài bị cắt thành nhiều mảnh thì
    # mảnh mở và mảnh đóng nằm ở hai chỗ — phạt mù sẽ chọn nhầm giả thuyết xấu hơn.
    source_quotes = source.count("“") + source.count("”") + source.count("「") + source.count("」")
    if source_quotes % 2 == 0:
        penalty += 3.0 * any(
            candidate.count(left) != candidate.count(right)
            for left, right in (("“", "”"), ("「", "」"), ("『", "』"))
        )
    penalty += 5.0 * sum(
        zh in source and vi.lower() in candidate.lower() for zh, vi in _KINSHIP
    )
    penalty += 4.0 * len(_REPEAT.findall(candidate))
    # Nhịp: mỗi dấu kết câu nguồn nên cho ~2 câu tiếng Việt (đo ở docs/hachimi_rhythm_research.md).
    stops = sum(candidate.count(char) for char in ".!?") or 1
    source_stops = sum(source.count(char) for char in "。！？") or 1
    penalty += abs(stops / source_stops - 2.0)
    return penalty


class _Engine:
    def __init__(self, model_dir: str, nbest: int | None = None, beam: int | None = None):
        import ctranslate2
        import sentencepiece as spm

        self.nbest = nbest if nbest is not None else settings.hachimi_nbest
        self.beam = beam if beam is not None else settings.hachimi_beam_size
        self.translator = ctranslate2.Translator(
            model_dir, device="cpu", compute_type=settings.hachimi_compute_type,
            intra_threads=settings.hachimi_cpu_threads or 0)
        self.src = spm.SentencePieceProcessor()
        self.src.load(f"{model_dir}/source.spm")
        self.tgt = spm.SentencePieceProcessor()
        self.tgt.load(f"{model_dir}/target.spm")

    def _hard_split(self, text: str, limit: int) -> list[str]:
        if len(self.src.encode(text)) <= limit:
            return [text]
        lo, hi = 1, len(text) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if len(self.src.encode(text[:mid])) <= limit:
                lo = mid
            else:
                hi = mid - 1
        cut = lo
        # Không cắt giữa placeholder/từ Latin như ZX001Q hoặc BOSS.
        while (cut > 1 and cut < len(text)
               and text[cut - 1].isascii() and text[cut - 1].isalnum()
               and text[cut].isascii() and text[cut].isalnum()):
            cut -= 1
        if cut <= 0 or cut >= len(text):
            raise RuntimeError("Không thể chia nhỏ câu nguồn Hachimi")
        return [text[:cut], *self._hard_split(text[cut:], limit)]

    def _split_source(self, line: str) -> list[str]:
        limit = max(32, settings.hachimi_max_len // 2)
        pairs = {"“": "”", "‘": "’", "「": "」", "『": "』"}
        stack: list[str] = []
        sentences: list[str] = []
        start = 0
        for index, char in enumerate(line):
            if char in pairs:
                stack.append(pairs[char])
            elif stack and char == stack[-1]:
                stack.pop()
            elif not stack and char in "。！？!?；;":
                sentences.append(line[start:index + 1])
                start = index + 1
        if start < len(line):
            sentences.append(line[start:])
        if not sentences:
            sentences = [line]
        out: list[str] = []
        for sentence in sentences:
            clauses = ([m.group(0) for m in _SOFT_END.finditer(sentence) if m.group(0)]
                       if len(self.src.encode(sentence)) > limit else [sentence])
            for clause in clauses:
                out.extend(self._hard_split(clause, limit))
        return out

    def _translate_safe(self, lines: list[str]) -> list[str]:
        # Marian cần </s> cuối nguồn, nếu thiếu model dịch xong không biết dừng → lặp.
        source = [self.src.encode(line, out_type=str) + [_EOS] for line in lines]
        nbest = max(1, min(self.nbest, self.beam))
        results = self.translator.translate_batch(
            source, beam_size=self.beam,
            num_hypotheses=nbest,
            max_decoding_length=settings.hachimi_max_len)
        out: list[str] = []
        for line, res in zip(lines, results):
            best = res.hypotheses[0]
            if nbest > 1:
                best = min(
                    res.hypotheses,
                    key=lambda h: _rank_penalty(line, self.tgt.decode([t for t in h if t != _EOS])),
                )
            tokens = [t for t in best if t != _EOS]
            decoded = self.tgt.decode(tokens)
            if len(tokens) < settings.hachimi_max_len and not _HAN.search(decoded):
                out.append(decoded)
                continue
            soft = [m.group(0) for m in _SOFT_END.finditer(line) if m.group(0)]
            parts = (soft if _HAN.search(decoded) and len(soft) > 1 else
                     self._hard_split(line, max(8, len(self.src.encode(line)) // 2)))
            if len(parts) == 1:
                reason = "còn chữ Hán" if _HAN.search(decoded) else "chạm trần output"
                raise RuntimeError(f"Hachimi {reason} dù nguồn không thể chia tiếp")
            out.append(_join_translations(self._translate_safe(parts)))
        return out

    def translate_lines(self, lines: list[str]) -> list[str]:
        groups: list[tuple[int, int]] = []
        pieces: list[str] = []
        for line in lines:
            start = len(pieces)
            pieces.extend(self._split_source(line))
            groups.append((start, len(pieces)))
        translated = self._translate_safe(pieces)
        return [_join_translations(translated[start:end]) for start, end in groups]


def available() -> bool:
    """True nếu dịch được bằng Hachimi: ctranslate2 đã cài + thư mục model có model.bin.

    Cho phép deploy code trước khi VPS kịp có model/deps — thiếu thì worker tự lùi về LLM
    thay vì fail job (xem handle_chapter)."""
    import importlib.util
    import os

    if importlib.util.find_spec("ctranslate2") is None:
        return False
    return os.path.isfile(os.path.join(settings.hachimi_model_dir, "model.bin"))


def _get() -> _Engine:
    global _engine
    if _engine is None:
        with _lock:
            if _engine is None:
                _engine = _Engine(settings.hachimi_model_dir)
    return _engine


def translate_text(text: str) -> str:
    """Dịch một khối văn giữ khung dòng: dòng trắng giữ nguyên, dòng có chữ dịch qua CT2.

    Dịch theo dòng (đoạn) vì model là MT câu→câu; batch cả khối cho nhanh.
    """
    lines = text.split("\n")
    idx = [i for i, line in enumerate(lines) if clean_source(line)]
    if not idx:
        return text
    cleaned = [clean_source(lines[i]) for i in idx]
    translated = _get().translate_lines(cleaned)
    out = list(lines)
    for i, vi in zip(idx, translated):
        out[i] = vi
    return "\n".join(out)


def _self_check() -> None:
    """python -m novelworker.translator.hachimi_engine — cần HACHIMI_MODEL_DIR trỏ model thật."""
    src = "少年握紧手中长剑。\n\n灵气在丹田中缓缓凝聚。"
    vi = translate_text(src)
    assert vi.count("\n") == src.count("\n"), "phải giữ nguyên khung dòng"
    assert "\n\n" in vi, "dòng trắng phải còn"
    for line in vi.split("\n"):
        assert not any("一" <= c <= "鿿" for c in line), f"còn chữ Hán: {line}"
    assert _join_translations(['"Xin chào!"', '"Đi thôi."']) == '"Xin chào!" "Đi thôi."'
    # Vế sau dấu phẩy phải hạ chữ hoa, nhưng tên riêng và mã placeholder thì không.
    assert _join_translations(["Hắn nhíu mày,", "Nền tảng lại kém."]) == "Hắn nhíu mày, nền tảng lại kém."
    assert _join_translations(["Hắn buông tay,", "Ngạo Thiên lùi lại."]) == "Hắn buông tay, Ngạo Thiên lùi lại."
    assert _join_translations(["Hắn quát:", "Đi thôi!"]) == "Hắn quát: Đi thôi!"
    assert _join_translations(["Hắn hỏi,", "ZX001Q gật đầu."]) == "Hắn hỏi, ZX001Q gật đầu."
    dialogue = "“你不会吧？连这都问呀？”他说道！"
    assert _get()._split_source(dialogue) == [dialogue], "không được xé một lượt thoại"
    long_src = "少年握紧手中长剑。" * 30
    assert len(_get()._split_source(long_src)) > 1, "đoạn dài phải được chia nhỏ"
    print("hachimi_engine OK:\n" + vi)


if __name__ == "__main__":
    _self_check()
