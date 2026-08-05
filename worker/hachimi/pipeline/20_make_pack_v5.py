"""Gói train v5 = recipe teacher-v4 (giữ NGUYÊN) + mỏ neo người dịch kaihe (pipeline 19).

Vì sao v5 khác v4: teacher-v4 là 100% data máy-sinh (model collapse, DATA_CHUAN trục 1).
kaihe là bản dịch NGƯỜI, căn theo chương → mỏ neo chống sụp. Đây là bậc 2 mà chính tài liệu
dự án đặt ra ("chạy cổng nhất quán theo giới lên kaihe... con số quyết định bậc 2 có nguyên
liệu hay không"), KHÔNG phải doc-level (đã đóng).

Thiết kế then chốt — KHÔNG đổ hết 745k kaihe vào:
  Bài học doc-level v1: corpus rộng/loãng làm TỤT register về base, mất booster nhắm-đích của
  teacher-v4. Nên kaihe được SAMPLE xuống cỡ mỏ-neo cân bằng (mặc định 40k), gold vẫn ×3 để
  giữ tiếng nói. Tỉ lệ ghi vào manifest. Muốn mỏ neo mạnh hơn/nhẹ hơn: đổi --kaihe.

LaBSE (DATA_CHUAN cổng 1): kaihe căn bằng thuật toán, CÒN lệch-căn (đọc tay thấy ~vài %).
Khuyến nghị chạy 15_score_labse trên kaihe_anchor.jsonl để siết cosine≥0.7 TRƯỚC khi train
nếu muốn sạch hơn — bước tùy chọn, ghi trong README pack.

Chạy:  python -m pipeline.20_make_pack_v5 [--kaihe 40000]   (sau khi đã chạy pipeline 19)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import zipfile
from pathlib import Path

import prepare_teacher_v4_pack as v4
from kaggle_train import clean_source

ROOT = Path(__file__).resolve().parent
DATA = ROOT.parent / "data"
ANCHOR = DATA / "kaihe_anchor.jsonl"
V4_PACK = ROOT.parent / "packs" / "hachimi-teacher-v4-kaggle.zip"
V5_PACK = ROOT.parent / "packs" / "hachimi-teacher-v5-kaggle.zip"
GOLD_FILES = ("core_gold_240.jsonl", "train_game_english_approved.jsonl",
              "train_db_game_litrpg_approved.jsonl", "booster_v3.jsonl")


def _blocked_zh(pack: zipfile.ZipFile) -> set[str]:
    """ZH của MỌI shard khác (gold + eval + teacher replay) — combine_clean_shards raise nếu
    kaihe trùng zh với bất kỳ shard nào mà vi khác, nên phải loại hết trước."""
    blocked: set[str] = set()
    for name in pack.namelist():
        if not name.endswith(".jsonl"):
            continue
        for line in pack.read(name).decode("utf-8").splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            zh = clean_source(str(row.get("zh") or row.get("source_zh") or ""))
            if zh:
                blocked.add(zh)
    return blocked


def _sample_anchor(limit: int, blocked: set[str]) -> list[str]:
    """Đọc kaihe_anchor, loại zh trùng gold/eval, random sample `limit` (seed cố định)."""
    rows = [l for l in ANCHOR.read_text(encoding="utf-8").splitlines() if l.strip()]
    kept = [l for l in rows if json.loads(l)["zh"] not in blocked]
    random.Random(20260805).shuffle(kept)
    return kept[:limit] if limit and limit < len(kept) else kept


def _readme(kaihe_n: int, total_anchor: int) -> str:
    return f"""# Hachimi teacher v5 — Kaggle (v4 + mỏ neo người dịch kaihe + LaBSE)

Khác v4: thêm mỏ neo **kaihe** (bản dịch NGƯỜI, đã lọc pipeline 19: cổng nhất quán xưng hô
theo giới + anh/em sến + toàn bộ cổng replay của kaggle_train) để chống **model-collapse**
(DATA_CHUAN trục 1). Gold vẫn ×3 để giữ booster register nhắm-đích.

`kaihe_pre_labse.jsonl` = **{kaihe_n}** cặp (sample seed 20260805 từ {total_anchor} cặp sạch),
CHƯA lọc LaBSE. Chạy LaBSE trên GPU Kaggle để vứt cặp **lệch-căn** (Trung một đằng, Việt một
nẻo) mà cổng regex không thấy — cả 3 bước dưới đây trong CÙNG 1 phiên Kaggle:

