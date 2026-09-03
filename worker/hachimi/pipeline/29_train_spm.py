"""Nấu SentencePiece joint zh+vi cho v7 + dựng đủ file MarianTokenizer.

Vì sao (docs/train-scratch-v7.md mục 2.2): SPM 24k hiện tại fit trên 350k cặp teacher Gemini —
không phải văn của dự án. Fit lại trên chính corpus v7 cho **ít token hơn cùng một câu** ⇒ vừa
nhanh hơn lúc decode vừa dịch tốt hơn, không tốn một tham số nào.

Nhân bản đúng quy ước của HachimiMT-60 (đã soi bằng `vocab.json` + `tokenizer_config.json` của
v6): joint (source.spm == target.spm), byte_fallback, id cố định
`<pad>=0 <s>=1 </s>=2 <unk>=3`, `vocab.json` = piece → id lấy thẳng thứ tự của spm.

Khác một điểm có chủ ý: khai `⟪ctx⟫` là **user_defined_symbol** để nó thành một piece nguyên
khối. `16_make_doclevel.py` từng ghi "SPM tự học SEP, khỏi thêm special token" — đúng khi phải
dùng lại vocab người khác; lần này tự nấu nên khai thẳng, khỏi phó mặc BPE.

    python 29_train_spm.py --corpus ~/hachimi-work/scratch/corpus.jsonl \
        --out ~/hachimi-work/scratch/spm24k --vocab-size 24000
    python 29_train_spm.py --self-check

Đo `fertility` (token / ký tự nguồn) và so với SPM cũ — đây là số quyết định 24k hay 32k:
32k chỉ đáng nếu câu ngắn đi đủ bù ~33% chi phí lớp chiếu output mỗi bước decode.
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

SEP = "⟪ctx⟫"
SPECIALS = {"pad_id": 0, "bos_id": 1, "eos_id": 2, "unk_id": 3}
TOKENIZER_CONFIG = {
    "backend": "custom",
    "bos_token": "<s>",
    "clean_up_tokenization_spaces": False,
    "eos_token": "</s>",
    "is_local": True,
    "model_max_length": 512,
    "pad_token": "<pad>",
    "separate_vocabs": False,
    "source_lang": None,
    "sp_model_kwargs": {},
    "target_lang": None,
    "tokenizer_class": "MarianTokenizer",
    "unk_token": "<unk>",
}


def sentence_iter(corpus: Path, cap: int, seed: int):
    """Đọc jsonl, nhả xen kẽ zh và vi để BPE không lệch hẳn về một ngôn ngữ.

    Lấy mẫu theo xác suất cố định thay vì giữ cả corpus trong RAM (2M dòng × 2 câu).
    """
    rng = random.Random(seed)
    emitted = 0
    with corpus.open(encoding="utf-8") as handle:
        for line in handle:
            if emitted >= cap:
                return
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            for text in (row.get("zh"), row.get("vi")):
                if text and emitted < cap:
                    yield text
                    emitted += 1
            # Cho SPM thấy dạng đã ghép ngữ cảnh ở một phần nhỏ, để SEP có ngữ cảnh thật.
            ctx = row.get("ctx") or []
            if ctx and emitted < cap and rng.random() < 0.15:
                yield SEP.join([*ctx, row["zh"]])
                emitted += 1


def train(args) -> Path:
    import sentencepiece as spm

    args.out.mkdir(parents=True, exist_ok=True)
    prefix = args.out / "spm"
    spm.SentencePieceTrainer.train(
        sentence_iterator=sentence_iter(args.corpus, args.input_sentences, args.seed),
        model_prefix=str(prefix),
        model_type="bpe",
        vocab_size=args.vocab_size,
        character_coverage=args.character_coverage,
        byte_fallback=True,
        user_defined_symbols=[SEP],
        normalization_rule_name="nmt_nfkc",
        shuffle_input_sentence=True,
        input_sentence_size=args.input_sentences,
        num_threads=args.threads,
        train_extremely_large_corpus=False,
        **SPECIALS,
    )
    return Path(str(prefix) + ".model")


def write_marian_files(spm_model: Path, out: Path) -> int:
    """Nhân `spm.model` thành source.spm/target.spm + vocab.json + tokenizer_config.json."""
    import sentencepiece as spm

    processor = spm.SentencePieceProcessor()
    processor.load(str(spm_model))
    vocab = {processor.id_to_piece(i): i for i in range(processor.get_piece_size())}
    if len(vocab) != processor.get_piece_size():
        raise SystemExit("SPM sinh piece trùng tên — vocab.json sẽ lệch id, dừng")
    for token, index in (("<pad>", 0), ("<s>", 1), ("</s>", 2), ("<unk>", 3)):
        if vocab.get(token) != index:
            raise SystemExit(f"{token} phải mang id {index}, đang là {vocab.get(token)}")
    if SEP not in vocab:
        raise SystemExit(f"{SEP} không nằm trong vocab — kiểm user_defined_symbols")

    for name in ("source.spm", "target.spm"):
        (out / name).write_bytes(spm_model.read_bytes())
    (out / "vocab.json").write_text(json.dumps(vocab, ensure_ascii=False, indent=2), encoding="utf-8")
    (out / "tokenizer_config.json").write_text(
        json.dumps(TOKENIZER_CONFIG, ensure_ascii=False, indent=2), encoding="utf-8")
    return len(vocab)


def fertility(spm_model: Path, samples: list[str]) -> dict:
    """token / ký tự nguồn — thấp hơn là tốt hơn (câu ngắn ⇒ ít bước decode)."""
    import sentencepiece as spm

    processor = spm.SentencePieceProcessor()
    processor.load(str(spm_model))
    tokens = sum(len(processor.encode(text)) for text in samples)
    chars = sum(len(text) for text in samples) or 1
    return {"tokens": tokens, "chars": chars, "tokens_per_char": round(tokens / chars, 4),
            "tokens_per_sentence": round(tokens / max(1, len(samples)), 2)}


def _read_samples(corpus: Path, field: str, count: int) -> list[str]:
    out: list[str] = []
    with corpus.open(encoding="utf-8") as handle:
        for line in handle:
            if len(out) >= count:
                break
            line = line.strip()
            if not line:
                continue
            try:
                text = json.loads(line).get(field)
            except json.JSONDecodeError:
                continue
            if text:
                out.append(text)
    return out


def _self_check() -> None:
    import tempfile

    import sentencepiece as spm

    rows = []
    for k in range(400):
        rows.append({"zh": f"第{k}章 他走进房间，开口说道：“你来了。”", "ctx": ["他走进房间。"],
                     "vi": f"Chương {k}: Hắn bước vào phòng, mở miệng nói: “Ngươi đến rồi.”"})
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        corpus = tmp / "corpus.jsonl"
        corpus.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
        args = argparse.Namespace(corpus=corpus, out=tmp / "spm", vocab_size=600,
                                  character_coverage=0.9995, input_sentences=2000,
                                  threads=2, seed=1)
        model = train(args)
        size = write_marian_files(model, args.out)
        assert size == 600, size
        processor = spm.SentencePieceProcessor()
        processor.load(str(model))
        # SEP phải là MỘT piece, không bị BPE xé. (SPM luôn thêm "▁" đầu chuỗi — kệ nó.)
        pieces = [p for p in processor.encode(SEP, out_type=str) if p != "▁"]
        assert pieces == [SEP], pieces
        # Ghép ngữ cảnh vẫn tách được câu hiện tại ở phía sau SEP.
        joined = processor.encode("他走进房间。" + SEP + "开口说道。", out_type=str)
        assert SEP in joined, joined
        vocab = json.loads((args.out / "vocab.json").read_text(encoding="utf-8"))
        assert vocab["<pad>"] == 0 and vocab["</s>"] == 2 and vocab["<unk>"] == 3
        assert (args.out / "source.spm").read_bytes() == (args.out / "target.spm").read_bytes()
        stats = fertility(model, [r["zh"] for r in rows[:50]])
        assert stats["tokens_per_char"] > 0
    print("29_train_spm OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, default=Path.home() / "hachimi-work/scratch/corpus.jsonl")
    ap.add_argument("--out", type=Path, default=Path.home() / "hachimi-work/scratch/spm24k")
    ap.add_argument("--vocab-size", type=int, default=24_000)
    ap.add_argument("--character-coverage", type=float, default=0.9995)
    ap.add_argument("--input-sentences", type=int, default=2_000_000)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--seed", type=int, default=20260830)
    ap.add_argument("--compare", type=Path, default=None, help="spm cũ để so fertility")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return

    model = train(args)
    size = write_marian_files(model, args.out)
    print(f"vocab {size} · {args.out}")

    samples_zh = _read_samples(args.corpus, "zh", 5_000)
    samples_vi = _read_samples(args.corpus, "vi", 5_000)
    report = {"vocab_size": size,
              "new_zh": fertility(model, samples_zh), "new_vi": fertility(model, samples_vi)}
    if args.compare:
        report["old_zh"] = fertility(args.compare, samples_zh)
        report["old_vi"] = fertility(args.compare, samples_vi)
        for lang in ("zh", "vi"):
            old = report[f"old_{lang}"]["tokens_per_sentence"]
            new = report[f"new_{lang}"]["tokens_per_sentence"]
            report[f"delta_{lang}_pct"] = round((new - old) / max(1e-9, old) * 100, 1)
    (args.out / "fertility.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
