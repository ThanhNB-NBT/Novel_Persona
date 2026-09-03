"""Ghép CHƯƠNG: nguyên tác Trung (CNovels) ↔ bản dịch người (epub trên đĩa).

Đứng giữa `31_fetch_cnovels.py` (tải vế Trung) và bước căn câu. Ra file jsonl mỗi dòng một
CẶP CHƯƠNG `{novel, index, zh, vi}` — đúng dạng `24_align_epub_anchor` nhận.

    python 32_pair_novel_chapters.py --chapters 100 --out ~/hachimi-work/scratch/paired.jsonl
    python 32_pair_novel_chapters.py --self-check

Bốn thứ đã đo trước khi viết, đừng phát minh lại:

1. **File Trung mã GB18030**, không phải UTF-8. Đọc bằng UTF-8 ra mojibake và dễ tưởng file
   hỏng (đã dính 30/08).
2. **Epub đánh số chương ngay trong tên file** (`OEBPS/chapter_46.xhtml`) nên ghép theo SỐ,
   không phải theo thứ tự — epub hay có lời tựa/phiên ngoại chen vào.
3. **Tiêu đề chương trong epub lặp HAI lần**, và có dòng `Nguồn:` là chú thích của trang dịch
   chứ không phải nội dung. Phải bỏ cả hai.
4. **~10% truyện Trung bắt được 0 chương** nếu chỉ nhận `第N章`. Có nhiều kiểu đánh số khác,
   nên `CHAPTER_PATTERNS` gom vài dạng; truyện nào vẫn 0 chương thì bỏ, đừng đoán.

⚠ Ghép theo SỐ CHƯƠNG là ghép THÔ. Hai bản thường lệch nhau vì bản dịch bỏ chương, gộp chương,
hoặc epub có quyển. Cổng lọc thật (chrF giữa bản dịch máy của chương Trung và chương Việt,
ngưỡng ≥50 — đo thật 55/82 cặp đạt) nằm ở bước sau; ở đây chỉ dựng ứng viên.
"""
from __future__ import annotations

import argparse
import html
import io
import json
import re
import sys
import unicodedata
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))   # worker/ — nơi có novelworker

EPUB_ZIP = Path("/home/thanhnb/code/Novel_Project/novel/output_epubs.zip")
# Dạng tiêu đề chương bên Trung. Xếp từ chặt tới lỏng; dùng dạng đầu tiên bắt được ≥5 chương.
CHAPTER_PATTERNS = [
    re.compile(r"^[ \t]*第\s*([零一二三四五六七八九十百千万两0-9]+)\s*[章节][^\n]{0,40}$", re.MULTILINE),
    re.compile(r"^[ \t]*正文\s*第\s*([零一二三四五六七八九十百千万两0-9]+)\s*[章节][^\n]{0,40}$", re.MULTILINE),
    re.compile(r"^[ \t]*(?:Chapter|CHAPTER)\s*([0-9]+)[^\n]{0,40}$", re.MULTILINE),
]
EPUB_CHAPTER = re.compile(r"chapter[_-]?(\d+)\.x?html?$", re.IGNORECASE)
TAG = re.compile(r"<[^>]+>")
SOURCE_LINE = re.compile(r"^\s*(?:Nguồn|Nguồn:|Source)\s*:?\s*$", re.IGNORECASE)
_CN_NUM = {c: i for i, c in enumerate("零一二三四五六七八九")}
_CN_UNIT = {"十": 10, "百": 100, "千": 1000}


def cn_int(text: str) -> int | None:
    """`第一百二十三章` → 123. Trả None nếu không đọc nổi — không đoán bừa."""
    text = text.strip()
    if text.isdigit():
        return int(text)
    total = section = 0
    for char in text:
        if char in _CN_NUM:
            section = _CN_NUM[char]
        elif char in _CN_UNIT:          # 十/百/千: CỘNG vào tổng, không nhân dồn vào section
            total += (section or 1) * _CN_UNIT[char]
            section = 0
        elif char == "万":              # 万 nhân TẤT CẢ những gì đứng trước
            total = (total + section) * 10000
            section = 0
        else:
            return None
    return (total + section) or None


def split_chinese(raw: str) -> dict[int, str]:
    """Văn bản một truyện → {số chương: nội dung}. Chọn dạng tiêu đề bắt được nhiều nhất."""
    best: list = []
    for pattern in CHAPTER_PATTERNS:
        found = list(pattern.finditer(raw))
        if len(found) > len(best):
            best = found
    if len(best) < 5:
        return {}
    out: dict[int, str] = {}
    for index, match in enumerate(best):
        number = cn_int(match.group(1))
        if number is None or number in out:
            continue
        end = best[index + 1].start() if index + 1 < len(best) else len(raw)
        body = raw[match.end():end].strip()
        if len(body) >= 300:
            out[number] = body
    return out


def clean_epub_html(raw: str) -> str:
    """HTML một chương epub → văn bản. Bỏ tiêu đề lặp và dòng `Nguồn:` của trang dịch."""
    text = html.unescape(TAG.sub("\n", raw))
    lines = [line.strip() for line in text.split("\n") if line.strip()]
    kept: list[str] = []
    for line in lines:
        if SOURCE_LINE.match(line):
            continue
        if kept and line == kept[-1]:      # tiêu đề chương bị lặp ngay sau chính nó
            continue
        kept.append(line)
    return "\n".join(kept)


