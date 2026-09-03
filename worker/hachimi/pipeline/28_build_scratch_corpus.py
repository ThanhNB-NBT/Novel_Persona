"""Dựng corpus train-from-scratch (v7) từ kaihe — mỏ neo NGƯỜI dịch, tách theo TRUYỆN.

Vì sao có script này (docs/train-scratch-v7.md mục 6):
- `19_build_anchor_kaihe.py` đọc `data/kaihe/aligned_chapters.jsonl` (bản căn theo chương, đã
  cũ) và ném ra cặp câu-lẻ cho **finetune**. Vòng v7 cần bản gốc `kaihe_parallel_sentences.jsonl`
  (332 truyện · 32M cặp) vì nó giữ **THỨ TỰ CÂU trong truyện** → dựng được ngữ cảnh.
- P0/P1/P2 phải chạy trên **cùng một tập câu**, chỉ khác ngữ cảnh. Nên ở đây KHÔNG ghép sẵn
  chuỗi `ctx ⟪ctx⟫ câu`; mỗi dòng ra mang sẵn `ctx` (tối đa 2 dòng nguồn phía trước) và lúc
  train mới render theo `--ctx-mix`. Đổi một nút thì khỏi dựng lại data.

Định dạng kaihe gốc: MỖI DÒNG JSONL LÀ MỘT TRUYỆN
    {"name": "妖神记", "sentences": [[vi, zh], [vi, zh], ...]}   ← tiếng VIỆT đứng TRƯỚC.

Ra: jsonl {"zh", "ctx": [zh_{i-2}, zh_{i-1}], "vi", "novel"} + `<out>.manifest.json`.

    python 28_build_scratch_corpus.py --kaihe ~/hachimi-work/kaihe_parallel_sentences.jsonl \
        --out ~/hachimi-work/scratch/corpus.jsonl \
        --eval-out ~/hachimi-work/scratch/dev.jsonl --limit 2000000
    python 28_build_scratch_corpus.py --self-check

Cổng: dùng LẠI `kaggle_train._replay_ok` (register cấm modern, Hán sạch, ngoặc cân, ratio, số
khớp) để shard v7 khớp hệt các shard khác — đừng chế cổng lệch. LaBSE **không** chạy ở đây:
11M cặp là một job GPU riêng, probe bỏ qua (mục 6 của spec).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kaggle_train import _replay_ok
from text_clean import clean_source

HERE = Path(__file__).resolve().parents[1]
DEFAULT_SEP = "⟪ctx⟫"          # phải khớp HỆT `settings.hachimi_context_sep` và 16_make_doclevel
MAX_CTX = 2                     # trần ngữ cảnh; max_position 512 dư chỗ cho 2 dòng
# Bộ eval khoá: mọi zh ở đây bị chặn khỏi train (chống rò, spec mục 7).
BLOCKED_GLOBS = ("data/eval_locked/*.jsonl", "data/gold/*.jsonl")

# --- Cổng "kho con máy xử lý" -------------------------------------------------
# Đo 30/08 trên 102k dòng: **34% kaihe không phải văn người** mà là data đã qua tiền xử lý của
# một pipeline MT khác — chữ Hán tách rời từng chữ, tiếng Việt viết thường tuốt kể cả tên riêng,
# lác đác token `<UNK>` lọt nguyên vào bản dịch:
#     叶 紫 芸 身 份 高 贵  →  thân phận diệp tử vân cao quý
# `_replay_ok` KHÔNG bắt được (nó không xét hoa/thường lẫn dấu cách). Train vào là dạy model
# xuất tên riêng viết thường — đúng trục dự án đang yếu, và nguồn tách chữ thì tokenize khác
# hẳn lúc chạy thật. Phải loại, không sửa được: phía zh gỡ dấu cách thì dễ, nhưng phía vi
# không khôi phục nổi chữ hoa của TÊN RIÊNG, mà vi mới là cái model học để sinh ra.
_HAN_BEFORE_SPACE = re.compile(r"[一-鿿](?= )")
_HAN_CHAR = re.compile(r"[一-鿿]")
MIN_LEN_FOR_CASE = 20           # câu ngắn không có chữ hoa là chuyện thường, đừng vu oan


def is_machine_shard(zh: str, vi: str) -> bool:
    """True nếu cặp thuộc kho con đã qua máy xử lý (xem chú thích khối trên)."""
    if "<UNK>" in vi or "<UNK>" in zh:
        return True
    han = _HAN_CHAR.findall(zh)
    # ≥3 chứ không phải ≥4: đo 30/08, hạ 4→3 bắt thêm 2,18% mà KHÔNG oan cặp nào
    # (`裂 云 手`, `城 主 府`, `受 死 吧`… đều là kho máy). Dưới 3 chữ thì thôi — tiếng Trung
    # thật hiếm khi có dấu cách nên tỉ lệ >50% đã đủ chắc, nhưng mẫu 2 chữ thì quá mỏng.
    if len(han) >= 3 and len(_HAN_BEFORE_SPACE.findall(zh)) / len(han) > 0.5:
        return True
    stripped = vi.strip()
    return (len(stripped) >= MIN_LEN_FOR_CASE
            and not any(ch.isalpha() and ch.isupper() for ch in stripped))


def render_source(row: dict, ctx_len: int, sep: str = DEFAULT_SEP) -> str:
    """Ghép `ctx ⟪ctx⟫ câu` đúng cách hachimi_engine ghép lúc chạy thật.

    `ctx` lưu theo thứ tự XUÔI (xa → gần), nên lấy `ctx_len` phần tử CUỐI.
    """
    ctx = [c for c in row.get("ctx") or [] if c][-max(0, ctx_len):] if ctx_len > 0 else []
    return sep.join([*ctx, row["zh"]]) if ctx else row["zh"]


def _zh_key(zh: str) -> int:
    """Khoá khử trùng 8 byte — set 11M int tốn ~350MB, đủ rẻ so với giữ nguyên chuỗi."""
    return int.from_bytes(hashlib.blake2b(zh.encode("utf-8"), digest_size=8).digest(), "big")


def is_holdout(name: str, seed: int, pct: int) -> bool:
    """Tách theo TRUYỆN (không theo câu) — tất định, khỏi giữ danh sách rời."""
    digest = hashlib.blake2b(f"{seed}:{name}".encode(), digest_size=8).digest()
    return int.from_bytes(digest, "big") % 100 < pct


def novel_pairs(sentences: list, limit: int | None) -> list[dict]:
    """Một truyện → các cặp đạt cổng, kèm tối đa 2 dòng nguồn phía trước làm ngữ cảnh.

    Ngữ cảnh lấy từ dòng nguồn LIỀN KỀ trong bản gốc (kể cả dòng bị cổng loại — cổng loại vì
    bản DỊCH lỗi, còn nguồn vẫn là ngữ cảnh hợp lệ). Dòng nguồn rỗng thì bỏ, không tính.
    """
    zh_lines: list[str] = []
    vi_lines: list[str] = []
    for item in sentences:
        if not isinstance(item, (list, tuple)) or len(item) < 2:
            zh_lines.append("")
            vi_lines.append("")
            continue
        vi_raw, zh_raw = item[0], item[1]
        zh_lines.append(clean_source(str(zh_raw or "")).strip())
        vi_lines.append(str(vi_raw or "").strip())

    eligible: list[int] = [
        i for i, (zh, vi) in enumerate(zip(zh_lines, vi_lines))
        if zh and vi and not is_machine_shard(zh, vi) and _replay_ok(zh, vi)
    ]
    if limit and len(eligible) > limit:
        # Lấy mẫu ĐỀU khắp truyện, không lấy phần đầu — chương đầu truyện nào cũng giới thiệu
        # nhân vật, lấy đầu thì corpus lệch về văn tả cảnh.
        step = len(eligible) / limit
        eligible = [eligible[int(k * step)] for k in range(limit)]

    out: list[dict] = []
    for i in eligible:
        ctx = [zh_lines[j] for j in range(max(0, i - MAX_CTX), i) if zh_lines[j]]
        out.append({"zh": zh_lines[i], "ctx": ctx, "vi": vi_lines[i]})
    return out


def load_blocked(root: Path, extra: list[Path] | None = None) -> set[int]:
    """Khoá zh của mọi bộ eval để chúng không lọt vào train.

    `extra` cho các bộ test nằm NGOÀI repo (ví dụ `~/hachimi-work/clean_testset.jsonl`, bộ 55
    chương sạch mà `eval_project_metrics`/`eval_register` dùng) — không chặn thì đo xong không
    biết điểm đẹp là do model giỏi hay do nó đã thấy bài.
    """
    blocked: set[int] = set()
    paths = [p for pattern in BLOCKED_GLOBS for p in sorted(root.glob(pattern))]
    paths += list(extra or [])
    for path in paths:
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            zh = row.get("zh") or row.get("source") or row.get("source_zh") or ""
            for piece in str(zh).split("\n"):
                piece = clean_source(piece).strip()
                if piece:
                    blocked.add(_zh_key(piece))
    return blocked


def _count_novels(path: Path) -> int:
    total = 0
    with path.open("rb") as handle:
        while chunk := handle.read(1 << 24):
            total += chunk.count(b"\n")
    return total


def build(args) -> dict:
    root = Path(args.root)
    blocked = set() if args.no_block else load_blocked(root, args.block_extra)
    print(f"Chặn {len(blocked)} câu nguồn của bộ eval khoá", flush=True)

    novels = args.novels or _count_novels(Path(args.kaihe))
    train_target = max(1, args.limit // max(1, novels))
    rng = random.Random(args.seed)
    weights = [int(w) for w in args.ctx_mix.split(",")]
    if len(weights) != MAX_CTX + 1 or sum(weights) <= 0:
        raise SystemExit(f"--ctx-mix cần {MAX_CTX + 1} số dương, ví dụ 40,30,30")

    seen: set[int] = set()
    stats = {"novels": novels, "novels_train": 0, "novels_holdout": 0,
             "rows": 0, "eval_rows": 0, "dup": 0, "blocked_hit": 0,
             "ctx_hist": {str(k): 0 for k in range(MAX_CTX + 1)}}
    out_path, eval_path = Path(args.out), Path(args.eval_out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    eval_path.parent.mkdir(parents=True, exist_ok=True)

    with (Path(args.kaihe).open(encoding="utf-8") as source,
          out_path.open("w", encoding="utf-8") as train_file,
          eval_path.open("w", encoding="utf-8") as eval_file):
        for index, line in enumerate(source, 1):
            line = line.strip()
            if not line:
                continue
            try:
                novel = json.loads(line)
            except json.JSONDecodeError:
                print(f"  bỏ dòng {index}: JSON hỏng", flush=True)
                continue
            name = str(novel.get("name") or f"novel-{index}")
            holdout = is_holdout(name, args.seed, args.holdout_pct)
            quota = args.eval_per_novel if holdout else train_target
            rows = novel_pairs(novel.get("sentences") or [], quota)
            if holdout:
                stats["novels_holdout"] += 1
            else:
                stats["novels_train"] += 1

            handle = eval_file if holdout else train_file
            written = 0
            for row in rows:
                key = _zh_key(row["zh"])
                if key in blocked:
                    stats["blocked_hit"] += 1
                    continue
                if key in seen:
                    stats["dup"] += 1
                    continue
                seen.add(key)
                row["novel"] = name
                row["ctx_len"] = rng.choices(range(MAX_CTX + 1), weights=weights)[0]
                row["ctx"] = row["ctx"][-row["ctx_len"]:] if row["ctx_len"] else []
                row["ctx_len"] = len(row["ctx"])
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
                stats["ctx_hist"][str(row["ctx_len"])] += 1
                written += 1
            if holdout:
                stats["eval_rows"] += written
            else:
                stats["rows"] += written
            if index % 25 == 0:
                print(f"  {index}/{novels} truyện · train {stats['rows']:,} · dev {stats['eval_rows']:,}",
                      flush=True)
            if args.eval_limit and stats["eval_rows"] >= args.eval_limit and stats["rows"] >= args.limit:
                break

    manifest = {**stats, "kaihe": str(args.kaihe), "seed": args.seed,
                "holdout_pct": args.holdout_pct, "ctx_mix": args.ctx_mix,
                "sep": DEFAULT_SEP, "blocked_sources": len(blocked)}
    Path(str(out_path) + ".manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def _self_check() -> None:
    row = {"zh": "开口说道。", "ctx": ["他走进房间。", "环视四周。"], "vi": "Mở miệng nói."}
    assert render_source(row, 0, "|") == "开口说道。"
    assert render_source(row, 1, "|") == "环视四周。|开口说道。"
    assert render_source(row, 2, "|") == "他走进房间。|环视四周。|开口说道。"
    # ctx nhiều hơn số dòng có sẵn → lấy hết những gì có, không lỗi.
    assert render_source({"zh": "甲。", "ctx": []}, 2, "|") == "甲。"

    sentences = [
        ["Hắn bước vào phòng.", "他走进房间。"],
        ["Tôi thấy vậy.", "我看到了。"],                      # register hiện đại → cổng loại
        ["Mở miệng nói: “Ngươi đến rồi.”", "开口说道：“你来了。”"],
    ]
    pairs = novel_pairs(sentences, None)
    assert [p["zh"] for p in pairs] == ["他走进房间。", "开口说道：“你来了。”"], pairs
    # Dòng bị cổng loại VẪN làm ngữ cảnh (nó bị loại vì bản dịch, nguồn vẫn hợp lệ).
    assert pairs[1]["ctx"] == ["他走进房间。", "我看到了。"], pairs[1]
    # Lấy mẫu đều: 4 câu lấy 2 thì không được dính liền nhau ở đầu.
    many = [[f"Câu {k} hắn nói.", f"第{k}句他说。"] for k in range(10)]
    assert len(novel_pairs(many, 3)) == 3
    assert is_holdout("妖神记", 1, 100) and not is_holdout("妖神记", 1, 0)

    # Cổng kho-con-máy-xử-lý (đo 30/08: 34% kaihe dính).
    assert is_machine_shard("叶 紫 芸 身 份 高 贵", "thân phận diệp tử vân cao quý")
    assert is_machine_shard("不是妈咪思想太古板", "không phải <UNK> tư tưởng cổ hủ")
    # vi dài mà KHÔNG có một chữ hoa nào → kho máy, kể cả khi zh bình thường.
    assert is_machine_shard("陈阳就这么眼睁睁地看着", "chỉ có thể trơ mắt nhìn cánh cửa đóng lại")
    # Không vu oan: văn người bình thường phải lọt.
    assert not is_machine_shard("连绵不绝的圣祖山脉，阳光透过山峦之间的空隙",
                                "Sơn mạch Thánh Tổ liên miên không dứt, ánh mặt trời xuyên qua")
    # Câu NGẮN viết thường là chuyện thường (mẩu giữa câu), đừng loại.
    assert not is_machine_shard("远大", "rộng lớn")
    # Dấu cách lác đác giữa câu (lỗi gõ) khác với TÁCH RỜI TỪNG CHỮ — không được nhầm.
    assert not is_machine_shard("这煞气之强，更蕴含 了无尽的冰寒", "Luồng sát khí này cực mạnh")
    # Cặp thuộc kho máy bị loại khỏi `eligible` nhưng nguồn vẫn dùng làm ngữ cảnh được.
    mixed = novel_pairs([
        ["Hắn bước vào phòng.", "他走进房间。"],
        ["thân phận diệp tử vân cao quý", "叶 紫 芸 身 份 高 贵"],
        ["Mở miệng nói.", "开口说道。"],
    ], None)
    assert [p["zh"] for p in mixed] == ["他走进房间。", "开口说道。"], mixed
    assert mixed[1]["ctx"] == ["他走进房间。", "叶 紫 芸 身 份 高 贵"], mixed[1]
    print("28_build_scratch_corpus OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kaihe", type=Path, default=Path.home() / "hachimi-work/kaihe_parallel_sentences.jsonl")
    ap.add_argument("--out", type=Path, default=Path.home() / "hachimi-work/scratch/corpus.jsonl")
    ap.add_argument("--eval-out", type=Path, default=Path.home() / "hachimi-work/scratch/dev.jsonl")
    ap.add_argument("--root", type=Path, default=HERE, help="gốc worker/hachimi để tìm bộ eval khoá")
    ap.add_argument("--limit", type=int, default=2_000_000, help="trần số cặp TRAIN")
    ap.add_argument("--eval-limit", type=int, default=3_000)
    ap.add_argument("--eval-per-novel", type=int, default=250)
    ap.add_argument("--holdout-pct", type=int, default=4, help="%% truyện giữ làm dev (4%% ≈ 13/332)")
    ap.add_argument("--ctx-mix", default="40,30,30", help="tỉ lệ ctx-0,ctx-1,ctx-2")
    ap.add_argument("--novels", type=int, default=0, help="0 = tự đếm dòng file kaihe")
    ap.add_argument("--seed", type=int, default=20260830)
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
    print(f"→ {args.out}  ·  dev → {args.eval_out}")


if __name__ == "__main__":
    main()
