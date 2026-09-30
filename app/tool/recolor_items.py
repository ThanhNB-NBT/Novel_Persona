"""Sinh ảnh biến thể màu cho vật phẩm Tu Tiên từ bộ minh hoạ gốc.

124+ món chỉ có ~31 minh hoạ → nhiều món trùng hình. Script này đổi màu CÓ CHỌN LỌC
(chỉ dải màu chủ đạo của từng hình, giữ viền vàng/trắng/tua đỏ) để mỗi món một bản phối.

Nguồn sự thật là map `itemArt` trong lib/screens/cultivation/pixel.dart: mọi giá trị
dạng '<key>_<phối>' ở đó được sinh ra assets/cult_items/<key>_<phối>.webp.

    cd app && python tool/recolor_items.py          # sinh thiếu
    cd app && python tool/recolor_items.py --all    # sinh lại hết
    cd app && python tool/recolor_items.py --sheet out.png   # bảng xem thử

Cần: pip install pillow numpy
"""

import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

APP = Path(__file__).resolve().parent.parent
ITEMS = APP / 'assets' / 'cult_items'
PIXEL_DART = APP / 'lib' / 'screens' / 'cultivation' / 'pixel.dart'

# Dải hue (độ) coi là "màu chủ đạo" của từng hình — phần sẽ bị đổi.
# Mặc định: lam đậm (áo/bìa/vỏ) 175..255.
BAND = {
    'seal': (330, 30),         # khối ấn đỏ
    'stone': (110, 200),       # linh thạch ngọc bích
    'shield_pill': (110, 200),
    'pill': (110, 200),        # thân bình ngọc
    'jade': (100, 190),
    'talisman': (35, 70),      # giấy bùa vàng
    'halo': (30, 70),          # vòng kim loại vàng
    'orb': (100, 190),
    'dragon_cauldron': (60, 190),  # lửa lục
    'compass': (100, 255),     # mặt ngọc + viền lam
    'fan': (100, 255),
    'array': (100, 255),
    'pagoda': (25, 75),        # thân tháp vàng
    'mirror': (25, 75),        # gương đồng
    'demonic_saber': (330, 30),
    'bow': (25, 75),           # thân cung vàng
}
DEFAULT_BAND = (175, 255)

# Hình mà thân chính NHẠT màu (lưỡi kiếm, vỏ hồ lô, ngọc giản, cầu thủy tinh) — dải hue
# chỉ chạm tua/hoa văn → nhuộm thêm vùng nhạt với cường độ này để bản phối nhìn ra được.
PALE = {'sword': 0.6, 'spear': 0.6, 'saber': 0.6, 'bow': 0.45, 'gourd': 0.5,
        'slip': 0.55, 'pill': 0.45, 'orb': 0.45}

# phối → (hue đích | None = giữ, nhân bão hoà, nhân sáng)
COLORWAYS = {
    'xich': (356, 1.15, 1.20),   # đỏ son — hỏa, huyết, chu tước
    'tu': (282, 1.05, 1.20),     # tím — tử, lôi, hỗn độn
    'bich': (148, 0.95, 1.15),   # lục ngọc — mộc, thanh, bích
    'kim': (40, 1.20, 1.65),     # hổ phách — kim, hoàng, phật
    'bang': (192, 0.75, 1.45),   # băng lam nhạt — thủy, hàn, nguyệt
    'huyen': (None, 0.30, 0.55), # huyền hắc — ma, u, sát
    'bach': (None, 0.10, 2.10),  # bạch ngân — bạch, tiên, vô cấu
    'tho': (26, 0.65, 1.25),     # nâu đất — thổ, bố, thảo
    'lam': (218, 1.00, 1.00),    # lam gốc (cho hình gốc không phải lam: ấn, bùa)
}


def _hue_dist(h, lo, hi):
    """Khoảng cách (độ) từ h tới dải [lo, hi] trên vòng tròn; 0 nếu nằm trong."""
    if lo <= hi:
        inside = (h >= lo) & (h <= hi)
        d = np.minimum(np.abs(h - lo), np.abs(h - hi))
    else:  # dải vắt qua 0°
        inside = (h >= lo) | (h <= hi)
        d = np.minimum(np.abs(h - lo), np.abs(h - hi))
    d = np.minimum(d, 360 - d)
    return np.where(inside, 0, d)


