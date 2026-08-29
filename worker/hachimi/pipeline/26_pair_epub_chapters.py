"""Ghép chương Trung vừa tải với đúng chương trong epub dịch tay → đầu vào cho bước căn câu.

Chạy Ở MÁY DEV (nơi có file zip 43,6GB). Đầu vào:
  - zh_raw.jsonl  : do pipeline/25 tải về từ box
  - match_ids.json: [{novel_id, file}] — bản đồ truyện ↔ epub, do bước sàng kho dựng

Hai cửa lọc bắt buộc, thiếu là data bẩn:
  1. epub đánh số chương LỆCH DB (có quyển/phiên ngoại) → chương cùng số chưa chắc cùng nội dung.
  2. Bản epub phải đạt chuẩn dịch tay ở CẤP CHƯƠNG (mật độ hư từ ≥14/1k), không chỉ cấp sách.

Cửa "cùng nội dung" (chrF giữa bản dịch máy và bản epub) làm ở bước sau, trên box có Hachimi.
"""
from __future__ import annotations

import argparse
import html
import io
import json
import re
import zipfile
from pathlib import Path

TAG = re.compile(r"<[^>]+>")
JUNK = re.compile(r"^(Nguồn:|Converter|Nguồn truyện|Edit:|Beta:|Convert:).*$", re.M)
CHAP_HEAD = re.compile(r"^Chương\s+\d+[:.]?.*$", re.M)
FUNC = re.compile(r"\b(bởi vì|cho nên|tuy nhiên|nhưng mà|mà còn|đến mức|chả trách|thì ra|"
                  r"vì thế|do đó|nếu như|trong khi|sau khi|trước khi|của|rằng|để|khiến cho|"
                  r"không những|vẫn còn|hình như|dường như|có vẻ|thế nhưng|vậy mà)\b", re.I)
FUNC_MIN = 14.0          # convert 4-6/1k · dịch tay 17-22/1k · mốc kaihe 18,5


def chapter_text(epub_bytes: bytes, index: int) -> str:
    e = zipfile.ZipFile(io.BytesIO(epub_bytes))
    names = set(e.namelist())
    for cand in (f"OEBPS/chapter_{index}.xhtml", f"OEBPS/chapter_{index}.html",
                 f"chapter_{index}.xhtml"):
        if cand in names:
            raw = e.read(cand).decode("utf-8", "ignore")
            lines = [l.strip() for l in re.sub(r"\n{2,}", "\n", html.unescape(TAG.sub("\n", raw))
                                               ).split("\n") if l.strip()]
            while len(lines) > 1 and lines[0] == lines[1]:      # tiêu đề lặp hai lần
                lines = lines[1:]
            return "\n".join(lines)
    return ""


def func_density(vi: str) -> float:
    return len(FUNC.findall(vi)) / max(1, len(vi.split())) * 1000


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("zh_raw", type=Path)
    ap.add_argument("match_ids", type=Path)
    ap.add_argument("zip_path", type=Path)
    ap.add_argument("out", type=Path)
    args = ap.parse_args()

    by_id: dict[int, str] = {}
    for m in json.loads(args.match_ids.read_text(encoding="utf-8")):
        by_id.setdefault(int(m["novel_id"]), m["file"])
    z = zipfile.ZipFile(args.zip_path)
    paths = {n.split("/")[-1]: n for n in z.namelist() if n.endswith(".epub")}
    cache: dict[str, bytes] = {}

    n_in = n_out = n_nofile = n_nochap = n_convert = n_ratio = 0
    with args.out.open("w", encoding="utf-8") as fo:
        for line in args.zh_raw.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            n_in += 1
            f = by_id.get(r["novel_id"])
            if not f or f not in paths:
                n_nofile += 1
                continue
            if f not in cache:
                cache[f] = z.read(paths[f])
            vi = chapter_text(cache[f], r["chapter_index"])
            if not vi:
                n_nochap += 1
                continue
            vi = CHAP_HEAD.sub("", JUNK.sub("", vi), count=1).strip()
            if len(vi) < 500:
                n_nochap += 1
                continue
            dens = func_density(vi)
            if dens < FUNC_MIN:
                n_convert += 1
                continue
            # Bản dịch tiếng Việt dài gấp ~3,3 lần nguồn Trung; lệch xa nghĩa là ghép nhầm.
            if not 0.4 < len(vi) / max(1, len(r["zh"])) / 3.3 < 2.0:
                n_ratio += 1
                continue
            fo.write(json.dumps({**r, "vi_human": vi, "epub": f, "func": round(dens, 1)},
                                ensure_ascii=False) + "\n")
            n_out += 1
    print(f"vào {n_in} chương Trung → ghép được {n_out}")
    print(f"  bỏ: không có epub {n_nofile} · epub thiếu chương {n_nochap} · "
          f"bản convert {n_convert} · tỉ lệ độ dài lệch {n_ratio}")


if __name__ == "__main__":
    main()
