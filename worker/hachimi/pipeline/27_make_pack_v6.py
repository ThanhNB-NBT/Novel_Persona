"""Gói train v6 = v5 (v4 + mỏ neo kaihe) + mỏ neo epub + booster THƠ.

Hai thứ mới, nhắm hai lỗ khác nhau nên gộp một lượt train vẫn tách bạch kết quả được:

1. `epub_anchor` — bản dịch TAY từ kho epub, ~77 giọng dịch mới. kaihe tuy 745k cặp nhưng
   chỉ từ 90 bộ; trục thiếu là ĐA DẠNG chứ không phải lượng (DATA_CHUAN trục 2 / LIMA).
   Đo được: LaBSE trung vị 0,770 so với 0,744 của kaihe — sạch hơn.

2. `poem_booster` — THƠ, chỗ v5 gần như bằng 0. Đo 29/08: v5 dịch `更上一层楼` thành
   "tiến thêm một bước nữa" (đúng ra: lên thêm một tầng lầu) và bẻ thơ thành văn xuôi.
   Đây là chỗ DUY NHẤT nên dùng data máy: gemma-4-31b giữ đúng thể ngũ ngôn và gieo vần
   được, mà từ số không thì data máy vẫn nâng. Với văn xuôi thì tuyệt đối không —
   gemma ngang trình v5, chưng cất chỉ nhân bias.

Bộ test thơ được TÁCH RA KHỎI train (khoá lại) để còn đo được.

    python -m pipeline.27_make_pack_v6 [--kaihe 40000] [--labse-min 0.70] [--poem-eval 120]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import zipfile
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from text_clean import clean_source  # noqa: E402  (cùng hàm kaggle_train dùng để so trùng)

ROOT = Path(__file__).resolve().parent
DATA = ROOT.parent / "data"
PACKS = ROOT.parent / "packs"
V5_PACK = PACKS / "hachimi-teacher-v5-kaggle.zip"
V6_PACK = PACKS / "hachimi-teacher-v6-kaggle.zip"
EPUB = DATA / "epub_anchor.jsonl"
POEM = DATA / "poem_vi.jsonl"
HAN = re.compile(r"[一-鿿]")


def _verses(zh: str) -> int:
    return sum(1 for line in zh.split("\n")
               for v in re.split(r"[，,。；;？！]", line) if v.strip())


def _loops(vi: str) -> bool:
    w = vi.split()
    return any(w[i] == w[i + 1] == w[i + 2] for i in range(len(w) - 2))


def gate_poem(row: dict) -> bool:
    """Cổng thơ: đúng số vế, sạch chữ Hán, không lặp. Đo trên 100 bài: 90% đạt."""
    vi = (row.get("vi") or "").strip()
    if not vi or HAN.search(vi) or _loops(vi):
        return False
    lines = [l for l in vi.split("\n") if l.strip()]
    return len(lines) == _verses(row["zh"])


def blocked_zh(pack: zipfile.ZipFile) -> set[str]:
    """ZH của MỌI shard đã có trong pack v5 (gold + eval + kaihe + teacher).

    `combine_clean_shards` raise nếu hai shard cùng một nguồn Trung mà bản dịch khác nhau —
    nên shard mới phải tự tránh, y như `pipeline/20` làm với kaihe."""
    out: set[str] = set()
    for name in pack.namelist():
        if not name.endswith(".jsonl"):
            continue
        for line in pack.read(name).decode("utf-8").splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            zh = clean_source(str(row.get("zh") or row.get("source_zh") or ""))
            if zh:
                out.add(zh)
    return out


def load_epub(labse_min: float, blocked: set[str]) -> list[str]:
    """Khử trùng theo zh, giữ bản LaBSE cao nhất — `load_clean_shard` raise nếu một nguồn
    Trung có hai bản dịch khác nhau (chuyện thường gặp: cùng câu xuất hiện ở nhiều chương)."""
    if not EPUB.exists():
        return []
    # Khoá theo clean_source(zh) — kaggle_train so trùng SAU khi làm sạch nên khử trùng
    # trên chuỗi thô là không đủ (đo: vẫn vấp ở dòng 1336).
    best: dict[str, dict] = {}
    for line in EPUB.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        r = json.loads(line)
        key = clean_source(r["zh"])
        if key in blocked:
            continue
        cur = best.get(key)
        if cur is None or (r.get("labse") or 0) > (cur.get("labse") or 0):
            best[key] = r
    out = []
    for r in best.values():
        if r.get("labse") is None or r["labse"] >= labse_min:
            # kaggle_train.load_clean_shard đòi nhãn này cho mọi shard --clean-replay
            out.append(json.dumps({"zh": r["zh"], "vi": r["vi"], "domain": "epub_anchor",
                                   "status": "approved_replay"}, ensure_ascii=False))
    return out


def load_poems(n_eval: int, blocked: set[str]) -> tuple[list[str], list[str]]:
    if not POEM.exists():
        return [], []
    rows = [json.loads(l) for l in POEM.read_text(encoding="utf-8").splitlines() if l.strip()]
    good, seen = [], set()
    for r in rows:
        key = clean_source(r["zh"])
        if gate_poem(r) and key not in seen and key not in blocked:
            seen.add(key)
            good.append(r)
    random.Random(20260829).shuffle(good)
    evalset = good[:n_eval]
    train = good[n_eval:]
    to_line = lambda r: json.dumps({"zh": r["zh"], "vi": r["vi"], "domain": "poem",
                                    "status": "approved_replay"}, ensure_ascii=False)
    return [to_line(r) for r in train], [to_line(r) for r in evalset]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--labse-min", type=float, default=0.70)
    ap.add_argument("--poem-eval", type=int, default=120)
    args = ap.parse_args()
    if not V5_PACK.exists():
        raise SystemExit("Chưa có pack v5 — chạy pipeline/20 trước.")

    with zipfile.ZipFile(V5_PACK) as _p:
        blocked = blocked_zh(_p)
    epub = load_epub(args.labse_min, blocked)
    poem_train, poem_eval = load_poems(args.poem_eval, blocked)
    if not epub and not poem_train:
        raise SystemExit("Không có data mới nào (epub_anchor.jsonl / poem_vi.jsonl đều trống).")

    with zipfile.ZipFile(V5_PACK) as src, zipfile.ZipFile(V6_PACK, "w", zipfile.ZIP_DEFLATED) as dst:
        for name in src.namelist():
            if name in ("README.md", "training_manifest.json"):
                continue
            dst.writestr(name, src.read(name))
        if epub:
            dst.writestr("epub_anchor.jsonl", "\n".join(epub) + "\n")
        if poem_train:
            dst.writestr("poem_booster.jsonl", "\n".join(poem_train) + "\n")
            dst.writestr("eval_poem_locked.jsonl", "\n".join(poem_eval) + "\n")
        dst.writestr("README.md", f"""# Hachimi teacher v6 — Kaggle (v5 + mỏ neo epub + booster thơ)