```bash
pip -q install "transformers==4.48.3" "datasets==3.3.2" "accelerate==1.3.0" \\
  sentence-transformers sentencepiece ctranslate2

# B1 — chấm độ căn khớp bằng LaBSE (tự dùng GPU T4)
python 15_score_labse.py kaihe_pre_labse.jsonl kaihe_scored.jsonl --batch 256

# B2 — xem 15 cặp điểm thấp (ĐỌC TAY chốt ngưỡng) rồi lọc ra file train
python labse_filter.py kaihe_scored.jsonl kaihe_anchor.jsonl --min 0.70

# B3 — train (dùng kaihe_anchor.jsonl vừa lọc)
accelerate launch --num_processes=2 --multi_gpu kaggle_train.py \\
  --clean-gold core_gold_240.jsonl --clean-gold train_game_english_approved.jsonl \\
  --clean-gold train_db_game_litrpg_approved.jsonl --clean-gold booster_v3.jsonl \\
  --clean-replay teacher_general_screened.jsonl --clean-replay teacher_game_screened.jsonl \\
  --clean-replay rhythm_gold.jsonl --clean-replay kaihe_anchor.jsonl \\
  --eval eval_reference_60.jsonl --eval-chapters eval_fullchapters_6_locked.jsonl \\
  --eval-chapters eval_game_english_locked.jsonl --pro-limit 0 --replay-limit 0 \\
  --gold-repeat 3 --epochs 1 --lr 1e-5 \\
  --output-dir /kaggle/working/hachimi-teacher-v5 --export-ct2
```

**Bỏ LaBSE (train nhanh, chấp nhận ~vài % lệch-căn):** `cp kaihe_pre_labse.jsonl kaihe_anchor.jsonl`
rồi chạy thẳng B3.

**Muốn lọc từ TOÀN BỘ {total_anchor} cặp** (chất hơn 40k pre-sample): upload
`data/kaihe_anchor.jsonl` (463MB, ở máy) làm Kaggle Dataset, chạy B1/B2 trên nó rồi sample.

Sau khi tải model về: đo bằng `eval/eval_register.py` — mục tiêu GIỮ register của v4 và xem mỏ
neo có giảm lỗi phần-đuôi (lược chủ ngữ) không. Nếu register TỤT so v4 → dựng lại pack
`20_make_pack_v5.py --kaihe N` nhỏ hơn (bài học doc-level v1).
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kaihe", type=int, default=40_000, help="số cặp kaihe đưa vào (0=bỏ)")
    args = ap.parse_args()

    if not ANCHOR.exists():
        raise SystemExit("Chưa có kaihe_anchor.jsonl — chạy pipeline 19 trước.")
    v4.build()  # tái dựng pack v4 (nguồn chân lý cho mọi shard cũ)

    total_anchor = sum(1 for l in ANCHOR.read_text(encoding="utf-8").splitlines() if l.strip())
    with zipfile.ZipFile(V4_PACK) as src:
        blocked = _blocked_zh(src)
        anchor_lines = _sample_anchor(args.kaihe, blocked) if args.kaihe else []
        with zipfile.ZipFile(V5_PACK, "w", zipfile.ZIP_DEFLATED) as dst:
            for name in src.namelist():
                if name in ("README.md", "training_manifest.json"):
                    continue
                dst.writestr(name, src.read(name))
            # Script LaBSE để lọc lệch-căn trên GPU Kaggle (xem README, chạy trước train)
            dst.write(ROOT / "15_score_labse.py", "15_score_labse.py")
            dst.write(ROOT / "labse_filter.py", "labse_filter.py")
            if anchor_lines:
                # CHƯA lọc LaBSE — Kaggle sẽ score+lọc thành kaihe_anchor.jsonl (README B1/B2)
                dst.writestr("kaihe_pre_labse.jsonl", "\n".join(anchor_lines) + "\n")
            dst.writestr("README.md", _readme(len(anchor_lines), total_anchor))
            dst.writestr("training_manifest.json", json.dumps({
                "status": "ready_for_kaggle_train",
                "base": "hachimi-teacher-v4 + kaihe anchor",
                "kaihe_in_pack": len(anchor_lines),
                "kaihe_anchor_total": total_anchor,
                "kaihe_blocked_by_gold_eval": "loại zh trùng gold/eval",
                "sample_seed": 20260805,
            }, ensure_ascii=False, indent=2) + "\n")

    sha = hashlib.sha256(V5_PACK.read_bytes()).hexdigest()
    print(json.dumps({"pack": str(V5_PACK), "kaihe_in_pack": len(anchor_lines),
                      "kaihe_anchor_total": total_anchor, "sha256": sha}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
