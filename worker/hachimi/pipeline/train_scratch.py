"""Train Marian zh→vi TỪ SỐ 0 (v7) — kiến trúc bất đối xứng cho CPU, xuất thẳng CT2.

Đọc `docs/train-scratch-v7.md` trước. Tóm tắt vì sao khác `kaggle_train.py`:
- `kaggle_train.py` **finetune** HachimiMT-60 (nạp trọng số có sẵn). Ở đây dựng `MarianConfig`
  từ đầu, khởi tạo ngẫu nhiên — để thoát prior 350k cặp Gemini (mục 0 của spec).
- Tokenize bằng **sentencepiece thô**, KHÔNG qua `MarianTokenizer`. Lý do: runtime thật
  (`novelworker/translator/hachimi_engine.py`) cũng dùng spm thô + `</s>`; còn `MarianTokenizer`
  bọc thêm `MosesPunctNormalizer` khi máy có `sacremoses` (Kaggle có, máy dev không) → train và
  chạy sẽ tokenize KHÁC NHAU tuỳ máy. Bỏ hẳn nó là hết một lớp bẫy.
- Ngữ cảnh: mỗi dòng corpus mang sẵn `ctx` + `ctx_len` (do `28_build_scratch_corpus.py` bốc).
  `--ctx-mode zero` ép về câu-lẻ cho bậc P0; `corpus` dùng đúng tỉ lệ đã bốc cho P1/P2.

    python train_scratch.py --self-check                    # chạy trọn vòng trên CPU, ~1 phút
    python train_scratch.py --preset tiny --ctx-mode zero \
        --corpus corpus.jsonl --dev dev.jsonl --spm spm24k --output-dir out/p0 --export-ct2

Kiến trúc: `--preset` chọn cấu hình đã chốt, các cờ `--encoder-layers`… đè lên preset.
"""
from __future__ import annotations

import argparse
import inspect
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:  # cùng thư mục, nhưng tên module bắt đầu bằng số nên phải nạp tay khi chạy từ nơi khác
    from kaggle_train import _export_ct2
except ImportError:  # pragma: no cover - chỉ xảy ra khi thiếu file
    _export_ct2 = None

SEP = "⟪ctx⟫"
PAD, BOS, EOS, UNK = 0, 1, 2, 3

# Preset: xem bảng ở docs/train-scratch-v7.md mục 3 và 5.
PRESETS = {
    # Bậc probe — ~15M tham số, cùng cỡ chi-vi/hirashiba-mt-tiny-zh-vi để so có nghĩa.
    "tiny": dict(d_model=256, encoder_layers=6, decoder_layers=1,
                 encoder_attention_heads=4, decoder_attention_heads=4,
                 encoder_ffn_dim=1024, decoder_ffn_dim=1536),
    # Bậc probe P2 — dồn ngân sách encoder từ RỘNG sang SÂU, giữ số tham số xấp xỉ "tiny"
    # (12,2M vs 12,8M): 6×ffn1024 → 9×ffn640. Có param-matched thì mới đo được "sâu có hơn
    # rộng không", chứ không phải "to hơn thì hơn".
    "tiny-deep": dict(d_model=256, encoder_layers=9, decoder_layers=1,
                      encoder_attention_heads=4, decoder_attention_heads=4,
                      encoder_ffn_dim=640, decoder_ffn_dim=1536),
    # Bản gốc HachimiMT-60, giữ để so cùng data.
    "base": dict(d_model=512, encoder_layers=8, decoder_layers=2,
                 encoder_attention_heads=8, decoder_attention_heads=8,
                 encoder_ffn_dim=3072, decoder_ffn_dim=3072),
    # Bản thật v7 — theo Kasai et al. ICLR 2021 (arXiv 2006.10369), đo trên WMT17 EN<->ZH:
    # 12 enc / 1 dec mất 0,35 BLEU so với 6-6 nhưng decode nhanh 2,7-2,9x, chiều ZH->EN còn
    # nhỉnh hơn (24,22 vs 24,19). Với beam=6 x nbest=6 trên CPU 4 luồng thì decoder là chỗ
    # đắt nhất, nên 1 layer là lựa chọn đúng. ffn 2048 CẢ HAI phía (transformer-base chuẩn,
    # đúng cấu hình họ dùng) — HachimiMT-60 để 3072 là to hơn chuẩn.
    # ~54M tham số: NHỎ hơn HachimiMT-60 (56,4M) mà encoder sâu hơn và decode rẻ một nửa.
    "v7": dict(d_model=512, encoder_layers=12, decoder_layers=2,
               encoder_attention_heads=8, decoder_attention_heads=8,
               encoder_ffn_dim=2048, decoder_ffn_dim=2048),
    # Biến thể TỐC ĐỘ, để dành thí nghiệm SAU khi đã có chất lượng. Kasai đo 12-1 mất 0,35
    # BLEU đổi lấy 2,7x tốc độ — nhưng đo trên EN<->ZH, KHÔNG có bài nào kiểm cho zh->vi
    # (tài liệu zh-vi toàn bối cảnh 300k cặp, model 2 layer). Ta đang thiếu chất lượng chứ
    # không thiếu tốc độ, nên đừng cược cái chưa kiểm để lấy cái chưa cần.
    "v7-fast": dict(d_model=512, encoder_layers=12, decoder_layers=1,
                    encoder_attention_heads=8, decoder_attention_heads=8,
                    encoder_ffn_dim=2048, decoder_ffn_dim=2048),
}


