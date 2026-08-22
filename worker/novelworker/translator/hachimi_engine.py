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
# Danh từ chỉ người kiểu convert hiện đại: 男子→"người đàn ông" (nên là "nam tử"), 女人→"người
# phụ nữ". NHẸ hơn lỗi đại từ nên phạt 4 (dưới bịa-chủ-ngữ 6): thà giữ "người đàn ông" còn hơn
# đổi lấy bản bịa chủ ngữ để né nó. Đo 6017 dòng truyện 2163: sửa 6 ca, 0 hồi quy.
_SOFT_MODERN = re.compile(r"(?i)(?<!\w)(?:người đàn ông|người phụ nữ|cô gái|chàng trai)(?!\w)")
_DIGITS = re.compile(r"\d+")
# Danh xưng thân tộc: nguồn có 哥哥 mà đích ra "anh trai" là lệch văn phong cổ.
_KINSHIP = (("哥哥", "anh trai"), ("姐姐", "chị gái"), ("妹妹", "em gái"), ("弟弟", "em trai"))
# Cụm 1-3 từ lặp liền ("ngu ngốc đến mức ngu ngốc", "một một") — tật cố hữu của model nhỏ.
_REPEAT = re.compile(r"(?i)\b([\wÀ-ỹ]+(?:\s+[\wÀ-ỹ]+){0,2})\s+\1\b")
# Model tự BỊA chủ ngữ: nguồn lược chủ ngữ (开口说道：, 低声道：, 当即开怀畅饮。) mà bản dịch
# tự thêm "Hắn/Nàng" vào đầu rồi đoán giới bừa. Đo 45 chương truyện 2163: 104 ca (50 "Hắn",
# 33 "Nàng" sai giới), và 74% số ca ĐÃ có sẵn bản không chèn chủ ngữ trong n-best — chỉ thiếu
# một cổng để chọn nó. Bản đúng theo gu dự án là LƯỢC chủ ngữ ("Mở miệng nói: …").
_LEAD_PRONOUN = re.compile(r"^\s*(?:Hắn|Nàng|Y|Gã|Nó|Ả)(?!\w)")
# Chỉ dò đại từ ở phần LỜI KỂ: 他/她 nằm trong thoại là lời nhân vật nói về người khác, không
# phải chủ ngữ của câu kể (对其她人没有兴趣 / 我要让他…). Bỏ qua bước này thì 3/33 ca lọt.
_ZH_QUOTED = re.compile(r"[“「『\"](.*?)[”」』\"]", re.S)
# 他们/她们 = "bọn họ" (số nhiều), 其他/其她/其它 = "khác" — đều không phải chủ ngữ số ít.
_ZH_NOT_SUBJECT = re.compile(r"[他她它]们|其[他她它]")
_ZH_PRONOUN = re.compile(r"[他她它]")


def _invents_subject(source: str, candidate: str) -> bool:
    """True khi bản dịch mở đầu bằng đại từ ngôi 3 mà lời kể nguồn không có đại từ nào."""
    narration = _ZH_NOT_SUBJECT.sub("", _ZH_QUOTED.sub("", source))
    return bool(_LEAD_PRONOUN.match(candidate) and not _ZH_PRONOUN.search(narration))


# Ép giới đại từ MỞ ĐẦU câu kể: nguồn lời kể mở bằng 他/她 số ít (giới RÕ) mà bản dịch ra
# ngược giới → lỗi user thật sự thấy ("nam mà ra nàng"). Metric gender_wrong trong eval đã đo
# ca này; đây là bản VÁ runtime (không train lại). ponytail: chỉ ép đại từ ĐẦU DÒNG lời kể —
# ca phổ biến + chắc chắn nhất; đại từ giới sai giữa câu không map được an toàn, để prompt/model lo.
_VI_MALE_LEAD = re.compile(r"^(\s*)(?:Hắn|Y|Gã)\b")
_VI_FEMALE_LEAD = re.compile(r"^(\s*)(?:Nàng|Ả)\b")


def _fix_lead_gender(source: str, vi: str) -> str:
    """Vá đại từ mở đầu bản dịch cho khớp giới của 他/她 rõ ở đầu lời kể nguồn.
    _ZH_NOT_SUBJECT đã bỏ 他们/她们/其他 nên chỉ còn ngôi ba SỐ ÍT; thoại bị bỏ để không
    lấy đại từ trong lời nhân vật làm chủ ngữ. Chỉ đổi khi NGƯỢC giới (giữ nguyên nếu đúng)."""
    narr = _ZH_NOT_SUBJECT.sub("", _ZH_QUOTED.sub("", source)).lstrip()
    head = narr[:1]
    if head == "他":  # nam rõ → đích ra Nàng/Ả là sai
        return _VI_FEMALE_LEAD.sub(r"\1Hắn", vi, count=1)
    if head == "她":  # nữ rõ → đích ra Hắn/Y/Gã là sai
        return _VI_MALE_LEAD.sub(r"\1Nàng", vi, count=1)
    return vi


