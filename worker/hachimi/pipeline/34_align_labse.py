"""Căn CÂU trong cặp chương bằng LaBSE — thay cầu dịch máy của `24_align_epub_anchor`.

Vì sao đổi: `24_align_epub_anchor` dịch từng câu Trung bằng Hachimi rồi căn bản-máy với
bản-người bằng độ giống chữ. Cách đó đúng cho vài chục chương, nhưng ta có **162.752 cặp
chương** ≈ 16 triệu câu — dịch cầu trên CPU là hàng trăm giờ.

LaBSE nhúng thẳng câu Trung và câu Việt vào cùng không gian nên **không cần cầu**, và chạy
GPU thì 33 triệu câu chỉ vài giờ. Thêm một cái lợi: điểm căn CHÍNH LÀ điểm LaBSE, nên gộp
luôn bước lọc chất lượng (mục 14 của `docs/train-scratch-v7.md`) — một lượt GPU làm hai việc,
khỏi chạy LaBSE lần nữa.

Phần quy hoạch động (1-1, 1-2, 2-1, cho phép bỏ câu) **giữ nguyên** của `24_align_epub_anchor`,
chỉ thay hàm tính độ giống. Đừng viết lại DP.

    python 34_align_labse.py --paired paired_clean.jsonl --out anchor.jsonl --chapters 40
    python 34_align_labse.py --calibrate      # in phân bố điểm để chọn ngưỡng
    python 34_align_labse.py --self-check     # không cần GPU, không tải model

⚠ Ngưỡng KHÔNG lấy từ `24_align_epub_anchor` được: cosine LaBSE khác thang với độ giống chữ.
Chạy `--calibrate` rồi đọc mẫu quanh ngưỡng, đúng như đã làm ở mục 14.

⚠ Nhịp 1-2 và 2-1: lấy TRUNG BÌNH vector của hai câu thay vì nhúng lại chuỗi ghép. Xấp xỉ này
tiết kiệm ~2/3 số lần nhúng; đổi lại điểm của nhịp ghép hơi thấp hơn thực tế, nên đừng đặt
ngưỡng sát quá.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODEL = "sentence-transformers/LaBSE"
BAND = 0.35          # dải cho phép lệch chỉ số — chương dài thì không cho trôi quá xa
SKIP_COST = 0.25     # giá bỏ một câu; đặt cao thì căn ép, thấp thì bỏ nhiều


def _load_splitters():
    """Mượn `split_zh`/`split_vi` của bộ căn cũ — cùng cách tách câu thì mới so được số liệu."""
    spec = importlib.util.spec_from_file_location(
        "align_old", HERE / "24_align_epub_anchor.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["align_old"] = module
    try:
        spec.loader.exec_module(module)
    except Exception:                       # noqa: BLE001 - bộ cũ cần ctranslate2 + đường dẫn box
        import re
        zh = re.compile(r"[^。！？!?…]*[。！？!?…]+|[^。！？!?…]+")
        vi = re.compile(r"[^.!?…]*[.!?…]+|[^.!?…]+")
        def split_zh(text):
            return [m.group(0).strip() for line in text.split("\n") if line.strip()
                    for m in zh.finditer(line) if m.group(0).strip()]
        def split_vi(text):
            return [m.group(0).strip() for line in text.split("\n") if line.strip()
                    for m in vi.finditer(line) if len(m.group(0).strip()) > 1]
        return split_zh, split_vi
    return module.split_zh, module.split_vi


_split_zh_raw, _split_vi_raw = _load_splitters()
_CLOSERS = set("”』」』）)〕】》›»\"' 　")


def _merge_orphans(parts: list[str]) -> list[str]:
    """Gộp mảnh chỉ gồm dấu ĐÓNG vào câu trước.

    Bộ tách kế thừa cắt ở `。` kể cả khi nó nằm trong ngoặc kép:
    `开口说道：“你来了。”` → `['开口说道：“你来了。', '”']`. Bộ căn cũ chạy vài chục chương nên
    không lộ; ở 162k chương thì mỗi lời thoại đẻ ra một mảnh rác một ký tự, vừa phá căn vừa
    lọt vào data train.
    """
    out: list[str] = []
    for part in parts:
        if out and part and all(c in _CLOSERS for c in part):
            out[-1] += part
        else:
            out.append(part)
    return out


def split_zh(text: str) -> list[str]:
    return _merge_orphans(_split_zh_raw(text))


def split_vi(text: str) -> list[str]:
    return _merge_orphans(_split_vi_raw(text))


def align(sim, n: int, m: int, min_score: float, base: float) -> list[tuple]:
    """DP đơn điệu 1-1 / 1-2 / 2-1, cho phép bỏ câu. `sim(i, ni, j, nj)` trả điểm một nhịp.

    Bê nguyên từ `24_align_epub_anchor.align`, chỉ tách hàm tính điểm ra ngoài để thay LaBSE.
    """
    neg = -1e9
    dp = [[neg] * (m + 1) for _ in range(n + 1)]
    back: list[list] = [[None] * (m + 1) for _ in range(n + 1)]
    dp[0][0] = 0.0
    for i in range(n + 1):
        for j in range(m + 1):
            if dp[i][j] == neg or abs(i * m - j * n) > BAND * max(n, m) * max(n, m):
                continue
            for di, dj in ((1, 1), (1, 2), (2, 1), (1, 0), (0, 1)):
                ni, nj = i + di, j + dj
                if ni > n or nj > m:
                    continue
                if di == 0 or dj == 0:
                    gain = -SKIP_COST
                else:
                    raw = sim(i, ni, j, nj)
                    gain = (raw - base) if raw >= min_score else -SKIP_COST * 2
                if dp[i][j] + gain > dp[ni][nj]:
                    dp[ni][nj] = dp[i][j] + gain
                    back[ni][nj] = (i, j, gain)
    i, j, out = n, m, []
    while (i, j) != (0, 0):
        step = back[i][j]
        if step is None:
            break
        pi, pj, gain = step
        if pi < i and pj < j and gain > 0:
            out.append((slice(pi, i), slice(pj, j), gain + base))
        i, j = pi, pj
    return out[::-1]


def make_sim(zh_vecs, vi_vecs):
    """Điểm một nhịp = cosine giữa TRUNG BÌNH vector hai vế (vector đã chuẩn hoá)."""
    import numpy as np

    def sim(i, ni, j, nj):
        a = zh_vecs[i:ni].mean(axis=0)
        b = vi_vecs[j:nj].mean(axis=0)
        denominator = float(np.linalg.norm(a) * np.linalg.norm(b)) or 1.0
        return float(a @ b) / denominator

    return sim


def load_model(device: str | None):
    import torch
    from sentence_transformers import SentenceTransformer

    device = device or ("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Nạp {MODEL} trên {device}", flush=True)
    model = SentenceTransformer(MODEL, device=device)
    if device == "cuda":
        model = model.half()
    model.eval()
    return model


def iter_chapters(path: Path, per_novel: int):
    """Nhả cặp chương, giới hạn `per_novel` chương mỗi truyện — ĐA DẠNG hơn là ĐÀO SÂU."""
    seen: dict[str, int] = {}
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            row = json.loads(line)
            count = seen.get(row["novel"], 0)
            if per_novel and count >= per_novel:
                continue
            seen[row["novel"]] = count + 1
            yield row


def run(args) -> None:
    model = load_model(args.device)
    kept = chapters = 0
    scores: list[float] = []
    out = None if args.calibrate else Path(args.out).open("w", encoding="utf-8")
    try:
        for row in iter_chapters(Path(args.paired), args.chapters):
            zh_lines = split_zh(row["zh"])[:args.max_lines]
            vi_lines = split_vi(row["vi"])[:args.max_lines]
            if len(zh_lines) < 5 or len(vi_lines) < 5:
                continue
            chapters += 1
            vectors = model.encode(zh_lines + vi_lines, batch_size=args.batch,
                                   convert_to_numpy=True, normalize_embeddings=True,
                                   show_progress_bar=False)
            zh_vecs, vi_vecs = vectors[:len(zh_lines)], vectors[len(zh_lines):]
            pairs = align(make_sim(zh_vecs, vi_vecs), len(zh_lines), len(vi_lines),
                          args.min_score, args.base)
            for zs, vs, score in pairs:
                scores.append(score)
                if out is not None and score >= args.min_score:
                    out.write(json.dumps({
                        "zh": " ".join(zh_lines[zs]), "vi": " ".join(vi_lines[vs]),
                        "labse": round(score, 4), "novel": row["novel"],
                        "index": row["index"]}, ensure_ascii=False) + "\n")
                    kept += 1
            if chapters % 500 == 0:
                print(f"  {chapters:,} chương · {kept:,} cặp câu", flush=True)
            if args.calibrate and chapters >= args.calibrate_chapters:
                break
    finally:
        if out is not None:
            out.close()

    scores.sort()
    if scores:
        print(f"\n{chapters:,} chương · {len(scores):,} nhịp căn được")
        for pct in (5, 10, 25, 50, 75, 90):
            print(f"  phân vị {pct:>2}%: {scores[int(len(scores) * pct / 100)]:.3f}")
        for cut in (0.55, 0.60, 0.65, 0.70, 0.75):
            rate = sum(1 for s in scores if s >= cut) / len(scores)
            print(f"  ngưỡng {cut:.2f} → giữ {rate:.0%}")
    if not args.calibrate:
        print(f"→ {args.out}  ·  {kept:,} cặp câu")


def kaggle_setup(args) -> None:
    subprocess.call([sys.executable, "-m", "pip", "-q", "install", "-U",
                     "sentence-transformers"])
    if not Path(args.paired).exists():
        for root, _dirs, files in os.walk("/kaggle/input"):
            for name in files:
                if name.startswith("paired") and name.endswith(".jsonl"):
                    args.paired = Path(root) / name
                    break
    args.out = Path("/kaggle/working/anchor_labse.jsonl")
    print(f"paired = {args.paired}\nout = {args.out}", flush=True)


def _self_check() -> None:
    # Mảnh chỉ có dấu đóng phải được gộp lại, không để lọt câu một ký tự.
    assert split_zh("他走进房间。开口说道：“你来了。”") == ["他走进房间。", "开口说道：“你来了。”"]
    assert _merge_orphans(["a。", "”", "b。"]) == ["a。”", "b。"]
    assert _merge_orphans(["”"]) == ["”"]      # không có câu trước thì giữ nguyên
    assert len(split_vi("Hắn bước vào phòng. Mở miệng nói.")) == 2

    # DP: ma trận điểm dựng tay, đường căn đúng phải là đường chéo.
    table = [[0.9, 0.1, 0.1], [0.1, 0.9, 0.1], [0.1, 0.1, 0.9]]
    def sim(i, ni, j, nj):
        return sum(table[a][b] for a in range(i, ni) for b in range(j, nj)) / ((ni - i) * (nj - j))
    got = align(sim, 3, 3, 0.5, 0.5)
    assert [(z.start, v.start) for z, v, _ in got] == [(0, 0), (1, 1), (2, 2)], got

    # Nhịp 1-2: câu Trung thứ 2 ứng với HAI câu Việt.
    table2 = [[0.9, 0.1, 0.1], [0.1, 0.8, 0.8]]
    def sim2(i, ni, j, nj):
        return sum(table2[a][b] for a in range(i, ni) for b in range(j, nj)) / ((ni - i) * (nj - j))
    got2 = align(sim2, 2, 3, 0.5, 0.5)
    assert (got2[-1][0].stop - got2[-1][0].start, got2[-1][1].stop - got2[-1][1].start) == (1, 2), got2

    import numpy as np
    zh = np.array([[1.0, 0.0], [0.0, 1.0]])
    vi = np.array([[1.0, 0.0], [0.0, 1.0]])
    sim3 = make_sim(zh, vi)
    assert abs(sim3(0, 1, 0, 1) - 1.0) < 1e-6
    assert abs(sim3(0, 1, 1, 2) - 0.0) < 1e-6
    print("34_align_labse OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--paired", type=Path,
                    default=Path.home() / "hachimi-work/scratch/paired_clean.jsonl")
    ap.add_argument("--out", type=Path,
                    default=Path.home() / "hachimi-work/scratch/anchor_labse.jsonl")
    ap.add_argument("--chapters", type=int, default=40,
                    help="trần chương mỗi truyện — đa dạng giọng đáng hơn đào sâu một truyện")
    ap.add_argument("--max-lines", type=int, default=400)
    ap.add_argument("--batch", type=int, default=256)
    ap.add_argument("--min-score", type=float, default=0.60)
    ap.add_argument("--base", type=float, default=0.55, help="điểm hoà vốn của một nhịp")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--calibrate-chapters", type=int, default=300)
    ap.add_argument("--device")
    ap.add_argument("--kaggle", action="store_true")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return
    if args.kaggle:
        kaggle_setup(args)
    run(args)


if __name__ == "__main__":
    main()
