"""Chấm bộ 36 chương: áp hậu xử lý production rồi so model vs bản Hachimi ĐANG PHỤC VỤ."""
import json, re, sys
from collections import defaultdict
from pathlib import Path
from novelworker.translator.worker import (
    _clean_output, _fix_register, _fix_soft_style, _hanviet_fallback)
from novelworker.translator import lint

HERE = Path(__file__).parent
HAN = re.compile(r"[一-鿿]")
MODERN = re.compile(r"\b(tôi|anh ấy|cô ấy|anh ta|cô ta|cậu ấy|mày|tao)\b", re.I)
# chữ Tây lọt (lint mù chỗ này) — bỏ qua tên Latin viết hoa, chỉ bắt từ thường ≥3 ký tự
WEST = re.compile(r"\b(?![Tt]he\b)[a-z]{3,}\b")
VI_CHARS = re.compile(r"[àáảãạăâèéẻẽẹêìíỉĩịòóỏõọôơùúủũụưỳýỷỹỵđ]", re.I)
QUOTES = (("“", "”"), ("「", "」"))

def west_words(t):
    """từ latin không dấu, không nằm trong cụm viết hoa → nghi tiếng Anh lọt"""
    bad = 0
    for line in t.split("\n"):
        for w in WEST.findall(line):
            if len(w) >= 4 and not VI_CHARS.search(w):
                bad += 1
    return bad

def paras(t):
    return len([p for p in t.split("\n") if p.strip()])

def post(vi):
    vi = _clean_output(vi)
    vi, _ = _hanviet_fallback(vi)
    return _fix_register(_fix_soft_style(vi))

chapters = {(r["novel_id"], r["chapter_index"]): r
            for r in (json.loads(l) for l in (HERE / "chapters_big.jsonl").open(encoding="utf-8"))}

agg = defaultdict(lambda: defaultdict(float))
per_novel = defaultdict(lambda: defaultdict(list))
rows = [json.loads(l) for l in (HERE / sys.argv[1]).open(encoding="utf-8")]
outdir = HERE / ("post_" + sys.argv[1].replace(".jsonl", ""))
outdir.mkdir(exist_ok=True)
n_err = 0

def stats(vi, ch, raw=None):
    return {
        "chars": len(vi), "ratio": len(vi) / max(1, len(ch["source_zh"])),
        "para_ratio": paras(vi) / max(1, paras(ch["source_zh"])),
        "han_raw": len(HAN.findall(raw)) if raw is not None else 0,
        "han": len(HAN.findall(vi)), "modern": len(MODERN.findall(vi)),
        "west": west_words(vi), "lint": lint.lint_score(ch["source_zh"], vi),
        "unbal": sum(abs(vi.count(a) - vi.count(b)) for a, b in QUOTES),
    }

for r in rows:
    ch = chapters.get((r["novel_id"], r["chapter_index"]))
    if ch is None:
        continue
    if "error" in r:
        n_err += 1
        print(f"LỖI nv{r['novel_id']} ch{r['chapter_index']}: {r['error'][:90]}")
        continue
    fin = post(r["vi"])
    (outdir / f"nv{r['novel_id']}_ch{r['chapter_index']}.txt").write_text(fin, encoding="utf-8")
    s = stats(fin, ch, r["vi"])
    h = stats(ch["hachimi_vi"], ch)
    for k in s:
        agg["model"][k] += s[k]; agg["hachimi"][k] += h[k]
    agg["model"]["n"] += 1
    agg["model"]["sec"] += r["sec"]
    for k in ("lint", "modern", "west", "han", "ratio"):
        per_novel[r["novel_id"]][k].append((s[k], h[k]))

n = agg["model"]["n"] or 1
print(f"\n=== TRUNG BÌNH TRÊN {int(n)} CHƯƠNG (lỗi: {n_err}) ===")
print(f"{'chỉ số':22s} {'MODEL':>10s} {'HACHIMI':>10s}")
for k in ("chars", "ratio", "para_ratio", "han", "modern", "west", "lint", "unbal"):
    print(f"{k:22s} {agg['model'][k]/n:10.2f} {agg['hachimi'][k]/n:10.2f}")
print(f"{'chữ Hán TRƯỚC vá':22s} {agg['model']['han_raw']/n:10.2f}")
print(f"{'giây/chương':22s} {agg['model']['sec']/n:10.1f}")

print(f"\n=== THEO TRUYỆN (lint · đại từ hiện đại · chữ Tây | model vs hachimi) ===")
for nid, d in sorted(per_novel.items()):
    def m(k, i): return sum(x[i] for x in d[k]) / max(1, len(d[k]))
    print(f"nv{nid:<6d} lint {m('lint',0):5.1f}/{m('lint',1):5.1f}   "
          f"đtừ {m('modern',0):4.1f}/{m('modern',1):4.1f}   "
          f"tây {m('west',0):5.1f}/{m('west',1):5.1f}   tỉ lệ {m('ratio',0):4.2f}/{m('ratio',1):4.2f}")
