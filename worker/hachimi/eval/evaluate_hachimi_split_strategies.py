"""Các chiến lược chia nguồn khác nhau cho engine Hachimi (dùng bởi harness so nhịp câu).

`current` = đúng cách production đang cắt (90 token); `packed160` gom mệnh đề; `direct448*`
đưa trọn câu dài cho model. Kết luận đo được: nới đơn vị KHÔNG làm model ngắt câu thêm —
xem docs/hachimi_rhythm_research.md.
"""
from __future__ import annotations

import re
from pathlib import Path

from novelworker.config import settings
from novelworker.translator.hachimi_engine import _EOS, _HAN, _Engine, _join_translations
from novelworker.translator.text_clean import clean_source

from eval_common import MODELS_DIR


CURRENT = MODELS_DIR / "hachimi-ct2"
SOFT_END = re.compile(r".+?(?:[，,、：:]+|$)")


class StrategyEngine:
    def __init__(self, model_dir: Path, mode: str):
        self.engine = _Engine(str(model_dir))
        self.mode = mode

    def _packed(self, line: str, limit: int) -> list[str]:
        clauses = [match.group(0) for match in SOFT_END.finditer(line) if match.group(0)]
        pieces: list[str] = []
        current = ""
        for clause in clauses or [line]:
            for part in self.engine._hard_split(clause, limit):
                if current and len(self.engine.src.encode(current + part)) > limit:
                    pieces.append(current)
                    current = ""
                current += part
        if current:
            pieces.append(current)
        return pieces

    def translate_lines(self, lines: list[str]) -> list[str]:
        if self.mode == "current":
            return self.engine.translate_lines(lines)
        groups: list[tuple[int, int]] = []
        pieces: list[str] = []
        limit = 160 if self.mode == "packed160" else 448
        for line in lines:
            start = len(pieces)
            if self.mode == "direct448" and len(self.engine.src.encode(line)) <= limit:
                pieces.append(line)
            else:
                pieces.extend(self._packed(line, limit))
            groups.append((start, len(pieces)))
        if self.mode == "direct448out448":
            source = [self.engine.src.encode(piece, out_type=str) + [_EOS] for piece in pieces]
            results = self.engine.translator.translate_batch(
                source,
                beam_size=settings.hachimi_beam_size,
                max_decoding_length=448,
            )
            translated = []
            for piece, result in zip(pieces, results):
                tokens = [token for token in result.hypotheses[0] if token != _EOS]
                decoded = self.engine.tgt.decode(tokens)
                translated.append(
                    decoded
                    if len(tokens) < 448 and not _HAN.search(decoded)
                    else _join_translations(
                        self.engine._translate_safe(self._packed(piece, 160))
                    )
                )
        else:
            translated = self.engine._translate_safe(pieces)
        return [_join_translations(translated[start:end]) for start, end in groups]
