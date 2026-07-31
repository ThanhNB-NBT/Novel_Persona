"""Chấm một model CT2 bất kỳ trên bộ test lỗi xưng hô — dùng cho Bậc 1 (đấu loại base).

Mọi chỉ số ở đây REF-FREE (so output với NGUỒN, không cần bản mẫu vàng), nên bộ test chạy được
ngay mà không phải chấm tay. Chỉ số cốt lõi là **tỉ lệ bịa chủ ngữ** — lỗi chính đã đo (nguồn
lược chủ ngữ mà model tự thêm "Hắn/Nàng" rồi đoán giới bừa).

    python eval_register.py                                   # model production, bộ test mặc định
    python eval_register.py <duong_dan_ct2>                   # model khác (vd HachimiMT-60-QT export CT2)
    python eval_register.py <ct2> --testset eval/testset_multi.jsonl
    python eval_register.py --self-check

Bậc 1 = chạy lệnh này cho từng ứng viên rồi so bảng. Con nào ÍT bịa chủ ngữ + ít lỗi giới nhất
mà tốc độ chấp nhận được thì thành base cho mọi vòng train sau.
"""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from novelworker.translator import hachimi_engine as H  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_TESTSET = HERE / "testset_2163_45ch.jsonl"
DEFAULT_MODEL = HERE.parents[1] / "models" / "hachimi-ct2"

_Q = re.compile(r"[“「『\"](.*?)[”」』\"]", re.S)
_LEAD_VI = re.compile(r"^\s*(?:Hắn|Nàng|Y|Gã|Nó|Ả)(?!\w)")
_LEADF_ZH = re.compile(r"^\s*她(?!们)")
_LEADM_ZH = re.compile(r"^\s*他(?!们)")
_VF = re.compile(r"^\s*Nàng\b")
_VM = re.compile(r"^\s*Hắn\b")


def _narr_zh(zh: str) -> str:
    return H._ZH_NOT_SUBJECT.sub("", _Q.sub("", zh))


def _make_codec(model_dir: str):
    """Trả (encode(str)->tokens, decode(tokens)->str, eos). Nhận cả model dùng SentencePiece
    (source.spm/target.spm) lẫn model dùng HF tokenizer.json (hirashiba-medium)."""
    if (Path(model_dir) / "source.spm").is_file():
        import sentencepiece as spm
        sp = spm.SentencePieceProcessor(); sp.load(model_dir + "/source.spm")
        tp = spm.SentencePieceProcessor(); tp.load(model_dir + "/target.spm")
        return (lambda s: sp.encode(s, out_type=str)), (lambda t: tp.decode(t)), "</s>"
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(model_dir)
    eos = tok.eos_token or "</s>"
    enc = lambda s: tok.convert_ids_to_tokens(tok(s).input_ids)
    dec = lambda t: tok.decode(tok.convert_tokens_to_ids(t), skip_special_tokens=True)
    return enc, dec, eos


def _build_units(testset: Path, context: int) -> list[tuple[str, str]]:
    """Trả (nguồn_nạp_vào_model, câu_hiện_tại_để_chấm). context=0: hai cái bằng nhau.
    context>0: ghép N dòng nguồn trước + ⟪ctx⟫ (đúng cách model doc-level được train/chạy)."""
    sep = "⟪ctx⟫"
    units: list[tuple[str, str]] = []
    for row in map(json.loads, testset.read_text(encoding="utf-8").splitlines()):
        lines = [l for l in row["zh_lines"] if l.strip()]
        for i, cur in enumerate(lines):
            if context <= 0:
                units.append((cur, cur))
            else:
                prev = lines[max(0, i - context):i]
                units.append((sep.join([*prev, cur]) if prev else cur, cur))
    return units