def render_source(row: dict, ctx_mode: str) -> str:
    """Ghép `ctx ⟪ctx⟫ câu` — phải khớp HỆT `hachimi_engine._with_context` lúc chạy thật."""
    if ctx_mode == "zero":
        return row["zh"]
    ctx = [c for c in (row.get("ctx") or []) if c]
    if ctx_mode == "corpus":
        ctx = ctx[-int(row.get("ctx_len") or 0):] if row.get("ctx_len") else []
    return SEP.join([*ctx, row["zh"]]) if ctx else row["zh"]


def iter_rows(path: Path, limit: int | None = None):
    """Đọc jsonl theo dòng. KHÔNG gom cả file vào list — 2M dict tốn ~1GB mỗi tiến trình, mà
    DDP chạy 2 tiến trình trên máy Kaggle 13GB RAM."""
    count = 0
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            yield json.loads(line)
            count += 1
            if limit and count >= limit:
                return


class PackedDataset:
    """Giữ id đã tokenize trong mảng numpy phẳng + offset, nạp theo LÔ.

    Danh sách Python 2M × ~85 token tốn ~5GB — mảng int32 phẳng chỉ ~700MB, và nạp theo lô thì
    đỉnh bộ nhớ chỉ bằng một lô. Đây là lý do không dùng `datasets.Dataset` cho vòng này.
    """

    def __init__(self):
        self._src_chunks: list = []
        self._tgt_chunks: list = []
        self._src_lens: list = []
        self._tgt_lens: list = []
        self.src_flat = self.tgt_flat = self.src_off = self.tgt_off = None

    def extend(self, sources: list[list[int]], targets: list[list[int]]) -> None:
        import numpy as np

        for seqs, chunks, lens in ((sources, self._src_chunks, self._src_lens),
                                   (targets, self._tgt_chunks, self._tgt_lens)):
            lens.append(np.fromiter((len(s) for s in seqs), dtype=np.int64, count=len(seqs)))
            flat = np.empty(int(lens[-1].sum()), dtype=np.int32)
            at = 0
            for seq in seqs:
                flat[at:at + len(seq)] = seq
                at += len(seq)
            chunks.append(flat)

    def finalize(self) -> PackedDataset:
        import numpy as np

        def join(chunks, lens):
            flat = np.concatenate(chunks) if chunks else np.empty(0, dtype=np.int32)
            sizes = np.concatenate(lens) if lens else np.empty(0, dtype=np.int64)
            offsets = np.zeros(len(sizes) + 1, dtype=np.int64)
            np.cumsum(sizes, out=offsets[1:])
            return flat, offsets

        self.src_flat, self.src_off = join(self._src_chunks, self._src_lens)
        self.tgt_flat, self.tgt_off = join(self._tgt_chunks, self._tgt_lens)
        self._src_chunks = self._tgt_chunks = self._src_lens = self._tgt_lens = []
        return self

    def __len__(self) -> int:
        return len(self.src_off) - 1

    def __getitem__(self, index: int) -> dict:
        return {
            "input_ids": self.src_flat[self.src_off[index]:self.src_off[index + 1]].tolist(),
            "labels": self.tgt_flat[self.tgt_off[index]:self.tgt_off[index + 1]].tolist(),
        }