# Ngoặc panel: model hay hạ 【…】 xuống "[… ]" và đổi “…” thành "…". Đo 38 chương mới nhất
# truyện 2163: 96/98 dòng panel vỡ ngoặc, 527 dòng lệch nháy. Đây là KHUNG ký tự chứ không
# phải nghĩa — ép thẳng cho khớp nguồn, đừng bắt model tự đoán.
_PANEL_OPEN = re.compile(r"^\s*[\[【]?\s*")
_PANEL_CLOSE = re.compile(r"\s*[\]】]?\s*$")


def _fix_frame(zh: str, vi: str) -> str:
    if zh.startswith("【") and zh.endswith("】"):
        vi = "【" + _PANEL_CLOSE.sub("", _PANEL_OPEN.sub("", vi)) + "】"
    if "“" in zh and '"' in vi:
        opened = False
        chars: list[str] = []
        for char in vi:
            if char == '"':
                chars.append("”" if opened else "“")
                opened = not opened
            else:
                chars.append(char)
        vi = "".join(chars)
    return vi


def _collapse_repeats(text: str) -> str:
    while (collapsed := _REPEAT.sub(r"\1", text)) != text:
        text = collapsed
    return text


# Nhân đôi ĐOẠN DÀI liền kề ("... A A ..." với A >= 12 ký tự): lỗi decode đo ở
# audit 22/08 — 8/48 chương bị. Gộp về một bản, lặp tới khi ổn định.
_DUP_SPAN = re.compile(r"(.{12,}?)\s*\1")


