"""Tầng 1: sàng kho epub — bản nào là convert máy, bản nào là dịch tay.

Đọc thẳng trong zip (không giải nén 43GB). Mỗi epub chỉ lấy ~40KB text ở GIỮA sách
(đầu sách hay là lời tựa/mục lục, không đại diện văn dịch).
"""
from __future__ import annotations
import html, io, json, random, re, sys, time, zipfile
from pathlib import Path

sys.path.insert(0, "/home/thanhnb/code/Novel_Project/worker")
from novelworker.translator import lint

ZIP = Path("/home/thanhnb/code/Novel_Project/novel/output_epubs.zip")
OUT = Path(__file__).parent / "scan_epub.jsonl"
TAG = re.compile(r"<[^>]+>")
HAN = re.compile(r"[一-鿿]")
PINYIN = re.compile(r"[āēīōūǖǎěǐǒǔǘǚǜ]")
# Dấu văn convert — cụm chỉ sinh ra khi dịch máy theo chữ, người dịch không viết vậy.
CONVERT = re.compile(
    r"\b(một cái|không khỏi|căn bản là|rốt cuộc là|trên thực tế|tổng cảm thấy|"
    r"đối với .{1,25} tới nói|thế nhưng là|chính mình|nói giỡn|có thể nói là)\b", re.I)
MODERN = re.compile(r"\b(tôi|anh ấy|cô ấy|anh ta|cô ta|cậu ấy)\b", re.I)
# Hư từ/liên từ tiếng Việt: người dịch PHẢI thêm vào vì tiếng Trung lược chúng; máy
# convert thì bỏ qua. Đo được 29/08: convert 4-6/1k, dịch tay 17-22/1k, mốc kaihe 18,5.
FUNC = re.compile(r"\b(bởi vì|cho nên|tuy nhiên|nhưng mà|mà còn|đến mức|chả trách|thì ra|"
                  r"vì thế|do đó|nếu như|trong khi|sau khi|trước khi|của|rằng|để|khiến cho|"
                  r"không những|vẫn còn|hình như|dường như|có vẻ|thế nhưng|vậy mà)\b", re.I)
# Sở hữu ngược kiểu Trung ('ngươi chân thân') — người Việt viết 'chân thân của ngươi'.
POSS = re.compile(r"\b(ta|ngươi|hắn|nàng|mình|bọn hắn|các ngươi)\s+"
                  r"(chân thân|tâm cảnh|bộ dáng|thân thể|trong lòng|trên người|khuôn mặt|"
                  r"ánh mắt|thanh âm|thần sắc|lời nói|đôi mắt)\b", re.I)
OLD = re.compile(r"\b(ta|ngươi|hắn|nàng|y|tại hạ|các hạ)\b", re.I)


def text_of(epub_bytes: bytes, budget: int = 40_000) -> str:
    try:
        z = zipfile.ZipFile(io.BytesIO(epub_bytes))
    except Exception:
        return ""
    names = [n for n in z.namelist() if n.lower().endswith((".xhtml", ".html", ".htm"))]
    if not names:
        return ""
    names.sort()
    mid = names[len(names) // 3: len(names) // 3 + 40]  # giữa sách, bỏ tựa/mục lục
    out: list[str] = []
    size = 0
    for n in mid:
        try:
            raw = z.read(n).decode("utf-8", "ignore")
        except Exception:
            continue
        txt = html.unescape(TAG.sub("\n", raw))
        txt = re.sub(r"\n{2,}", "\n", txt).strip()
        out.append(txt)
        size += len(txt)
        if size >= budget:
            break
    return "\n".join(out)[:budget]


def score(txt: str) -> dict:
    words = max(1, len(txt.split()))
    old, modern = len(OLD.findall(txt)), len(MODERN.findall(txt))
    return {
        "chars": len(txt),
        "convert_per_1k": round(len(CONVERT.findall(txt)) / words * 1000, 2),
        "han": len(HAN.findall(txt)),
        "pinyin": len(PINYIN.findall(txt)),
        "lint_per_1k": round(lint.lint_score(None, txt) / words * 1000, 2),
        "old_ratio": round(old / max(1, old + modern), 2),
        "func_per_1k": round(len(FUNC.findall(txt)) / words * 1000, 1),
        "poss_per_10k": round(len(POSS.findall(txt)) / words * 10000, 1),
    }


def main() -> None:
    n_sample = int(sys.argv[1]) if len(sys.argv) > 1 else 600
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 20260829
    z = zipfile.ZipFile(ZIP)
    names = [n for n in z.namelist() if n.lower().endswith(".epub")]
    random.Random(seed).shuffle(names)
    picked = names[:n_sample]
    t0 = time.time()
    with OUT.open("w", encoding="utf-8") as f:
        for i, name in enumerate(picked, 1):
            base = name.split("/")[-1]
            try:
                txt = text_of(z.read(name))
            except Exception as e:
                f.write(json.dumps({"file": base, "error": str(e)[:80]}, ensure_ascii=False) + "\n")
                continue
            low = base.lower()
            rec = {"file": base,
                   "labeled_dich": any(f"{a}dịch{b}" in low or f"{a}edit{b}" in low
                                       for a, b in (("(", ")"), ("[", "]"), ("【", "】"))),
                   "labeled_convert": "convert" in low,
                   **(score(txt) if txt else {"chars": 0})}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            if i % 50 == 0:
                print(f"  {i}/{len(picked)} · {time.time()-t0:.0f}s", flush=True)
    print(f"XONG {len(picked)} epub trong {time.time()-t0:.0f}s -> {OUT}")


if __name__ == "__main__":
    main()
