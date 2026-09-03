"""`data/poem_vi.jsonl` → shard corpus doc-level cho v7, MỘT DÒNG MỘT VẾ.

Vì sao vế chứ không phải cả bài: `eval/eval_poem.py` ghi rõ *"Dịch TỪNG VẾ: đó là cách
production chia câu, và cũng là cách duy nhất giữ được thể thơ"* — runtime cắt câu theo
`，。；？！` nên model chỉ bao giờ nhìn thấy MỘT vế. Train cả bài là dạy một hình dạng đầu vào
model không gặp bao giờ. Ngữ cảnh (`ctx`) gánh phần còn lại: 2 vế trước của chính bài đó.

Cổng lọc dùng chung với kaihe/prose, nới ĐÚNG một chỗ — xem `poem_replay_ok`.

Ra: jsonl {"zh", "ctx", "vi", "novel", "ctx_len"} + `<out>.manifest.json`.

    python 37_build_poem_corpus.py --out ~/hachimi-work/scratch/poem_corpus.jsonl
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import random
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from kaggle_train import _basic_structure_ok, _register_ok, _source_ok

_SPEC = importlib.util.spec_from_file_location(
    "scratch_corpus", Path(__file__).resolve().parent / "28_build_scratch_corpus.py")
_M = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_M)

_HAN = re.compile(r"[一-鿿]")
_WORD = re.compile(r"[a-zà-ỹđ]+", re.IGNORECASE)
_SPLIT = re.compile(r"[，,。；;？！]")
NOVEL_PREFIX = "poem:"
SYL_RATIO = (0.5, 2.0)


def verses(zh: str) -> list[str]:
    """Chia vế y hệt `eval_poem.verses` — phải khớp, không thì train và đo lệch đơn vị."""
    return [v.strip() for line in zh.split("\n") for v in _SPLIT.split(line) if v.strip()]


def poem_replay_ok(zh: str, vi: str) -> bool:
    """`_replay_ok` cho THƠ: đổi cổng tỉ lệ KÝ TỰ sang tỉ lệ ÂM TIẾT.

    Cổng chung chặn `0,25 ≤ ký_tự_vi / ký_tự_zh ≤ 4`, hiệu chỉnh cho câu văn xuôi dài. Chữ
    Hán 1 ký tự = 1 âm, còn tiếng Việt latin hoá tốn ~3,8 ký tự mỗi âm — nên vế thơ ngắn
    (5-7 chữ) luôn vọt quá trần 4 dù dịch đúng: `回首白云间` → `ngoảnh trông giữa bạch vân`
    là 5 chữ ra 5 âm, chuẩn mực, mà tỉ lệ ký tự là 4,6 ⇒ bị loại.

    Đo 01/09 trên 213.790 vế: tỉ lệ **âm tiết** trung vị đúng **1,00** (p5 1,0 · p95 1,4),
    **100%** nằm trong [0,5; 2] — dịch thơ giữ nguyên số âm, đó mới là dấu hiệu đúng. Cổng
    ký tự loại oan 26%.

    Các cổng khác giữ nguyên: sạch Hán, cân nháy, cấm register hiện đại, khớp chữ số.
    """
    if not _source_ok(zh) or not _basic_structure_ok(vi) or not _register_ok(vi):
        return False
    if re.findall(r"\d+", zh) != re.findall(r"\d+", vi):
        return False
    han = len(_HAN.findall(zh))
    syllables = len(_WORD.findall(vi))
    if not han or not syllables:
        return False
    return SYL_RATIO[0] <= syllables / han <= SYL_RATIO[1]


def load_poems(path: Path) -> list[dict]:
    """[{title, zh_verses, vi_verses}] — chỉ giữ bài khớp số vế (booster đã gác, kiểm lại)."""
    out: list[dict] = []
    for line in path.open(encoding="utf-8"):
        if not line.strip():
            continue
        row = json.loads(line)
        if not row.get("vi"):
            continue
        zh_v = verses(row["zh"])
        vi_v = [l.strip() for l in row["vi"].split("\n") if l.strip()]
        if len(zh_v) != len(vi_v):
            continue
        out.append({"title": row.get("title") or "", "zh": zh_v, "vi": vi_v})
    return out


def load_blocked_verses(paths: list[Path]) -> set[int]:
    """Chặn theo VẾ, không theo bài.

    `eval_poem.py` chấm từng vế, nên một vế của bài eval lọt vào train là rò — kể cả khi cả
    bài thì khác nhau. Chặn ở mức bài (như `36_build_poem_booster`) chưa đủ.
    """
    blocked: set[int] = set()
    for path in paths:
        if not path.exists():
            continue
        for line in path.open(encoding="utf-8"):
            if not line.strip():
                continue
            row = json.loads(line)
            for verse in verses(str(row.get("zh") or "")):
                blocked.add(_M._zh_key(verse))
    return blocked


def build(args) -> dict:
    poems = load_poems(Path(args.poems))
    blocked = set() if args.no_block else load_blocked_verses(list(args.block))
    print(f"Đọc {len(poems):,} bài · chặn {len(blocked)} vế của bộ eval thơ", flush=True)

    rng = random.Random(args.seed)
    weights = [int(w) for w in args.ctx_mix.split(",")]
    if len(weights) != _M.MAX_CTX + 1 or sum(weights) <= 0:
        raise SystemExit(f"--ctx-mix cần {_M.MAX_CTX + 1} số dương, ví dụ 40,30,30")

    stats = {"poems": len(poems), "verses_in": sum(len(p["zh"]) for p in poems),
             "rows": 0, "gate_fail": 0, "dup": 0, "blocked_hit": 0,
             "ctx_hist": {str(k): 0 for k in range(_M.MAX_CTX + 1)}}
    seen: set[int] = set()
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", encoding="utf-8") as handle:
        for index, poem in enumerate(poems):
            name = NOVEL_PREFIX + (poem["title"] or f"bai-{index}")
            for i, (zh, vi) in enumerate(zip(poem["zh"], poem["vi"])):
                key = _M._zh_key(zh)
                if key in blocked:
                    stats["blocked_hit"] += 1
                    continue
                if not poem_replay_ok(zh, vi):
                    stats["gate_fail"] += 1
                    continue
                if key in seen:
                    stats["dup"] += 1
                    continue
                seen.add(key)
                # ctx = vế trước của CHÍNH bài này; hết bài là hết ctx.
                ctx = poem["zh"][max(0, i - _M.MAX_CTX):i]
                ctx_len = rng.choices(range(_M.MAX_CTX + 1), weights=weights)[0]
                ctx = ctx[-ctx_len:] if ctx_len else []
                handle.write(json.dumps(
                    {"zh": zh, "ctx": ctx, "vi": vi, "novel": name, "ctx_len": len(ctx)},
                    ensure_ascii=False) + "\n")
                stats["rows"] += 1
                stats["ctx_hist"][str(len(ctx))] += 1

    manifest = {**stats, "poems_file": str(args.poems), "seed": args.seed,
                "ctx_mix": args.ctx_mix, "sep": _M.DEFAULT_SEP,
                "novel_prefix": NOVEL_PREFIX, "split": "train-only",
                "unit": "verse", "syl_ratio": list(SYL_RATIO),
                "blocked_verses": len(blocked)}
    Path(str(out_path) + ".manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def _self_check() -> None:
    import tempfile

    assert verses("回首白云间，日暮天无云。") == ["回首白云间", "日暮天无云"]
    # Cổng âm tiết: nhận vế thơ chuẩn 5 chữ→5 âm (cổng ký tự cũ loại vì tỉ lệ 4,6)…
    assert poem_replay_ok("回首白云间", "ngoảnh trông giữa bạch vân")
    # …nhưng vẫn loại bản dài lê thê, và loại lỗi thật (sót Hán, sai chữ số).
    assert not poem_replay_ok("回首白云间", " ".join(["dài"] * 20)), "vế dài mà vẫn nhận"
    assert not poem_replay_ok("回首白云间", "ngoảnh trông 白云"), "sót chữ Hán mà vẫn nhận"
    assert not poem_replay_ok("回首白云间", "ngoảnh trông 3 bạch vân"), "sai chữ số mà vẫn nhận"

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        poems = tmp / "poem_vi.jsonl"
        poems.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in [
            {"title": "bài A", "zh": "贱妾如桃李，君王若岁时。\n秋风一已劲，摇落不胜悲。",
             "vi": "Thiếp tựa hoa đào mận,\nquân vương ví tiết thì.\n"
                   "Gió thu vừa thổi mạnh,\nrơi rụng khôn xiết bi."},
            {"title": "bài B", "zh": "回首白云间，日暮天无云。",
             "vi": "ngoảnh trông giữa bạch vân,\nchiều tà trời quang mây."},
        ]), encoding="utf-8")
        block = tmp / "eval.jsonl"
        block.write_text(json.dumps({"zh": "回首白云间"}, ensure_ascii=False), encoding="utf-8")
        out = tmp / "poem_corpus.jsonl"
        stats = build(argparse.Namespace(poems=poems, out=out, block=[block], no_block=False,
                                         seed=1, ctx_mix="0,0,100"))
        rows = [json.loads(l) for l in out.open(encoding="utf-8")]
        assert stats["blocked_hit"] == 1, stats          # vế của bài eval bị chặn
        assert stats["rows"] == 5, stats                 # 4 + (2−1 bị chặn)
        assert rows[0]["ctx"] == [], rows[0]             # vế đầu bài không có ctx
        assert rows[2]["ctx"] == ["贱妾如桃李", "君王若岁时"], rows[2]
        # ctx không được vượt sang bài khác
        first_b = next(r for r in rows if r["novel"] == NOVEL_PREFIX + "bài B")
        assert all(c in ("回首白云间",) or c == "" for c in first_b["ctx"]) or first_b["ctx"] == [], first_b
        print("self-check OK:", json.dumps(
            {k: stats[k] for k in ("poems", "verses_in", "rows", "blocked_hit")},
            ensure_ascii=False))


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--poems", type=Path, default=HERE / "data/poem_vi.jsonl")
    ap.add_argument("--out", type=Path,
                    default=Path.home() / "hachimi-work/scratch/poem_corpus.jsonl")
    ap.add_argument("--block", action="append", type=Path,
                    default=[Path.home() / "hachimi-work/eval_poem_locked.jsonl"],
                    help="jsonl eval thơ cần chặn (chặn theo VẾ)")
    ap.add_argument("--ctx-mix", default="40,30,30", help="tỉ lệ ctx-0,ctx-1,ctx-2")
    ap.add_argument("--seed", type=int, default=20260901)
    ap.add_argument("--no-block", action="store_true")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)

    if args.self_check:
        _self_check()
        return
    print(json.dumps(build(args), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