def recolor(key, cw):
    src = Image.open(ITEMS / f'{key}.webp').convert('RGBA')
    rgba = np.asarray(src).astype(np.float32) / 255
    hsv = np.asarray(src.convert('RGB').convert('HSV')).astype(np.float32) / 255
    h, s, v = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    lo, hi = BAND.get(key, DEFAULT_BAND)
    # trọng số mềm: trong dải = 1, mép dải tắt dần 20°, màu gần xám (s thấp) không đụng
    w = np.clip(1 - _hue_dist(h, lo, hi) / 20, 0, 1) * np.clip((s - 0.12) / 0.15, 0, 1)
    tgt, sm, vm = COLORWAYS[cw]
    center = (lo + ((hi - lo) % 360) / 2) % 360
    if tgt is None:
        nh = h
    else:  # giữ độ lệch nhỏ quanh tâm dải để còn chuyển sắc
        off = ((h - center + 180) % 360) - 180
        nh = (tgt + off * 0.5) % 360
    ns = np.clip(s * sm, 0, 1)
    nv = np.clip(v * vm, 0, 1)
    hh = h + (((nh - h + 180) % 360) - 180) * w
    ss = s + (ns - s) * w
    vv = v + (nv - v) * w
    k = PALE.get(key, 0)
    if k:
        # vùng nhạt + đủ sáng (kim loại, ngọc, sứ) — không đụng viền đen và mảng đã nhuộm
        p = k * np.clip((0.32 - s) / 0.2, 0, 1) * np.clip((v - 0.4) / 0.2, 0, 1) * (1 - w)
        if tgt is not None:
            hh = hh + (((tgt - hh + 180) % 360) - 180) * p
            ss = ss + (0.55 * min(sm, 1) - ss) * p
        else:
            ss = ss * (1 - p)
        vv = vv + (np.clip(vv * (0.6 if vm < 1 else 1.08), 0, 1) - vv) * p
    out = Image.merge('HSV', [
        Image.fromarray(((hh % 360) / 360 * 255).astype(np.uint8)),
        Image.fromarray((ss * 255).astype(np.uint8)),
        Image.fromarray((vv * 255).astype(np.uint8)),
    ]).convert('RGBA')
    out.putalpha(Image.fromarray((rgba[..., 3] * 255).astype(np.uint8)))
    return out


def wanted():
    """Mọi '<key>_<phối>' được map itemArt trong pixel.dart tham chiếu."""
    text = PIXEL_DART.read_text(encoding='utf-8')
    block = text[text.index('const itemArt'):]
    block = block[:block.index('};')]
    names = sorted(set(re.findall(r":\s*'([a-z_]+)'", block)))
    out = []
    for n in names:
        key, _, cw = n.rpartition('_')
        assert cw in COLORWAYS, n
        assert (ITEMS / f'{key}.webp').exists(), n
        out.append((key, cw))
    return out


def main():
    args = sys.argv[1:]
    pairs = wanted()
    if '--sheet' in args:
        path = args[args.index('--sheet') + 1]
        cell = 112
        cols = 10
        rows = (len(pairs) + cols - 1) // cols
        sheet = Image.new('RGBA', (cols * cell, rows * cell), (34, 36, 44, 255))
        for i, (k, cw) in enumerate(pairs):
            im = recolor(k, cw).resize((cell, cell), Image.LANCZOS)
            sheet.alpha_composite(im, ((i % cols) * cell, (i // cols) * cell))
        sheet.convert('RGB').save(path)
        print(f'{len(pairs)} bien the -> {path}')
        return
    made = 0
    for k, cw in pairs:
        dst = ITEMS / f'{k}_{cw}.webp'
        if dst.exists() and '--all' not in args:
            continue
        recolor(k, cw).save(dst, 'WEBP', quality=88, method=6)
        made += 1
    print(f'{made} anh moi / {len(pairs)} bien the')


if __name__ == '__main__':
    main()