def score_model(model_dir: str, testset: Path = DEFAULT_TESTSET, context: int = 0) -> dict:
    import ctranslate2

    tr = ctranslate2.Translator(model_dir, device="cpu", compute_type="int8")
    encode, decode, eos = _make_codec(model_dir)

    units = _build_units(testset, context)
    m = {k: 0 for k in ("lines", "subj_drop_src", "invented", "gender_src", "gender_wrong",
                         "modern", "soft_modern", "repeat", "han")}
    m["lines"] = len(units)
    t0 = time.time()
    for i in range(0, len(units), 400):
        chunk = units[i:i + 400]
        res = tr.translate_batch([encode(s) + [eos] for s, _ in chunk],
                                 beam_size=6, num_hypotheses=6, max_decoding_length=180)
        for (_, src), r in zip(chunk, res):
            # src = CÂU HIỆN TẠI (không gồm ngữ cảnh) — chấm output theo đúng câu này
            hyps = [decode([t for t in h if t != eos]) for h in r.hypotheses]
            out = min(hyps, key=lambda c: H._rank_penalty(src, c))
            narr = _narr_zh(src).strip()
            # bịa chủ ngữ: nguồn lời kể KHÔNG có đại từ mà output mở đầu bằng đại từ
            if not H._ZH_PRONOUN.search(narr):
                m["subj_drop_src"] += 1
                if _LEAD_VI.match(out):
                    m["invented"] += 1
            # lệch giới: nguồn có 他/她 rõ đầu dòng lời kể
            if _LEADM_ZH.match(narr) or _LEADF_ZH.match(narr):
                m["gender_src"] += 1
                if (_LEADM_ZH.match(narr) and _VF.match(out)) or (_LEADF_ZH.match(narr) and _VM.match(out)):
                    m["gender_wrong"] += 1
            out_narr = _Q.sub("", out)
            m["modern"] += len(H._MODERN_VI.findall(out_narr))
            m["soft_modern"] += len(H._SOFT_MODERN.findall(out_narr))
            m["repeat"] += len(H._REPEAT.findall(out))
            m["han"] += len(H._HAN.findall(out))
    m["sec"] = round(time.time() - t0, 1)
    m["lines_per_sec"] = round(len(units) / (time.time() - t0), 1)
    return m


def _report(name: str, m: dict) -> None:
    inv = f'{m["invented"]}/{m["subj_drop_src"]}'
    g = f'{m["gender_wrong"]}/{m["gender_src"]}'
    print(f"\n== {name}  ({m['lines']} dòng, {m['sec']}s, {m['lines_per_sec']} dòng/s)")
    print(f"   BỊA CHỦ NGỮ (nguồn lược, output thêm) : {inv}  ← chỉ số cốt lõi")
    print(f"   lệch giới (nguồn có 他/她)             : {g}")
    print(f"   đại từ hiện đại lọt                    : {m['modern']}")
    print(f"   'người đàn ông' kiểu convert           : {m['soft_modern']}")
    print(f"   cụm lặp                                : {m['repeat']}")
    print(f"   Hán sót                                : {m['han']}")


def _self_check() -> None:
    assert DEFAULT_TESTSET.is_file(), "thiếu bộ test testset_2163_45ch.jsonl"
    rows = [json.loads(l) for l in DEFAULT_TESTSET.read_text(encoding="utf-8").splitlines()]
    assert len(rows) == 45 and all("zh_lines" in r for r in rows)
    assert not H._ZH_PRONOUN.search(_narr_zh("开口说道：“你来了”"))  # 开口说道 lược CN
    assert H._ZH_PRONOUN.search(_narr_zh("他握紧长枪。"))  # 他 có đại từ
    print("eval_register OK — bộ test 45 chương sẵn sàng")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        _self_check()
    else:
        args = sys.argv[1:]
        testset = DEFAULT_TESTSET
        context = 0
        if "--testset" in args:
            i = args.index("--testset")
            testset = Path(args[i + 1])
            args = args[:i] + args[i + 2:]
        if "--context" in args:
            i = args.index("--context")
            context = int(args[i + 1])
            args = args[:i] + args[i + 2:]
        model = args[0] if args else str(DEFAULT_MODEL)
        tag = f"{Path(model).name} @ {testset.name}" + (f" ctx={context}" if context else "")
        _report(tag, score_model(model, testset, context))