def pack_stream(processor, rows, ctx_mode: str, max_source: int, max_target: int,
                batch: int = 50_000) -> tuple[PackedDataset, set[str], int]:
    """Tokenize theo lô rồi nhả rows đi ngay; trả kèm tập tên truyện để kiểm rò."""
    data, novels, total, buffer = PackedDataset(), set(), 0, []
    for row in rows:
        buffer.append(row)
        if len(buffer) >= batch:
            data.extend(*encode_rows(processor, buffer, ctx_mode, max_source, max_target))
            novels.update(r.get("novel") for r in buffer)
            total += len(buffer)
            buffer = []
    if buffer:
        data.extend(*encode_rows(processor, buffer, ctx_mode, max_source, max_target))
        novels.update(r.get("novel") for r in buffer)
        total += len(buffer)
    return data.finalize(), novels - {None}, total


class Collator:
    """Đệm thủ công: nguồn đệm `<pad>`, nhãn đệm -100, decoder_input dịch phải bằng `<pad>`."""

    def __init__(self, pad_id: int = PAD):
        self.pad_id = pad_id

    def __call__(self, features: list[dict]) -> dict:
        import torch

        src_len = max(len(f["input_ids"]) for f in features)
        tgt_len = max(len(f["labels"]) for f in features)
        input_ids, attention, labels, decoder_input = [], [], [], []
        for feature in features:
            source, target = feature["input_ids"], feature["labels"]
            pad_src = src_len - len(source)
            input_ids.append(source + [self.pad_id] * pad_src)
            attention.append([1] * len(source) + [0] * pad_src)
            pad_tgt = tgt_len - len(target)
            labels.append(target + [-100] * pad_tgt)
            shifted = [self.pad_id, *target[:-1]]
            decoder_input.append(shifted + [self.pad_id] * pad_tgt)
        return {
            "input_ids": torch.tensor(input_ids, dtype=torch.long),
            "attention_mask": torch.tensor(attention, dtype=torch.long),
            "decoder_input_ids": torch.tensor(decoder_input, dtype=torch.long),
            "labels": torch.tensor(labels, dtype=torch.long),
        }


