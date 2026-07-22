"""Engine dịch CT2 (HachimiMT) — thay LLM cho truyện đặt engine 'hachimi'.

Model MT câu→câu (60M): dịch theo TỪNG DÒNG (đoạn), giữ khung xuống dòng của
chương. Nhẹ RAM: tokenize thẳng bằng sentencepiece, KHÔNG cần transformers.
Singleton lazy — nạp CT2 + spm một lần cho mỗi tiến trình worker.
"""
from __future__ import annotations

import threading

from ..config import settings
from .text_clean import clean_source

_EOS = "</s>"
_lock = threading.Lock()
_engine: "_Engine | None" = None


class _Engine:
    def __init__(self, model_dir: str):
        import ctranslate2
        import sentencepiece as spm

        self.translator = ctranslate2.Translator(
            model_dir, device="cpu", compute_type=settings.hachimi_compute_type,
            intra_threads=settings.hachimi_cpu_threads or 0)
        self.src = spm.SentencePieceProcessor()
        self.src.load(f"{model_dir}/source.spm")
        self.tgt = spm.SentencePieceProcessor()
        self.tgt.load(f"{model_dir}/target.spm")

    def translate_lines(self, lines: list[str]) -> list[str]:
        # Marian cần </s> cuối nguồn, nếu thiếu model dịch xong không biết dừng → lặp.
        source = [self.src.encode(line, out_type=str) + [_EOS] for line in lines]
        results = self.translator.translate_batch(
            source, beam_size=settings.hachimi_beam_size,
            max_decoding_length=settings.hachimi_max_len)
        out: list[str] = []
        for res in results:
            tokens = [t for t in res.hypotheses[0] if t != _EOS]
            out.append(self.tgt.decode(tokens))
        return out


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
    print("hachimi_engine OK:\n" + vi)


if __name__ == "__main__":
    _self_check()
