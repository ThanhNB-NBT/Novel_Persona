"""Gộp 100k cặp văn xuôi (epub zh → Gemini vi) thành shard corpus doc-level cho v7.

Nguồn: `~/hachimi-work/scratch/prose_batch/{in,out}_XXX.jsonl` — 401 lô × 250 câu.
`in_` là câu Trung trích từ nguyên tác epub, `out_` là bản dịch Gemini đã soát 4 vòng
(xem `docs/ban-giao-2026-09-01-prose.md`).

Vì sao cần script riêng thay vì nhét vào `28_build_scratch_corpus.py`:
`28` đọc định dạng kaihe (mỗi dòng MỘT truyện, `sentences: [[vi, zh], ...]`), còn prose nằm
rải theo lô 250 câu không mang nhãn truyện. Script này dựng lại nhãn rồi ra ĐÚNG định dạng
`28` xuất, để hai file nối thẳng được vào nhau.

NHÃN TRUYỆN: `in_*.jsonl` không có field truyện, nhưng đo được cấu trúc — 100.004 câu xếp
thành **1.667 khối 60 câu liên tiếp, mỗi khối một truyện** (khớp con số 1.667 truyện epub
trong bản bàn giao). Nhãn lấy từ `prose_novel_map.jsonl` (dựng bằng
`map_prose_novel.py`, khớp 81% câu về `paired_clean.jsonl`), rồi lấy **nhãn đa số của khối**
cho cả 60 câu. Đa số chứ không phải nhãn đầu tiên: 8/1667 khối dính 1-2 câu khớp nhầm sang
truyện khác (câu trùng nhau giữa hai truyện), lấy đa số là loại được.

CHỈ RA TRAIN, KHÔNG RA DEV — khác `28`. Dev phải là bản dịch NGƯỜI (truyện holdout của
kaihe); nhét bản dịch Gemini vào dev thì thước đo thành "model bắt chước teacher giống đến
đâu" chứ không còn là "dịch hay đến đâu", đúng cái bẫy đã ghi ở mục 5 của
`docs/train-scratch-v7.md`.

Ra: jsonl {"zh", "ctx", "vi", "novel", "ctx_len"} + `<out>.manifest.json`.

    python 35_build_prose_corpus.py --out ~/hachimi-work/scratch/prose_corpus.jsonl \
        --block-extra ~/hachimi-work/scratch/clean_testset.jsonl
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import random
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from kaggle_train import _QUOTE_PAIRS, _replay_ok
from text_clean import clean_source

# `28_build_scratch_corpus` mở đầu bằng chữ số nên `import` thường không nuốt được — nạp tay
# để DÙNG LẠI cổng lọc và khoá khử trùng của nó, đừng chép lại (chép là đẻ ra cặp mirror phải
# sửa hai đầu).
_SPEC = importlib.util.spec_from_file_location(
    "scratch_corpus", Path(__file__).resolve().parent / "28_build_scratch_corpus.py")
_M = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_M)

BLOCK = 60          # mỗi truyện đóng góp đúng 60 câu liên tiếp (đã đo, xem chú thích đầu file)
NOVEL_PREFIX = "epub:"   # tách hẳn không gian tên khỏi truyện kaihe (tên Trung) cho dễ truy vết


def _quote_delta(text: str) -> tuple:
    """Chữ ký lệch nháy: dư mở−dư đóng của từng cặp, kèm parity nháy thẳng."""
    return (*(text.count(l) - text.count(r) for l, r in _QUOTE_PAIRS), text.count('"') % 2)


def _pad_quotes(text: str) -> str:
    """Bù nháy cho cân — CHỈ để chấm cổng, không dùng làm dữ liệu ghi ra."""
    for left, right in _QUOTE_PAIRS:
        diff = text.count(left) - text.count(right)
        if diff > 0:
            text += right * diff
        elif diff < 0:
            text = left * (-diff) + text
    return text + '"' if text.count('"') % 2 else text


def prose_replay_ok(zh: str, vi: str) -> bool:
    """`_replay_ok` nới ĐÚNG một chỗ: hai phía lệch nháy GIỐNG HỆT nhau thì vẫn nhận.

    Nguồn prose cắt câu giữa lời thoại nên dấu `”` đóng thoại rơi sang đầu câu SAU — đo
    31/08: 17.494 cặp lệch nháy cả hai phía, 17.390 (99,4%) lệch y hệt nhau, tức bản dịch
    bám đúng dấu mồ côi của nguồn chứ không hỏng. Cổng chung loại thẳng 24% corpus vì lỗi
    của bộ CẮT CÂU, không phải lỗi dịch.

    Và đây là tình huống CHẠY THẬT: `hachimi_engine` cũng cắt chương ra câu kiểu ấy, luật 9
    của prompt dịch bắt giữ nguyên dấu mồ côi. Nên giữ lại là dạy đúng cái model sẽ gặp.

    Lệch KHÁC nhau giữa hai phía thì vẫn loại — đó là dịch thêm/bớt nháy, lỗi thật.
    Văn bản ghi ra vẫn là bản GỐC còn dấu mồ côi; bù nháy chỉ để chấm cổng.
    """
    if _replay_ok(zh, vi):
        return True
    if _quote_delta(zh) != _quote_delta(vi):
        return False
    return _replay_ok(_pad_quotes(zh), _pad_quotes(vi))


def load_novel_map(path: Path) -> dict[int, str]:
    """gid → tên truyện, lấy nhãn ĐA SỐ của khối 60 câu."""
    votes: dict[int, Counter] = defaultdict(Counter)
    total = 0
    for line in path.open(encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        total = max(total, row["gid"] + 1)
        if row.get("novel"):
            votes[row["gid"] // BLOCK][row["novel"]] += 1
    out: dict[int, str] = {}
    for gid in range(total):
        counter = votes.get(gid // BLOCK)
        if counter:
            out[gid] = counter.most_common(1)[0][0]
    return out


def load_pairs(batch_dir: Path) -> list[dict]:
    """[{gid, novel_block, zh, vi}] theo đúng thứ tự lô rồi `n` — thứ tự này LÀ thứ tự văn bản."""
    rows: list[dict] = []
    for idx in range(401):
        src = {o["n"]: o["zh"] for o in _read(batch_dir / f"in_{idx:03d}.jsonl")}
        tgt = {o["n"]: o["vi"] for o in _read(batch_dir / f"out_{idx:03d}.jsonl")}
        for n in sorted(src):
            rows.append({"gid": len(rows), "n": n, "file": f"{idx:03d}",
                         "zh": src[n], "vi": tgt.get(n, "")})
    return rows


def _read(path: Path) -> list[dict]:
    return [json.loads(l) for l in path.open(encoding="utf-8") if l.strip()]


def build(args) -> dict:
    batch_dir = Path(args.batch)
    pairs = load_pairs(batch_dir)
    novel_of = load_novel_map(Path(args.novel_map))
    print(f"Đọc {len(pairs):,} cặp · {len(set(novel_of.values()))} truyện có nhãn", flush=True)

    blocked = set() if args.no_block else _M.load_blocked(Path(args.root), args.block_extra)
    print(f"Chặn {len(blocked)} câu nguồn của bộ eval khoá", flush=True)

    rng = random.Random(args.seed)
    weights = [int(w) for w in args.ctx_mix.split(",")]
    if len(weights) != _M.MAX_CTX + 1 or sum(weights) <= 0:
        raise SystemExit(f"--ctx-mix cần {_M.MAX_CTX + 1} số dương, ví dụ 40,30,30")

    # Làm sạch trước, giữ nguyên vị trí: ngữ cảnh lấy từ dòng nguồn LIỀN KỀ kể cả dòng bị cổng
    # loại (cổng loại vì bản DỊCH lỗi, nguồn vẫn là ngữ cảnh hợp lệ) — y hệt `28.novel_pairs`.
    for row in pairs:
        row["zh"] = clean_source(str(row["zh"] or "")).strip()
        row["vi"] = str(row["vi"] or "").strip()

    stats = {"pairs_in": len(pairs), "rows": 0, "no_novel": 0, "empty": 0,
             "machine_shard": 0, "replay_fail": 0, "dup": 0, "blocked_hit": 0,
             "novels": 0, "ctx_hist": {str(k): 0 for k in range(_M.MAX_CTX + 1)}}
    seen: set[int] = set()
    novels_out: set[str] = set()
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", encoding="utf-8") as handle:
        for row in pairs:
            gid = row["gid"]
            name = novel_of.get(gid)
            if not name:
                stats["no_novel"] += 1
                continue
            zh, vi = row["zh"], row["vi"]
            if not zh or not vi:
                stats["empty"] += 1
                continue
            if _M.is_machine_shard(zh, vi):
                stats["machine_shard"] += 1
                continue
            if not prose_replay_ok(zh, vi):
                stats["replay_fail"] += 1
                continue
            key = _M._zh_key(zh)
            if key in blocked:
                stats["blocked_hit"] += 1
                continue
            if key in seen:
                stats["dup"] += 1
                continue
            seen.add(key)

            # Ngữ cảnh KHÔNG được vượt biên khối: hai khối cạnh nhau là hai truyện khác hẳn.
            block_start = (gid // BLOCK) * BLOCK
            ctx = [pairs[j]["zh"] for j in range(max(block_start, gid - _M.MAX_CTX), gid)
                   if pairs[j]["zh"]]
            ctx_len = rng.choices(range(_M.MAX_CTX + 1), weights=weights)[0]
            ctx = ctx[-ctx_len:] if ctx_len else []

            novels_out.add(name)
            handle.write(json.dumps(
                {"zh": zh, "ctx": ctx, "vi": vi,
                 "novel": NOVEL_PREFIX + name, "ctx_len": len(ctx)},
                ensure_ascii=False) + "\n")
            stats["rows"] += 1
            stats["ctx_hist"][str(len(ctx))] += 1

    stats["novels"] = len(novels_out)
    manifest = {**stats, "batch": str(batch_dir), "novel_map": str(args.novel_map),
                "seed": args.seed, "ctx_mix": args.ctx_mix, "sep": _M.DEFAULT_SEP,
                "novel_prefix": NOVEL_PREFIX, "split": "train-only",
                "blocked_sources": len(blocked)}
    Path(str(out_path) + ".manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def _self_check() -> None:
    import tempfile

    # Cổng nháy: nhận khi lệch GIỐNG nhau, loại khi lệch KHÁC nhau (đối chứng âm bắt buộc —
    # không có nó thì một hàm `return True` cũng qua bài kiểm).
    zh_open = "她关切问道，“冷不冷？"
    vi_open = "Nàng quan tâm hỏi, “Lạnh không?"
    assert prose_replay_ok(zh_open, vi_open), "cùng lệch nháy mà bị loại"
    assert not prose_replay_ok(zh_open, "Nàng quan tâm hỏi, “Lạnh không?”"), "lệch khác nhau mà vẫn nhận"
    assert not prose_replay_ok(zh_open, "Nàng quan tâm hỏi, 1 lạnh không?"), "sai chữ số mà vẫn nhận"

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        batch = tmp / "batch"
        batch.mkdir()
        # Hai "truyện" tí hon: khối 0 và khối 1, mỗi khối BLOCK câu, nhồi vào một lô giả.
        src, tgt = [], []
        for gid in range(2 * BLOCK):
            src.append({"n": gid + 1, "zh": f"第{gid}句，他走进房间。"})
            tgt.append({"n": gid + 1, "vi": f"Câu {gid}, hắn bước vào phòng."})
        (batch / "in_000.jsonl").write_text(
            "\n".join(json.dumps(o, ensure_ascii=False) for o in src), encoding="utf-8")
        (batch / "out_000.jsonl").write_text(
            "\n".join(json.dumps(o, ensure_ascii=False) for o in tgt), encoding="utf-8")
        for idx in range(1, 401):      # các lô còn lại rỗng cho đủ vòng lặp
            (batch / f"in_{idx:03d}.jsonl").write_text("", encoding="utf-8")
            (batch / f"out_{idx:03d}.jsonl").write_text("", encoding="utf-8")

        nmap = tmp / "map.jsonl"
        with nmap.open("w", encoding="utf-8") as fh:
            for gid in range(2 * BLOCK):
                # Bỏ trống vài nhãn + cắm MỘT nhãn nhiễu để thử luật "đa số"
                novel = None if gid % 7 == 0 else ("truyen-a" if gid < BLOCK else "truyen-b")
                if gid == 3:
                    novel = "nhieu"
                fh.write(json.dumps({"gid": gid, "novel": novel}, ensure_ascii=False) + "\n")

        out = tmp / "prose.jsonl"
        args = argparse.Namespace(
            batch=batch, novel_map=nmap, out=out, root=HERE, seed=1,
            ctx_mix="0,0,100", block_extra=[], no_block=True)
        manifest = build(args)

        rows = [json.loads(l) for l in out.open(encoding="utf-8")]
        assert manifest["rows"] == len(rows) > 0, manifest
        names = {r["novel"] for r in rows}
        assert names == {NOVEL_PREFIX + "truyen-a", NOVEL_PREFIX + "truyen-b"}, names
        # ctx-mix 0,0,100 ⇒ mọi dòng phải có 2 ctx, TRỪ hai dòng mở đầu mỗi khối
        head = [r for r in rows if r["ctx_len"] < 2]
        assert len(head) == 4, [r["zh"] for r in head]
        # ctx không được vượt biên khối: dòng đầu khối 1 phải sạch ctx
        first_b = next(r for r in rows if r["novel"].endswith("truyen-b"))
        assert first_b["ctx"] == [], first_b
        print("self-check OK:", json.dumps(
            {k: manifest[k] for k in ("pairs_in", "rows", "novels", "ctx_hist")},
            ensure_ascii=False))


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", type=Path,
                    default=Path.home() / "hachimi-work/scratch/prose_batch")
    ap.add_argument("--novel-map", type=Path,
                    default=Path.home() / "hachimi-work/scratch/prose_novel_map.jsonl")
    ap.add_argument("--out", type=Path,
                    default=Path.home() / "hachimi-work/scratch/prose_corpus.jsonl")
    ap.add_argument("--root", type=Path, default=HERE, help="gốc worker/hachimi để tìm bộ eval khoá")
    ap.add_argument("--ctx-mix", default="40,30,30", help="tỉ lệ ctx-0,ctx-1,ctx-2")
    ap.add_argument("--seed", type=int, default=20260901)
    ap.add_argument("--block-extra", type=Path, action="append", default=[],
                    help="jsonl test ngoài repo cần chặn, ví dụ ~/hachimi-work/clean_testset.jsonl")
    ap.add_argument("--no-block", action="store_true", help="bỏ bước chặn eval (chỉ để thử)")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)

    if args.self_check:
        _self_check()
        return
    manifest = build(args)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