def encode_rows(processor, rows: list[dict], ctx_mode: str,
                max_source: int, max_target: int) -> tuple[list[list[int]], list[list[int]]]:
    """spm thô + `</s>` cuối cho NGUỒN; đích thêm `<s>` ở ĐẦU (xem chú thích dưới).

    Vì sao đích phải có `<s>` mở đầu — đo 30/08, đây là chỗ đắt nhất của cả vòng:

    CTranslate2 khởi động decoder từ **vector 0** (`start_from_zero_embedding`), nên nếu train
    bằng `decoder_input = [<pad>, y0, y1…]` thì phải ép embedding `<pad>` về 0 cho khớp. Nhưng
    ép về 0 là **lấy mất tín hiệu duy nhất decoder có ở vị trí 0** — đo teacher-forcing trên
    60 câu đã train:

        pad ngẫu nhiên (lệch CT2) : đúng vị trí 0  67%   · vị trí 1-5  72%
        pad = 0        (khớp CT2) : đúng vị trí 0  28%   · vị trí 1-5  72%

    Hai đường đều hỏng: một đằng lệch train/chạy (61% câu mất chữ hoa đầu), một đằng model
    không học nổi token đầu.

    Lối ra: đích = `<s> y0 y1 … </s>`. Khi đó `decoder_input = [<pad>(=0), <s>, y0 …]` —
    vị trí 0 chỉ phải đoán `<s>` (luôn cố định, dễ), còn y0 được đoán ở vị trí 1 với đầu vào là
    **embedding `<s>` HỌC ĐƯỢC**. Vừa khớp CT2 vừa trả lại tín hiệu khởi đầu.

    ⚠ Bản dịch trả về sẽ mở đầu bằng `<s>` — phải lọc bỏ lúc giải mã (kernel + `hachimi_engine`).
    """
    sources = processor.encode([render_source(row, ctx_mode) for row in rows])
    targets = processor.encode([row["vi"] for row in rows])
    # Cắt CUỐI nguồn thì mất câu hiện tại (nó nằm sau ctx) → cắt ĐẦU, giữ câu phải dịch.
    sources = [seq[-(max_source - 1):] + [EOS] for seq in sources]
    targets = [[BOS] + seq[:max_target - 2] + [EOS] for seq in targets]
    return sources, targets


def _zero_pad_embedding(model) -> None:
    """Ép hàng embedding của `<pad>` về 0 — BẮT BUỘC, không phải làm cho đẹp.

    Đo 30/08, mất nửa ngày mới truy ra: HF train với decoder_input[0] = `<pad>`, tức decoder
    khởi động từ **embedding của `<pad>`**. Nhưng CTranslate2 (bộ chuyển Marian) khởi động
    decoder từ **vector 0** — chú thích ngay trong `ct2.converters.transformers.MarianMTLoader`:
    *"The decoder start token can be any token because the decoder always starts from a zero
    embedding."*

    Hàng `<pad>` KHÔNG bao giờ nhận gradient (`padding_idx`), nên nó nằm nguyên ở giá trị khởi
    tạo NGẪU NHIÊN (đo được norm 0,286). Train thì khởi động từ vector ngẫu nhiên đó, chạy thật
    lại khởi động từ 0 ⇒ **lệch ngay bước decode đầu tiên**. Hậu quả đo trên probe: **61% câu
    mất chữ hoa đầu hoặc rụng nguyên từ đầu tiên** (`Thanh niên…` → `thanh niên…`,
    `Vậy tốt,…` → `tốt,…`), dù bản dịch phần sau vẫn đúng.

    Chứng minh: ép hàng này về 0 rồi chạy HF thì HF hỏng Y HỆT CT2 (trùng khớp 8/25 → 16/25).

    Ép về 0 một lần lúc khởi tạo là đủ — không có gradient thì nó nằm yên. Vẫn ép lại lần nữa
    trước khi lưu cho chắc.

    (Model production v6 KHÔNG dính lỗi này — đã đối chiếu HF vs CT2 trên 40 câu, chỉ khác vài
    từ giữa câu do lượng tử int8.)
    """
    import torch

    shared = getattr(getattr(model, "model", None), "shared", None)
    if shared is None:
        raise SystemExit("Không tìm thấy model.model.shared — kiểm lại phiên bản transformers")
    with torch.no_grad():
        shared.weight[PAD].zero_()


def build_config(args, vocab_size: int):
    from transformers import MarianConfig

    shape = dict(PRESETS[args.preset])
    for key in list(shape):
        override = getattr(args, key, None)
        if override:
            shape[key] = override
    return MarianConfig(
        vocab_size=vocab_size,
        decoder_vocab_size=vocab_size,
        share_encoder_decoder_embeddings=True,
        max_position_embeddings=args.max_position,
        activation_function="swish",
        dropout=args.dropout,
        attention_dropout=0.1,
        pad_token_id=PAD,
        bos_token_id=BOS,
        eos_token_id=EOS,
        decoder_start_token_id=PAD,
        scale_embedding=True,
        **shape,
    )


