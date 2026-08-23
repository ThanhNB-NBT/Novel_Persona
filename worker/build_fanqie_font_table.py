# -*- coding: utf-8 -*-
"""Xây bảng mã PUA→Hán cho font fanqie (TOOL DEV — KHÔNG chạy trên VPS).

Khi adapter fanqie log cảnh báo "font ĐỔI" (ByteDance rebuild font woff2):
  1. Mở 1 trang /reader/{id} bất kỳ, lấy URL .woff2 mới → thay FONT_URL dưới.
  2. Tải Noto Sans SC Regular (ref.otf) từ notofonts/noto-cjk trên GitHub → sửa REF.
  3. Chạy script này → ghi `novelworker/crawler/fanqie_charset.json` mới.
  4. Decode thử vài chương, rà tay các mục biên mỏng (<0.05) + ngữ cảnh sai
     (đã biết: nét ngang mảnh 一 hay bị nhận nhầm em-dash).
Dependency dev-only: fonttools brotli pillow numpy (không cần trên VPS —
runtime chỉ str.translate với bảng JSON).
"""
import io
import json
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
import numpy as np
from curl_cffi import requests as rq
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

FONT_URL = "https://lf6-awef.bytetos.com/obj/awesome-font/c/dc027189e0ba4cd.woff2"
REF = r"C:\Windows\Fonts\msyh.ttc"  # hoặc NotoSansSC-Regular.otf (khớp tốt hơn)
OUT = "novelworker/crawler/fanqie_charset.json"
SIZE = 64
GRID = 24


def load_fanqie_ttf(url):
    data = rq.get(url, impersonate="chrome", timeout=(8, 25)).content
    t = TTFont(io.BytesIO(data))
    cmap = {cp: g for cp, g in t.getBestCmap().items() if 0xE000 <= cp <= 0xF8FF}
    t.flavor = None
    buf = io.BytesIO()
    t.save(buf)
    buf.seek(0)
    return buf.read(), cmap


def render(ch, font):
    """Render ký tự → vector đặc trưng (crop ink → resize GRID²). None nếu trống."""
    img = Image.new("L", (SIZE * 2, SIZE * 2), 255)
    ImageDraw.Draw(img).text((SIZE // 2, SIZE // 2), ch, font=font, fill=0)
    arr = np.asarray(img)
    ink = arr < 128
    if not ink.any():
        return None
    ys, xs = np.where(ink)
    crop = arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1].astype(np.uint8)
    # giữ tỷ lệ khung hình: pad về vuông rồi mới resize — nét ngang/dọc (一/丨)
    # không còn bị ép thành ô vuông đầy và trùng nhau
    ch_, cw_ = crop.shape
    s = max(ch_, cw_)
    sq = np.full((s, s), 255, dtype=np.uint8)
    y0, x0 = (s - ch_) // 2, (s - cw_) // 2
    sq[y0:y0 + ch_, x0:x0 + cw_] = crop
    small = np.asarray(Image.fromarray(sq).resize((GRID, GRID)), dtype=np.float32) / 255.0
    v = small.flatten()
    n = np.linalg.norm(v)
    return v / n if n else None


def main():
    ttf_bytes, cmap = load_fanqie_ttf(FONT_URL)
    pua_cps = sorted(cmap)
    print(f"PUA glyphs: {len(pua_cps)}")

    fq_font = ImageFont.truetype(io.BytesIO(ttf_bytes), SIZE)
    ref_font = ImageFont.truetype(REF, SIZE)

    # tập ứng viên: toàn bộ CJK + dấu câu/digit/latin hay gặp
    cands = [chr(cp) for cp in range(0x4E00, 0xA000)]
    cands += [chr(c) for c in range(0x3000, 0x303F) if not (0x3021 <= c <= 0x302F)]  # dấu câu CJK
    cands += [chr(c) for c in list(range(0xFF10, 0xFF1A)) + list(range(0xFF21, 0xFF3B)) + list(range(0xFF41, 0xFF5B))]  # chỉ digit+letter fullwidth
    cands += list("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.,!?:;'\"()-—…%")
    cands = [c for c in dict.fromkeys(cands)]

    print(f"render {len(cands)} ứng viên tham chiếu…")
    ref_vecs = []
    ref_ok = []
    for c in cands:
        v = render(c, ref_font)
        if v is not None:
            ref_vecs.append(v)
            ref_ok.append(c)
    M = np.stack(ref_vecs)                      # (N, GRID²)
    print("ứng viên có hình:", len(ref_ok))

    # trọng số: chữ Hán được ưu tiên — khoảng cách của ứng viên KHÔNG phải Hán
    # bị phạt nhẹ để phân giải các cặp giống nhau về hình (一 vs －, 在 vs 往…)
    weights = np.array([
        1.0 if 0x4E00 <= ord(c) <= 0x9FFF else
        (1.05 if c in "，。！？…、；：“”‘’（）《》—0123456789" else 1.35)
        for c in ref_ok], dtype=np.float32)

    table = {}
    low_margin = []
    no_match = []
    for cp in pua_cps:
        v = render(chr(cp), fq_font)
        if v is None:
            no_match.append(hex(cp))
            continue
        d = np.linalg.norm(M - v, axis=1) * weights
        order = np.argsort(d)
        best, best_d = ref_ok[order[0]], float(d[order[0]])
        second_d = float(d[order[1]])
        margin = second_d - best_d
        table[hex(cp)] = best
        if margin < 0.05:
            low_margin.append((hex(cp), best, round(margin, 3)))

    print(f"map được: {len(table)}; không render được: {len(no_match)}; "
          f"biên mỏng (<0.05): {len(low_margin)}")
    print("biên mỏng mẫu:", low_margin[:10])

    out = {"font_url": FONT_URL, "table": table}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("đã ghi", OUT)

    # thử dịch ngay một chương thật để soi
    tbl = str.maketrans({chr(int(k, 16)): v for k, v in table.items()})
    r = rq.get("https://fanqienovel.com/reader/7567314951392461374",
               impersonate="chrome", timeout=(8, 25))
    txt = re.sub(r"<script.*?</script>", "", r.text, flags=re.S)
    txt = re.sub(r"<[^>]+>", " ", txt)
    decoded = txt.translate(tbl)
    runs = sorted(re.findall(r"[^<>]{150,}", decoded), key=len, reverse=True)[:3]
    print("\n===== ĐOẠN DỊCH THỬ =====")
    for run in runs:
        run2 = re.sub(r"\s+", "", run)
        han = sum(1 for c in run2 if 0x4E00 <= ord(c) <= 0x9FFF)
        pua = sum(1 for c in run2 if 0xE000 <= ord(c) <= 0xF8FF)
        print(f"[Hán={han} PUA còn={pua}] {run2[:200]}")


if __name__ == "__main__":
    main()




