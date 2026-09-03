"""Dựng lại `data/poem_vi.jsonl` từ 33.699 bài thơ Gemini, thay bộ gemma cũ.

Bộ gemma cũ (3.228 bài, trong đó 118 dòng chỉ có `error` 502) **phiên âm thô 32,4%** — tức
data đang dạy model đúng cái lỗi trục thơ đang yếu. Bộ mới sinh qua Antigravity (mục A2/A3
`ban-giao-2026-08-30-chieu.md`), đo lại còn **2,2%** — **tốt hơn ~14 lần**, đúng như bản bàn
giao ghi (33,7% → 2,4%).

ĐỊNH DẠNG: lô ra của Gemini dùng `" / "` ngăn CÂU (mỗi câu 2 vế, ngăn nhau bằng dấu phẩy),
còn `27_make_pack_v6.gate_poem` đòi **mỗi VẾ một dòng** như bộ cũ. Nên đổi
`" / "` → xuống dòng và `", "` → xuống dòng. Đo: 99,8% bài khớp số vế sau khi đổi.

    python 36_build_poem_booster.py            # ghi đè data/poem_vi.jsonl, backup bản cũ
    python 36_build_poem_booster.py --self-check
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(HERE.parents[0]))          # worker/ để import novelworker
from text_clean import clean_source

_SPEC = importlib.util.spec_from_file_location(
    "pack_v6", Path(__file__).resolve().parent / "27_make_pack_v6.py")
_M = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_M)

_WORD = re.compile(r"[a-zà-ỹđ]+", re.IGNORECASE)
# Ngưỡng 0,44 tính trên CẢ BÀI — đây là thước đã hiệu chuẩn của dự án, đừng tự đổi:
# chỉnh cho bộ gemma cũ ra đúng 33,7% như bản bàn giao 30/08 ghi (chạy lại 01/09: 32,4%).
# Đổi đơn vị sang "theo vế" hay đổi ngưỡng sang 0,5 thì bộ đối chứng VẪN ra ~35% (trông như
# vẫn khớp) nhưng bộ mới nhảy 2,2% → 7,4%, tức kết luận đảo từ "tốt hơn 14 lần" thành "4,7
# lần". Khớp bộ đối chứng ở MỘT điểm không chứng minh cả cái thước đúng.
RAW_THRESHOLD = 0.44


def to_lines(text: str) -> str:
    """`" / "` ngăn câu, `", "` ngăn vế → mỗi vế một dòng (quy ước của bộ booster cũ).

    GIỮ dấu phẩy ở cuối vế trước (`", "` → `",\\n"`, không phải `"\\n"`): bộ cũ viết
    `"...trái ân quân,\\nĐành cam..."`. Bỏ phẩy là dạy model xuống dòng trần, lệch hẳn cách
    trình bày thơ mà chính data này đang dùng để dạy.
    """
    return text.replace(" / ", "\n").replace(", ", ",\n")


def load_batches(dirs: list[Path]) -> list[dict]:
    """Ghép `in_XXX` ↔ `out_XXX` theo lô — `n` đánh lại từ 1 ở MỖI lô, không phải toàn cục."""
    rows: list[dict] = []
    for folder in dirs:
        for src_path in sorted(folder.glob("in_*.jsonl")):
            out_path = src_path.with_name(src_path.name.replace("in_", "out_", 1))
            if not out_path.exists():
                continue
            src = {o["n"]: o for o in _read(src_path)}
            tgt = {o["n"]: o for o in _read(out_path)}
            for n in sorted(src):
                vi = (tgt.get(n) or {}).get("vi") or ""
                if not vi.strip():
                    continue
                rows.append({"title": src[n].get("title", ""),
                             "zh": to_lines(src[n]["zh"]),
                             "vi": to_lines(vi)})
    return rows


def _read(path: Path) -> list[dict]:
    return [json.loads(l) for l in path.open(encoding="utf-8") if l.strip()]


def _hv_readings(zh: str, table: dict) -> set[str]:
    out: set[str] = set()
    for ch in zh:
        for reading in table.get(ch) or ():
            out.add(reading.lower())
    return out


def raw_translit_rate(rows: list[dict], threshold: float = RAW_THRESHOLD) -> tuple[int, int]:
    """(số BÀI phiên âm thô, tổng bài chấm được) — đơn vị là BÀI, xem `RAW_THRESHOLD`.

    Đếm tỉ lệ âm trong bản dịch trùng phiên âm Hán-Việt của chính bài nguồn. Cao = dịch thô
    kiểu "convert".

    ⚠ Luôn chạy kèm bộ ĐỐI CHỨNG đã biết tính nết (`data/poem_vi.gemma.jsonl` ≈ 32-34%) — số
    đẹp mà không có đối chứng thì không biết là data tốt hay thước hỏng.
    """
    from novelworker.translator import hanviet

    table = hanviet._load()
    raw = total = 0
    for row in rows:
        if not row.get("vi"):
            continue
        tokens = [w.lower() for w in _WORD.findall(row["vi"])]
        if not tokens:
            continue
        total += 1
        readings = _hv_readings(row["zh"], table)
        if sum(1 for t in tokens if t in readings) / len(tokens) >= threshold:
            raw += 1
    return raw, total


def build(args) -> dict:
    rows = load_batches([Path(d) for d in args.batch])
    stats = {"pairs_in": len(rows)}

    blocked: set[str] = set()
    for path in args.block:
        if Path(path).exists():
            for row in _read(Path(path)):
                if row.get("zh"):
                    blocked.add(clean_source(row["zh"]))
    stats["blocked_sources"] = len(blocked)

    good: list[dict] = []
    seen: set[str] = set()
    stats.update(gate_fail=0, dup=0, blocked_hit=0)
    for row in rows:
        key = clean_source(row["zh"])
        if not _M.gate_poem(row):
            stats["gate_fail"] += 1
            continue
        if key in blocked:
            stats["blocked_hit"] += 1
            continue
        if key in seen:
            stats["dup"] += 1
            continue
        seen.add(key)
        good.append(row)
    stats["rows"] = len(good)

    raw, total = raw_translit_rate(good)
    stats["raw_translit"] = {"raw": raw, "poems": total,
                             "pct": round(raw / max(1, total) * 100, 1)}

    out = Path(args.out)
    backup = out.with_suffix(".gemma.jsonl")
    # CHỈ backup khi chưa có: chạy lần hai mà vẫn copy là đè bản gemma — mất luôn bộ ĐỐI CHỨNG
    # của thước phiên âm thô, thứ không dựng lại được.
    if out.exists() and not args.no_backup and not backup.exists():
        shutil.copy2(out, backup)
        stats["backup"] = str(backup)
    if backup.exists() and not args.no_backup:
        # Đọc từ BACKUP, không phải `out`: lần đầu thì hai cái như nhau, nhưng chạy lại lần
        # hai `out` đã là bộ mới ⇒ đo nhầm chính nó, ra "bộ cũ 2,2%".
        old = [r for r in _read(backup) if r.get("vi")]
        raw_o, total_o = raw_translit_rate(old)
        stats["raw_translit_old"] = {"rows": len(old), "raw": raw_o, "poems": total_o,
                                     "pct": round(raw_o / max(1, total_o) * 100, 1)}
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as fh:
        for row in good:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")
    stats["out"] = str(out)
    Path(str(out) + ".manifest.json").write_text(
        json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    return stats


def _self_check() -> None:
    import tempfile

    assert to_lines("甲，乙。 / 丙，丁。") == "甲，乙。\n丙，丁。"
    assert to_lines("Giáp, Ất. / Bính, Đinh.") == "Giáp,\nẤt.\nBính,\nĐinh."

    # Đối chứng cho thước: bản phiên âm thô phải ăn điểm CAO hơn hẳn bản dịch nghĩa.
    tho = [{"zh": "山高，水长", "vi": "sơn cao\nthủy trường"}]
    nghia = [{"zh": "山高，水长", "vi": "núi vươn\nsông dài"}]
    assert raw_translit_rate(tho) == (1, 1), raw_translit_rate(tho)
    assert raw_translit_rate(nghia) == (0, 1), raw_translit_rate(nghia)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        batch = tmp / "b"
        batch.mkdir()
        (batch / "in_000.jsonl").write_text(json.dumps(
            {"n": 1, "zh": "一顷含秋绿，森风十万竿。 / 气吹朱夏转，声扫碧霄寒。"},
            ensure_ascii=False), encoding="utf-8")
        (batch / "out_000.jsonl").write_text(json.dumps(
            {"n": 1, "vi": "Một khoảnh mang thu biếc, Gió luồn vạn trúc xanh. / "
                           "Khí xua mùa hạ cháy, Tiếng quét ngút trời thanh."},
            ensure_ascii=False), encoding="utf-8")
        out = tmp / "poem_vi.jsonl"
        stats = build(argparse.Namespace(batch=[batch], out=out, block=[], no_backup=True))
        assert stats["rows"] == 1, stats
        row = _read(out)[0]
        assert row["vi"].count("\n") == 3, row       # 4 vế = 3 lần xuống dòng
        print("self-check OK:", json.dumps(
            {k: stats[k] for k in ("pairs_in", "rows", "gate_fail")}, ensure_ascii=False))


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", action="append", type=Path, default=None,
                    help="thư mục lô, lặp lại được (mặc định: poem_batch + poem_batch2)")
    ap.add_argument("--out", type=Path, default=HERE / "data/poem_vi.jsonl")
    ap.add_argument("--block", action="append", type=Path,
                    default=[Path.home() / "hachimi-work/eval_poem_locked.jsonl"],
                    help="jsonl eval cần chặn khỏi booster")
    ap.add_argument("--no-backup", action="store_true")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)

    if args.self_check:
        _self_check()
        return
    if not args.batch:
        scratch = Path.home() / "hachimi-work/scratch"
        args.batch = [scratch / "poem_batch", scratch / "poem_batch2"]
    print(json.dumps(build(args), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