def _train(args) -> None:
    import sentencepiece as spm
    import torch
    from transformers import MarianMTModel, Seq2SeqTrainer, Seq2SeqTrainingArguments

    processor = spm.SentencePieceProcessor()
    processor.load(str(args.spm / "source.spm"))
    vocab_size = json.loads((args.spm / "vocab.json").read_text(encoding="utf-8"))
    vocab_size = len(vocab_size)
    if processor.get_piece_size() != vocab_size:
        raise SystemExit(f"spm {processor.get_piece_size()} lệch vocab.json {vocab_size}")

    train_data, train_novels, n_train = pack_stream(
        processor, iter_rows(args.corpus, args.limit), args.ctx_mode,
        args.max_source, args.max_target)
    dev_data, dev_novels, n_dev = pack_stream(
        processor, iter_rows(args.dev, args.dev_limit), args.ctx_mode,
        args.max_source, args.max_target)
    leaked = train_novels & dev_novels
    if leaked:
        raise SystemExit(f"Rò truyện giữa train và dev: {sorted(leaked)[:5]}")
    print(f"train {n_train:,} cặp / {len(train_novels)} truyện · dev {n_dev:,} cặp", flush=True)
    config = build_config(args, vocab_size)
    model = MarianMTModel(config)
    params = sum(p.numel() for p in model.parameters())
    print(f"Model từ số 0: {params/1e6:.1f}M tham số · vocab {vocab_size} · "
          f"{config.encoder_layers} enc / {config.decoder_layers} dec · d_model {config.d_model}",
          flush=True)
    _zero_pad_embedding(model)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    options = {
        "output_dir": str(args.output_dir),
        "learning_rate": args.lr,
        "num_train_epochs": args.epochs,
        "per_device_train_batch_size": args.per_device_batch,
        "per_device_eval_batch_size": args.per_device_batch,
        "gradient_accumulation_steps": args.grad_accum,
        "fp16": torch.cuda.is_available(),
        "warmup_steps": args.warmup_steps,
        "weight_decay": 0.01,
        "lr_scheduler_type": "inverse_sqrt",
        "label_smoothing_factor": args.label_smoothing,
        "max_grad_norm": 1.0,
        "eval_steps": args.eval_steps,
        "save_strategy": "steps",
        "save_steps": args.save_steps,
        "save_total_limit": 2,
        "logging_steps": args.logging_steps,
        "report_to": "none",
        "seed": args.seed,
        "dataloader_num_workers": 2 if torch.cuda.is_available() else 0,
        "ddp_find_unused_parameters": False,
    }
    strategy_key = ("eval_strategy"
                    if "eval_strategy" in inspect.signature(Seq2SeqTrainingArguments).parameters
                    else "evaluation_strategy")
    options[strategy_key] = "steps"
    trainer = Seq2SeqTrainer(
        model=model,
        args=Seq2SeqTrainingArguments(**options),
        train_dataset=train_data,
        eval_dataset=dev_data,
        data_collator=Collator(),
    )
    trainer.train(resume_from_checkpoint=str(args.resume) if args.resume else None)
    _zero_pad_embedding(trainer.model)     # bảo hiểm: xem chú thích ở `_zero_pad_embedding`
    trainer.save_model(str(args.output_dir))
    trainer.accelerator.wait_for_everyone()
    if not trainer.is_world_process_zero():
        return

    for name in ("source.spm", "target.spm", "vocab.json", "tokenizer_config.json"):
        shutil.copy2(args.spm / name, args.output_dir / name)
    (args.output_dir / "training_mix.json").write_text(json.dumps({
        "preset": args.preset, "ctx_mode": args.ctx_mode, "params_m": round(params / 1e6, 2),
        "vocab_size": vocab_size, "train_rows": n_train, "dev_rows": n_dev,
        "train_novels": len(train_novels),
        "epochs": args.epochs, "lr": args.lr, "seed": args.seed,
        "effective_batch": args.per_device_batch * args.grad_accum,
        "encoder_layers": config.encoder_layers, "decoder_layers": config.decoder_layers,
        "d_model": config.d_model, "encoder_ffn_dim": config.encoder_ffn_dim,
        "decoder_ffn_dim": config.decoder_ffn_dim,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.export_ct2:
        if _export_ct2 is None:
            raise SystemExit("Không nạp được kaggle_train._export_ct2")
        _export_ct2(args.output_dir)
    print(f"Xong: {args.output_dir}", flush=True)


def _self_check() -> None:
    """Chạy TRỌN vòng trên CPU: nấu spm → train 2 bước → xuất CT2 → dịch thử.

    Bài học `docs/kaggle-cli.md`: môi trường lạ thì lượt đầu để DÒ. Cái này dò sẵn ở nhà, để
    lượt push Kaggle đầu tiên không chết vì một mắt xích vặt.
    """
    import tempfile

    import ctranslate2
    import sentencepiece as spm

    spec = __import__("importlib.util", fromlist=["util"])
    loader = spec.spec_from_file_location("spm_builder", Path(__file__).parent / "29_train_spm.py")
    builder = spec.module_from_spec(loader)
    loader.loader.exec_module(builder)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        rows = [{"zh": f"第{k}章 他走进房间，开口说道：“你来了。”",
                 "ctx": ["天色渐晚。"], "ctx_len": 1, "novel": "A",
                 "vi": f"Chương {k}: Hắn bước vào phòng, mở miệng nói: “Ngươi đến rồi.”"}
                for k in range(200)]
        dev = [dict(row, novel="B") for row in rows[:8]]
        corpus, dev_path = tmp / "corpus.jsonl", tmp / "dev.jsonl"
        for path, data in ((corpus, rows), (dev_path, dev)):
            path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in data),
                            encoding="utf-8")

        spm_dir = tmp / "spm"
        model = builder.train(argparse.Namespace(
            corpus=corpus, out=spm_dir, vocab_size=600, character_coverage=0.9995,
            input_sentences=1000, threads=2, seed=1))
        builder.write_marian_files(model, spm_dir)

        args = argparse.Namespace(
            preset="tiny", ctx_mode="corpus", corpus=corpus, dev=dev_path, spm=spm_dir,
            output_dir=tmp / "out", limit=None, dev_limit=None, max_source=64, max_target=64,
            max_position=128, dropout=0.1, lr=5e-4, epochs=1.0, per_device_batch=4,
            grad_accum=1, warmup_steps=2, label_smoothing=0.1, eval_steps=25, save_steps=1000,
            logging_steps=25, seed=1, resume=None, export_ct2=True,
            d_model=64, encoder_layers=2, decoder_layers=1, encoder_attention_heads=2,
            decoder_attention_heads=2, encoder_ffn_dim=128, decoder_ffn_dim=128)
        _train(args)

        # Hàng <pad> phải bằng 0 sau train, nếu không CT2 sẽ decode lệch bước đầu.
        from safetensors.torch import load_file
        weights = load_file(str(args.output_dir / "model.safetensors"))
        key = next(k for k in weights if k.endswith("shared.weight"))
        assert float(weights[key][PAD].abs().max()) == 0.0, "hàng <pad> chưa được ép về 0"

        ct2_dir = args.output_dir / "ct2-int8_float32"
        assert ct2_dir.is_dir(), "không xuất được CT2"
        translator = ctranslate2.Translator(str(ct2_dir), device="cpu", compute_type="int8")
        processor = spm.SentencePieceProcessor()
        processor.load(str(ct2_dir / "source.spm"))
        source = processor.encode("天色渐晚。" + SEP + "他走进房间。", out_type=str) + ["</s>"]
        result = translator.translate_batch([source], beam_size=2, max_decoding_length=32)
        hyp = result[0].hypotheses[0]
        assert hyp, "CT2 dịch ra rỗng"
        print("dịch thử:", processor.decode([t for t in hyp if t not in ("</s>", "<s>")]))

    # Ghép ngữ cảnh đúng định dạng runtime.
    row = {"zh": "开口说道。", "ctx": ["他走进房间。", "环视四周。"], "ctx_len": 2}
    assert render_source(row, "zero") == "开口说道。"
    assert render_source(row, "corpus") == "他走进房间。⟪ctx⟫环视四周。⟪ctx⟫开口说道。"
    assert render_source(dict(row, ctx_len=1), "corpus") == "环视四周。⟪ctx⟫开口说道。"

    # Đích phải mở đầu bằng <s> và kết bằng </s> — nếu mất, decoder lại không có tín hiệu
    # khởi đầu học được (xem chú thích ở `encode_rows`).
    class _FakeSpm:
        def encode(self, texts):
            return [[10, 11, 12] for _ in texts]
    src_ids, tgt_ids = encode_rows(_FakeSpm(), [{"zh": "a", "vi": "b"}], "zero", 64, 64)
    assert tgt_ids[0][0] == BOS and tgt_ids[0][-1] == EOS, tgt_ids
    assert src_ids[0][-1] == EOS and src_ids[0][0] != BOS, src_ids
    # Cắt ngắn vẫn phải giữ đủ hai đầu.
    _, short = encode_rows(_FakeSpm(), [{"zh": "a", "vi": "b"}], "zero", 64, 3)
    assert short[0] == [BOS, 10, EOS], short
    print("train_scratch OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path)
    ap.add_argument("--dev", type=Path)
    ap.add_argument("--spm", type=Path, help="thư mục có source.spm + vocab.json")
    ap.add_argument("--output-dir", type=Path, default=Path("/kaggle/working/hachimi-v7"))
    ap.add_argument("--preset", choices=sorted(PRESETS), default="v7")
    ap.add_argument("--ctx-mode", choices=("corpus", "zero"), default="corpus",
                    help="zero = ép câu-lẻ (bậc P0); corpus = theo ctx_len đã bốc sẵn")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--dev-limit", type=int, default=2_000)
    ap.add_argument("--max-source", type=int, default=384)
    ap.add_argument("--max-target", type=int, default=192)
    ap.add_argument("--max-position", type=int, default=512)
    ap.add_argument("--dropout", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=5e-4, help="from-scratch cần lr cao hơn finetune 50×")
    ap.add_argument("--epochs", type=float, default=1.0)
    ap.add_argument("--per-device-batch", type=int, default=48)
    ap.add_argument("--grad-accum", type=int, default=2)
    ap.add_argument("--warmup-steps", type=int, default=2_000)
    ap.add_argument("--label-smoothing", type=float, default=0.1)
    ap.add_argument("--eval-steps", type=int, default=1_000)
    ap.add_argument("--save-steps", type=int, default=2_000)
    ap.add_argument("--logging-steps", type=int, default=100)
    ap.add_argument("--seed", type=int, default=20260830)
    ap.add_argument("--resume", type=Path)
    ap.add_argument("--export-ct2", action="store_true")
    ap.add_argument("--self-check", action="store_true")
    for key in ("d_model", "encoder_layers", "decoder_layers", "encoder_attention_heads",
                "decoder_attention_heads", "encoder_ffn_dim", "decoder_ffn_dim"):
        ap.add_argument(f"--{key.replace('_', '-')}", type=int, help="đè lên preset")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return
    for name in ("corpus", "dev", "spm"):
        if not getattr(args, name):
            raise SystemExit(f"Thiếu --{name}")
    _train(args)


if __name__ == "__main__":
    main()