def split_epub(blob: bytes) -> dict[int, str]:
    """Epub → {số chương: nội dung}. Số lấy từ TÊN FILE, không phải thứ tự."""
    book = zipfile.ZipFile(io.BytesIO(blob))
    out: dict[int, str] = {}
    for name in book.namelist():
        match = EPUB_CHAPTER.search(name)
        if not match:
            continue
        body = clean_epub_html(book.read(name).decode("utf-8", "replace"))
        if len(body) >= 200:
            out[int(match.group(1))] = body
    return out


def norm(text: str) -> str:
    text = unicodedata.normalize("NFC", text or "").lower()
    return re.sub(r"[^0-9a-zà-ỹ]+", " ", text).strip()


def run(args) -> None:
    zf = zipfile.ZipFile(EPUB_ZIP)
    epubs: dict[str, str] = {}
    for name in zf.namelist():
        if name.lower().endswith(".epub"):
            epubs.setdefault(norm(Path(name).stem.split(" - ")[0]), name)

    files = sorted(Path(args.cnovels).glob("*.txt"))
    print(f"{len(files):,} truyện Trung · {len(epubs):,} tên epub", flush=True)
    stats = {"novels": 0, "no_zh_chapters": 0, "no_epub": 0, "pairs": 0, "novels_used": 0}
    with Path(args.out).open("w", encoding="utf-8") as out:
        for order, path in enumerate(files, 1):
            stats["novels"] += 1
            key = path.stem.replace("_", " ")
            epub_name = epubs.get(key)
            if not epub_name:
                stats["no_epub"] += 1
                continue
            zh_map = split_chinese(path.read_bytes().decode("gb18030", "replace"))
            if not zh_map:
                stats["no_zh_chapters"] += 1
                continue
            with zf.open(epub_name) as handle:
                vi_map = split_epub(handle.read())
            shared = sorted(set(zh_map) & set(vi_map))[:args.chapters]
            if not shared:
                continue
            stats["novels_used"] += 1
            out.writelines(json.dumps({"novel": key, "index": number,
                                      "zh": zh_map[number], "vi": vi_map[number]},
                                     ensure_ascii=False) + "\n" for number in shared)
            stats["pairs"] += len(shared)
            if order % 100 == 0:
                print(f"  {order}/{len(files)} · {stats['pairs']:,} cặp chương", flush=True)
    print(json.dumps(stats, ensure_ascii=False, indent=2))
    print(f"→ {args.out}")


def _self_check() -> None:
    assert cn_int("三") == 3 and cn_int("十") == 10 and cn_int("十五") == 15
    assert cn_int("二十") == 20 and cn_int("九十九") == 99
    assert cn_int("123") == 123 and cn_int("abc") is None
    # Hàng trăm trở lên — bản đầu tại hạ viết sai ở đây mà test cũ chỉ thử tới 99 nên lọt.
    assert cn_int("一百") == 100, cn_int("一百")
    assert cn_int("一百二十三") == 123, cn_int("一百二十三")
    assert cn_int("二百零五") == 205, cn_int("二百零五")
    assert cn_int("一千") == 1000 and cn_int("一千零一") == 1001
    assert cn_int("三千五百") == 3500, cn_int("三千五百")
    assert cn_int("一万") == 10000 and cn_int("一万零八") == 10008

    body = "x" * 400
    raw = "\n".join(f"第{n}章 tiêu đề\n{body}" for n in range(1, 8))
    got = split_chinese(raw)
    assert sorted(got) == list(range(1, 8)), sorted(got)
    assert got[3].startswith("x") and len(got[3]) >= 300
    # Dưới 5 chương thì coi như không nhận dạng được, trả rỗng thay vì đoán.
    assert split_chinese("第1章 a\n" + body) == {}

    # Epub: bỏ tiêu đề lặp và dòng Nguồn:
    dirty = "<h1>Chương 46: Tên</h1><p>Chương 46: Tên</p><p>Nguồn:</p><p>Nội dung thật.</p>"
    assert clean_epub_html(dirty).split("\n") == ["Chương 46: Tên", "Nội dung thật."]
    # Số chương lấy từ tên file, không phải thứ tự.
    assert EPUB_CHAPTER.search("OEBPS/chapter_46.xhtml").group(1) == "46"
    assert EPUB_CHAPTER.search("OEBPS/chapter-7.html").group(1) == "7"
    assert EPUB_CHAPTER.search("OEBPS/cover.xhtml") is None
    print("32_pair_novel_chapters OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cnovels", type=Path, default=Path.home() / "hachimi-work/cnovels")
    ap.add_argument("--out", type=Path, default=Path.home() / "hachimi-work/scratch/paired.jsonl")
    ap.add_argument("--chapters", type=int, default=100,
                    help="trần số chương mỗi truyện — căn dư rồi cắt sau còn hơn phải căn lại")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return
    run(args)


if __name__ == "__main__":
    main()
