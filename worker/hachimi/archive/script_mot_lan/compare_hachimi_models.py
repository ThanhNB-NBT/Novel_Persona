"""So sánh raw output của checkpoint local và Hachimi gốc trên lỗi truyện 32."""
from pathlib import Path

from novelworker import db
from novelworker.config import settings
from novelworker.translator.hachimi_engine import _Engine
from novelworker.translator.text_clean import clean_source


CASES = [
    (1, 13, "Dì Maria và văn cảm thán"),
    (1, 16, "Maria, Ám Liên và quan hệ nhân vật"),
    (1, 19, "Nguồn tự đổi Maria thành Marilyn"),
    (1, 24, "Một lượt thoại bị tách"),
    (1, 28, "Tả tướng Mordo đến"),
    (1, 33, "Tên hoàng đế có dấu sao"),
    (1, 36, "Ba người nói chuyện, tên có dấu sao"),
    (1, 51, "Dấu gạch chéo rác"),
    (1, 52, "Ngoặc rỗng rác"),
    (2, 6, "耶 bị đọc thành Yah"),
]
MODELS = [
    ("Fine-tune local", "models/hachimi-ct2"),
    ("Hachimi gốc", "models/hachimi-base-download/ct2-int8_float32"),
    ("V-next D", "experiments/hachimi_vnext_d/ct2-int8_float32"),
    ("V-next E", "experiments/hachimi_vnext_e/ct2-int8_float32"),
]


def quote_aware_split(engine: _Engine, text: str) -> list[str]:
    """Giữ nguyên một lượt thoại; chỉ cắt ở dấu kết câu ngoài ngoặc."""
    pairs = {"“": "”", "‘": "’", "「": "」", "『": "』"}
    stack: list[str] = []
    parts: list[str] = []
    start = 0
    pending_end = False
    for index, char in enumerate(text):
        if char in pairs:
            stack.append(pairs[char])
        elif stack and char == stack[-1]:
            stack.pop()
            if not stack and pending_end:
                parts.append(text[start:index + 1])
                start = index + 1
                pending_end = False
                continue
        if char in "。！？!?；;":
            if stack:
                pending_end = True
            else:
                parts.append(text[start:index + 1])
                start = index + 1
    if start < len(text):
        parts.append(text[start:])
    limit = max(64, settings.hachimi_max_len - 20)
    packed: list[str] = []
    current = ""
    for part in parts:
        if current and len(engine.src.encode(current + part)) > limit:
            packed.append(current)
            current = ""
        if len(engine.src.encode(part)) > limit:
            packed.extend(engine._hard_split(part, limit))
        else:
            current += part
    if current:
        packed.append(current)
    return packed


def main() -> None:
    chapters = {
        row["chapter_index"]: (row["content_zh"] or "").splitlines()
        for row in (
            db.sb().table("chapters").select("chapter_index,content_zh")
            .eq("novel_id", 32).in_("chapter_index", [1, 2]).execute().data or []
        )
    }
    sources = [clean_source(chapters[chapter][line - 1]) for chapter, line, _ in CASES]
    translated = {}
    single_pass = {}
    quote_aware = {}
    for name, path in MODELS:
        engine = _Engine(path)
        translated[name] = engine.translate_lines(sources)
        single_pass[name] = engine._translate_safe(sources)
        quote_aware[name] = engine._translate_safe([
            piece
            for source in sources
            for piece in quote_aware_split(engine, source)
        ])
        # Ghép lại theo từng nguồn sau khi đã dịch các mảnh.
        cursor = 0
        grouped = []
        for source in sources:
            count = len(quote_aware_split(engine, source))
            grouped.append(" ".join(quote_aware[name][cursor:cursor + count]))
            cursor += count
        quote_aware[name] = grouped
    out = ["# Hachimi gốc so với fine-tune — truyện 32", "",
           "Đây là raw output CT2, chưa qua termguard hay hậu xử lý.", ""]
    for index, ((chapter, line, label), source) in enumerate(zip(CASES, sources)):
        out += [
            f"## {label}",
            f"- Vị trí nguồn: chương {chapter}, dòng {line}",
            f"- ZH: {source}",
        ]
        for name, _ in MODELS:
            out += [
                f"- {name} (đang chia câu): {translated[name][index]}",
                f"- {name} (một lượt): {single_pass[name][index]}",
                f"- {name} (giữ lượt thoại): {quote_aware[name][index]}",
            ]
        out.append("")
    target = Path("experiments/hachimi_base_vs_finetune_vnext_e.md")
    target.write_text("\n".join(out), encoding="utf-8")
    print(f"Đã ghi {target}")


if __name__ == "__main__":
    main()
