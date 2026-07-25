"""Fill review batches with Hachimi's current output as editable draft translations."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from text_clean import clean_source


def _sources(text: str) -> list[str]:
    # Xoá dấu chống crawl trước khi model dịch, khớp với clean lúc train.
    return [clean_source(zh) for zh in re.findall(r"\*\*ZH:\*\*\s*(.+)", text)]


def _replace_drafts(text: str, translations: list[str]) -> str:
    found = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal found
        translation = translations[found].strip()
        found += 1
        return f"**Đề xuất:** {translation}\n\n"

    result = re.sub(r"\*\*Đề xuất:\*\*.*?(?=\n##|\Z)", replace, text, flags=re.S)
    if found != len(translations):
        raise ValueError(f"Chỉ thay {found}/{len(translations)} đề xuất")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("batches", nargs="+", type=Path)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--ct2-dir", default="ct2-int8_float32")
    parser.add_argument("--cpu-threads", type=int, default=2)
    args = parser.parse_args()

    import ctranslate2
    from transformers import AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(args.model_dir)
    translator = ctranslate2.Translator(
        str(args.model_dir / args.ct2_dir),
        device="cpu",
        compute_type="int8_float32",
        intra_threads=args.cpu_threads,
    )
    for batch in args.batches:
        text = batch.read_text(encoding="utf-8")
        sources = _sources(text)
        tokens = [tokenizer.convert_ids_to_tokens(tokenizer(item, truncation=True, max_length=512).input_ids) for item in sources]
        results = translator.translate_batch(tokens, beam_size=4, max_decoding_length=512)
        translations = [
            tokenizer.decode(tokenizer.convert_tokens_to_ids(item.hypotheses[0]), skip_special_tokens=True)
            for item in results
        ]
        batch.write_text(_replace_drafts(text, translations), encoding="utf-8")
        print(f"filled={len(sources)} {batch}")


if __name__ == "__main__":
    main()