Khác v5:
- `epub_anchor.jsonl` — **{len(epub)}** cặp dịch TAY từ kho epub (đã lọc LaBSE ≥ {args.labse_min}),
  thêm ~77 giọng dịch mà kaihe không có.
- `poem_booster.jsonl` — **{len(poem_train)}** bài THƠ Đường (chinese-poetry, MIT, đã chuyển
  giản thể) dịch bằng gemma-4-31b rồi lọc qua cổng thơ.
- `eval_poem_locked.jsonl` — **{len(poem_eval)}** bài KHOÁ để đo, KHÔNG được train.

## Train

Giữ nguyên lệnh của v5, thêm hai shard mới vào `--clean-replay`:

```bash
accelerate launch --num_processes=2 --multi_gpu kaggle_train.py \\
  --clean-gold core_gold_240.jsonl --clean-gold train_game_english_approved.jsonl \\
  --clean-gold train_db_game_litrpg_approved.jsonl --clean-gold booster_v3.jsonl \\
  --clean-replay rhythm_gold.jsonl --clean-replay kaihe_anchor.jsonl \\
  --clean-replay epub_anchor.jsonl --clean-replay poem_booster.jsonl
```

## Đo sau khi train

1. Thước dự án (đại từ hiện đại / lint / bịa chủ ngữ) trên bộ chương sạch — v5 đang là
   0,95 đại từ và 3,15 lint mỗi chương.
2. **Thơ**: dịch `eval_poem_locked.jsonl`, đếm bài giữ đúng số vế + sạch chữ Hán. v5 hiện
   gần như trượt toàn bộ (bẻ thơ thành văn xuôi).
""")
        dst.writestr("training_manifest.json", json.dumps({
            "status": "ready_for_kaggle_train",
            "base": "hachimi-teacher-v5 + epub anchor + poem booster",
            "epub_anchor": len(epub), "labse_min": args.labse_min,
            "poem_train": len(poem_train), "poem_eval_locked": len(poem_eval),
            "poem_source": "chinese-poetry (MIT) + gemma-4-31b",
        }, ensure_ascii=False, indent=2) + "\n")

    print(json.dumps({"pack": str(V6_PACK), "epub_anchor": len(epub),
                      "poem_train": len(poem_train), "poem_eval": len(poem_eval),
                      "sha256": hashlib.sha256(V6_PACK.read_bytes()).hexdigest()[:16]},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
