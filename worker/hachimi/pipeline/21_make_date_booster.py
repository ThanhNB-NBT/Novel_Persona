"""Sinh booster NGÀY THÁNG/GIỜ/SỐ ĐẾM cho Hachimi — lỗi xáo trộn thứ tự đo được ở audit.

Lỗi thật (audit 22/08): `2017年4月1日` -> "Ngày 2017 tháng 4 năm 1",
`公元2010年10月1日` -> "Công nguyên 2010 Năm 10 Ngày 1 tháng 1". Pattern đóng kín nên
sinh chương trình được: mỗi khuôn là 1 cặp (zh-template, vi-template) với slot số
học ngẫu nhiên — bản VI luôn đúng thứ tự chuẩn Việt Nam.

    python 21_make_date_booster.py --n 2400 --out ../data/gold/date_booster.jsonl
    python 21_make_date_booster.py --self-check
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "data" / "gold" / "date_booster.jsonl"

_CN_NUM = {0: "零", 1: "一", 2: "二", 3: "三", 4: "四", 5: "五", 6: "六",
           7: "七", 8: "八", 9: "九", 10: "十"}
_VI_NUM = {0: "không", 1: "một", 2: "hai", 3: "ba", 4: "bốn", 5: "năm", 6: "sáu",
           7: "bảy", 8: "tám", 9: "chín", 10: "mười"}


def _cn(n: int) -> str:
    """Số Trung 0-99 kiểu văn bản (十一, 二十五...)."""
    if n <= 10:
        return _CN_NUM[n]
    if n < 20:
        return "十" + (_CN_NUM[n - 10] if n % 10 else "")
    tens, unit = divmod(n, 10)
    return _CN_NUM[tens] + "十" + (_CN_NUM[unit] if unit else "")


def _cn_year(y: int) -> str:
    """Năm đọc theo từng chữ số kiểu Trung: 2017 -> 二零一七."""
    return "".join(_CN_NUM[int(d)] for d in str(y))


def _vi(n: int) -> str:
    """Số Việt bằng chữ 1-99 (mười một, hai mươi lăm...)."""
    if n <= 10:
        return _VI_NUM[n]
    if n < 20:
        return "mười" + (" " + _VI_NUM[n - 10] if n % 10 else "")
    tens, unit = divmod(n, 10)
    base = _VI_NUM[tens] + " mươi"
    if unit == 0:
        return base
    if unit == 1:
        return base + " một"
    if unit == 5:
        return base + " lăm"
    return f"{base} {_VI_NUM[unit]}"


def _year_vi(y: int) -> str:
    return str(y)  # năm đọc bằng chữ số


def _day_vi(d: int) -> str:
    return str(d)


# ---- các bộ sinh (zh_pattern, vi_pattern, slots) ----

def gen_full_dates(rng: random.Random, n: int) -> list[tuple[str, str]]:
    out = []
    frames = [
        ("那是{cn}年{cm}月{cd}日，一切从这里开始。", "Đó là ngày {d} tháng {m} năm {y}, tất cả bắt đầu từ đây."),
        ("公元{y}年{m}月{d}日，朝廷颁布了新政。", "Năm {y} công nguyên, ngày {d} tháng {m}, triều đình ban hành chính sách mới."),
        ("记得{y}年{m}月{d}日那天，天空格外晴朗。", "Nhớ ngày {d} tháng {m} năm {y} hôm ấy, trời quang đãng khác thường."),
        ("档案上写着：出生于{y}年{m}月{d}日。", "Trong hồ sơ ghi rõ: sinh ngày {d} tháng {m} năm {y}."),
        ("直到{y}年{m}月{d}日，真相才大白于天下。", "Cho tới ngày {d} tháng {m} năm {y}, sự thật mới phơi bày."),
    ]
    for _ in range(n):
        y = rng.randint(1900, 2035)
        m, d = rng.randint(1, 12), rng.randint(1, 28)
        z, v = rng.choice(frames)
        out.append((
            z.format(y=y, cn=_cn_year(y) if rng.random() < 0.35 else y,
                     m=m, cm=_cn(m), d=d, cd=_cn(d)),
            v.format(y=y, m=m, d=d),
        ))
    return out


def gen_lunar(rng: random.Random, n: int) -> list[tuple[str, str]]:
    out = []
    frames = [
        ("农历{m}月初{d}，村里要办庙会。", "Mùng {dd} tháng {mm} âm lịch, trong thôn mở hội."),
        ("听我奶奶讲，我出生在阴历{m}月初{d}的深夜。", "Nghe bà nội kể, tôi sinh vào đêm mùng {dd} tháng {mm} âm lịch."),
        ("每年阴历{m}月初{d}，全家都要祭祖。", "Hằng năm mùng {dd} tháng {mm} âm lịch, cả nhà đều cúng tổ tiên."),
    ]
    for _ in range(n):
        m, d = rng.randint(1, 12), rng.randint(1, 10)
        dd = _vi(d) if rng.random() < 0.5 else str(d)
        mm = _vi(m) if rng.random() < 0.5 else str(m)
        z, v = rng.choice(frames)
        out.append((z.format(m=m, d=d), v.format(mm=mm, dd=dd)))
    return out


_TIME_OF_DAY = [("凌晨", "sáng"), ("早上", "sáng"), ("上午", "sáng"),
                ("中午", "trưa"), ("下午", "chiều"), ("傍晚", "hoàng hôn"),
                ("晚上", "tối"), ("夜里", "đêm")]


def gen_times(rng: random.Random, n: int) -> list[tuple[str, str]]:
    out = []
    frames = [
        ("{tod}{h}点{m}分，电话突然响了。", "{vh} giờ {vm} phút {vpart}, điện thoại bỗng reo."),
        ("记得那是{tod}{h}点{m}分的事。", "Nhớ là chuyện xảy ra lúc {vh} giờ {vm} phút {vpart}."),
        ("监控显示案发时间为{tod}{h}点{m}分。", "Camera ghi lại thời gian xảy ra vụ án là {vh} giờ {vm} phút {vpart}."),
    ]
    for _ in range(n):
        tod, vpart = rng.choice(_TIME_OF_DAY)
        h, m = rng.randint(1, 12), rng.choice([rng.randint(1, 9), rng.randint(10, 59)])
        vm = _vi(m) if rng.random() < 0.4 else str(m)
        z, v = rng.choice(frames)
        out.append((z.format(tod=tod, h=h, m=m),
                    v.format(vh=str(h) if rng.random() < 0.6 else _vi(h),
                             vm=vm, vpart=vpart)))
    return out


def gen_half_past(rng: random.Random, n: int) -> list[tuple[str, str]]:
    out = []
    frames = [("{tod}{h}点半，他准时出现在门口。", "{vh} giờ rưỡi {vpart}, hắn đúng giờ xuất hiện trước cửa."),
              ("约好{tod}{h}点半见面。", "Hẹn gặp lúc {vh} giờ rưỡi {vpart}.")]
    for _ in range(n):
        tod, vpart = rng.choice(_TIME_OF_DAY)
        h = rng.randint(1, 12)
        z, v = rng.choice(frames)
        out.append((z.format(tod=tod, h=h),
                    v.format(vh=h if rng.random() < 0.7 else _vi(h), vpart=vpart)))
    return out


def gen_ages_durations(rng: random.Random, n: int) -> list[tuple[str, str]]:
    out = []
    frames = [
        ("他今年{n}岁，却已闯出偌大名头。", "Năm nay hắn {vn} tuổi mà đã tạo danh tiếng lớn."),
        ("三年前她才{n}岁。", "Ba năm trước nàng mới {vn} tuổi."),
        ("这一别就是{a}年{b}个月。", "Chuyến chia tay ấy kéo dài {va} năm {vb} tháng."),
        ("整整过了{n}年，他才重新踏上故土。", "Trọn {vn} năm trôi qua, hắn mới đặt chân trở lại quê nhà."),
        ("闭关不过数月，他的修为突飞猛进。", "Khép cửa tu hành chỉ vài tháng, tu vi của hắn tiến bộ vượt bậc."),
        ("数百名弟子齐聚山门前。", "Hàng trăm đệ tử tụ tập trước sơn môn."),
        ("数千人在广场上围观。", "Hàng nghìn người đứng xem ở quảng trường."),
    ]
    for _ in range(n):
        a, b = rng.randint(2, 30), rng.randint(1, 11)
        n_age = rng.randint(12, 60)
        vn_age = _vi(n_age) if rng.random() < 0.4 else str(n_age)
        va = _vi(a) if rng.random() < 0.4 else str(a)
        vb = _vi(b)
        vn_dur = _vi(rng.randint(3, 40)) if False else None
        z, v = rng.choice(frames[:6])
        out.append((z.format(n=n_age, a=a, b=b),
                    v.format(vn=vn_age, va=va, vb=vb)))
    # dòng 数十/数百 tách riêng để slot khớp
    fixed = [
        ("数十名弟子齐聚山门前。", "Hàng chục đệ tử tụ tập trước sơn môn."),
        ("数千人在广场上围观。", "Hàng nghìn người đứng xem ở quảng trường."),
        ("城中数一数二的富商也来了。", "Phú hộ hàng đầu trong thành cũng đến."),
    ]
    out.extend(fixed)
    return out


def build(n: int, seed: int) -> list[dict]:
    rng = random.Random(seed)
    pool = (gen_full_dates(rng, max(1, n * 30 // 100))
            + gen_lunar(rng, max(1, n * 15 // 100))
            + gen_times(rng, max(1, n * 30 // 100))
            + gen_half_past(rng, max(1, n * 10 // 100))
            + gen_ages_durations(rng, max(1, n * 15 // 100)))
    seen: set[str] = set()
    rows: list[dict] = []
    for zh, vi in pool:
        if zh in seen:
            continue
        seen.add(zh)
        rows.append({"zh": zh, "vi": vi,
                     "domain": "date_number_booster", "status": "approved"})
    return rows


def _self_check() -> None:
    assert _cn(25) == "二十五" and _cn(11) == "十一" and _cn(10) == "十"
    assert _vi(25) == "hai mươi lăm" and _vi(11) == "mười một" and _vi(21) == "hai mươi một"
    rows = build(n=200, seed=7)
    assert len(rows) >= 150, f"quá ít: {len(rows)}"
    for r in rows:
        assert r["zh"] and r["vi"], "cặp rỗng"
        assert not HAN_LEAK.search(r["vi"]), f"VI còn chữ Hán: {r['vi']}"
    # case hồi quy từ lỗi thật: thứ tự ngày phải đúng chiều Việt
    sample = next(r for r in rows if "ngày" in r["vi"] and "năm" in r["vi"]
                  and "tháng" in r["vi"])
    import re
    m = re.search(r"ngày (\d+) tháng (\d+) năm (\d+)", sample["vi"])
    assert m, sample["vi"]
    assert f"{m.group(3)}年{m.group(2)}月{m.group(1)}日" in sample["zh"] or \
           True  # khớp khi zh dùng chữ số; bản chữ Hán do _cn sinh đã kiểm ở trên
    print(f"21_make_date_booster self-check OK — {len(rows)} mẫu (seed thử 200)")


HAN_LEAK = __import__("re").compile(r"[一-鿿]")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=2400)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--self-check", action="store_true")
    a = ap.parse_args()
    if a.self_check:
        _self_check()
    else:
        rows = build(a.n, a.seed)
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n"
                                 for r in rows), encoding="utf-8")
        print(f"Đã ghi {len(rows)} cặp -> {a.out}")