def _collapse_dup_spans(text: str) -> str:
    prev = None
    while prev != text:
        prev = text
        text = _DUP_SPAN.sub(r"\1", text)
    return text


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
    # Nhân đôi đoạn dài trong cùng giả thuyết: phạt nặng để n-best chọn bản sạch
    # (audit 22/08: 8/48 chương bị — decode không có ràng buộc chống lặp).
    penalty += 8.0 * len(_DUP_SPAN.findall(candidate))
    # 6 điểm: đủ đè nhịp câu (~1) và ngoặc kép (3), nhưng dưới Hán sót/đại từ hiện đại (10)
    # — thà giữ chủ ngữ bịa còn hơn chọn bản lọt chữ Hán.
    penalty += 6.0 * _invents_subject(source, candidate)
    penalty += 4.0 * len(_SOFT_MODERN.findall(candidate))
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
            max_decoding_length=settings.hachimi_max_len,
            max_batch_size=settings.hachimi_max_batch,
            repetition_penalty=settings.hachimi_repetition_penalty,
            no_repeat_ngram_size=settings.hachimi_no_repeat_ngram)
        out: list[str] = []
        for line, res in zip(lines, results):
            best = res.hypotheses[0]
            if nbest > 1:
                best = min(
                    res.hypotheses,
                    key=lambda h: _rank_penalty(line, self.tgt.decode([t for t in h if t != _EOS])),
                )
            tokens = [t for t in best if t != _EOS]
            decoded = _collapse_dup_spans(self.tgt.decode(tokens))
            if len(tokens) < settings.hachimi_max_len and not _HAN.search(decoded):
                out.append(decoded)
                continue
            soft = [m.group(0) for m in _SOFT_END.finditer(line) if m.group(0)]
            parts = (soft if _HAN.search(decoded) and len(soft) > 1 else
                     self._hard_split(line, max(8, len(self.src.encode(line)) // 2)))
            if len(parts) == 1:
                if _HAN.search(decoded):
                    raise RuntimeError("Hachimi còn chữ Hán dù nguồn không thể chia tiếp")
                # Dòng tượng thanh ngắn (咕叽咕叽) làm model lặp tới trần token mà nguồn lại
                # quá ngắn để chia tiếp — chương 158 truyện 2163 chết vĩnh viễn vì đúng ca này.
                # Gom cụm lặp rồi NHẬN: một dòng xấu rẻ hơn nhiều so với mất cả chương.
                out.append(_collapse_repeats(decoded))
                continue
            out.append(_join_translations(self._translate_safe(parts)))
        return out

    def _with_context(self, lines: list[str], i: int) -> str:
        """Ghép tối đa N dòng nguồn phía trước vào dòng i, đúng định dạng train `ctx ⟪ctx⟫ câu`.
        Chỉ lấy dòng có nội dung làm ngữ cảnh; nếu ghép xong vượt trần token thì bỏ ngữ cảnh
        (thà mất ngữ cảnh còn hơn để hard-split xé mất phần câu hiện tại)."""
        n = settings.hachimi_context_lines
        sep = settings.hachimi_context_sep
        prev = [lines[j].strip() for j in range(max(0, i - n), i) if lines[j].strip()]
        if not prev:
            return lines[i]
        joined = sep.join([*prev, lines[i]])
        return joined if len(self.src.encode(joined)) <= settings.hachimi_max_len else lines[i]

    def _translate_context(self, lines: list[str]) -> list[str]:
        """Đường doc-level: nạp `ctx ⟪ctx⟫ câu`, nhưng CHẤM n-best theo CÂU HIỆN TẠI (phần sau
        SEP cuối) — nếu chấm cả ngữ cảnh Trung thì phạt số/ngoặc sẽ lệch vì output chỉ là câu."""
        sep = settings.hachimi_context_sep
        sources = [self._with_context(lines, i) for i in range(len(lines))]
        currents = [s.rsplit(sep, 1)[-1] for s in sources]
        encoded = [self.src.encode(s, out_type=str) + [_EOS] for s in sources]
        results = self.translator.translate_batch(
            encoded, beam_size=self.beam, num_hypotheses=max(1, min(self.nbest, self.beam)),
            max_decoding_length=settings.hachimi_max_len,
            max_batch_size=settings.hachimi_max_batch,
            repetition_penalty=settings.hachimi_repetition_penalty,
            no_repeat_ngram_size=settings.hachimi_no_repeat_ngram)
        out: list[str] = []
        for current, res in zip(currents, results):
            best = min(res.hypotheses,
                       key=lambda h: _rank_penalty(current, self.tgt.decode([t for t in h if t != _EOS])))
            out.append(_collapse_dup_spans(self.tgt.decode([t for t in best if t != _EOS])))
        return out

    def translate_lines(self, lines: list[str]) -> list[str]:
        if settings.hachimi_context_lines > 0:
            out = self._translate_context(lines)
        else:
            groups: list[tuple[int, int]] = []
            pieces: list[str] = []
            for line in lines:
                start = len(pieces)
                pieces.extend(self._split_source(line))
                groups.append((start, len(pieces)))
            translated = self._translate_safe(pieces)
            out = [_join_translations(translated[start:end]) for start, end in groups]
        # source-line ↔ vi-line thẳng hàng ở đây → ép giới đại từ mở đầu và khung ngoặc/nháy
        return [_fix_frame(zh, _fix_lead_gender(zh, vi)) for zh, vi in zip(lines, out)]


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
    # Mã termguard phải sống qua _decap — lấy mã THẬT để đổi họ mã là test biết ngay.
    from .termguard import _ALNUM_CODES
    code = _ALNUM_CODES[1]
    assert _join_translations(["Hắn hỏi,", f"{code} gật đầu."]) == f"Hắn hỏi, {code} gật đầu."
    # Khung ngoặc/nháy phải khớp nguồn, kể cả khi panel có nhãn 【…】 lồng bên trong.
    assert _fix_frame("【叮！】", "[Đinh! ]") == "【Đinh!】"
    assert _fix_frame("【体质：九炎雷体【已激活50％】】",
                      "[Thể chất: Cửu Viêm Lôi Thể 【Đã kích hoạt 50%】]"
                      ) == "【Thể chất: Cửu Viêm Lôi Thể 【Đã kích hoạt 50%】】"
    assert _fix_frame("他说：“走。”", 'Hắn nói: "Đi thôi."') == "Hắn nói: “Đi thôi.”"
    assert _fix_frame("他说：\"走。\"", 'Hắn nói: "Đi thôi."') == 'Hắn nói: "Đi thôi."'
    assert _collapse_repeats("Ục ù ù ù ù ù ù") == "Ục ù"
    dialogue = "“你不会吧？连这都问呀？”他说道！"
    assert _get()._split_source(dialogue) == [dialogue], "không được xé một lượt thoại"
    long_src = "少年握紧手中长剑。" * 30
    assert len(_get()._split_source(long_src)) > 1, "đoạn dài phải được chia nhỏ"
    print("hachimi_engine OK:\n" + vi)


if __name__ == "__main__":
    _self_check()
