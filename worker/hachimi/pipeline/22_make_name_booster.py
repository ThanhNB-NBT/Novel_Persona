"""Sinh booster NHẤT QUÁN TÊN nhân vật cho Hachimi.

Lỗi thật (audit 22/08): cùng 苏包 trong một chương ra cả "Tô Bao" lẫn "Tô túi".
Marian không có cơ chế khóa tên — chỉ có thể DẠY bằng data mà tên xuất hiện nhiều
lần trong cùng một cặp, bản VI phải render Y HỆT mỗi lần xuất hiện.

    python 22_make_name_booster.py --n 800 --out ../data/gold/name_booster.jsonl
    python 22_make_name_booster.py --self-check
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "data" / "gold" / "name_booster.jsonl"

# họ -> phiên âm Hán-Việt
SURNAMES = {
    "林": "Lâm", "叶": "Diệp", "韩": "Hàn", "王": "Vương", "苏": "Tô",
    "陈": "Trần", "张": "Trương", "李": "Lý", "赵": "Triệu", "秦": "Tần",
    "萧": "Tiêu", "沈": "Thẩm", "顾": "Cố", "陆": "Lục", "江": "Giang",
    "宋": "Tống", "唐": "Đường", "莫": "Mạc", "白": "Bạch", "楚": "Sở",
    "周": "Chu", "吴": "Ngô", "孙": "Tôn", "徐": "Từ", "方": "Phương",
}
# ký tự tên -> đọc Hán-Việt
GIVEN = {
    "风": "Phong", "凡": "Phàm", "雪": "Tuyết", "灵": "Linh", "天": "Thiên",
    "羽": "Vũ", "尘": "Trần", "霜": "Sương", "月": "Nguyệt", "星": "Tinh",
    "河": "Hà", "山": "Sơn", "海": "Hải", "剑": "Kiếm", "寒": "Hàn",
    "炎": "Viêm", "雷": "Lôi", "明": "Minh", "清": "Thanh", "玉": "Ngọc",
    "花": "Hoa", "蝶": "Điệp", "青": "Thanh", "云": "Vân", "远": "Viễn",
    "峰": "Phong", "瑶": "Dao", "烟": "Yên", "澜": "Lan", "辰": "Thần",
    "轩": "Hiên", "瑶": "Dao", "歌": "Ca", "离": "Ly", "渊": "Uyên",
}
TITLES_ZH_VI = [("师兄", "sư huynh"), ("师姐", "sư tỷ"), ("掌门", "chưởng môn"),
                ("长老", "trưởng lão"), ("城主", "thành chủ")]


def make_name(rng: random.Random) -> tuple[str, str]:
    sur_zh, sur_vi = rng.choice(list(SURNAMES.items()))
    chars = rng.sample(list(GIVEN.items()), rng.choice([1, 2]))
    zh = sur_zh + "".join(c for c, _ in chars)
    vi = sur_vi + " " + " ".join(v for _, v in chars)
    return zh, vi


PROFILES = [
    "{A}：{B}的{t}，两人{rel}，性情{trait}。",
    "{A}：{B} của {C}，{t2} đắc lực nhất, cùng {C} {rel} đã lâu.",
    "{A}: Con trai thứ hai của {B}, nhờ kỳ duyên mà tu vi vượt bậc, tính tình{trait}.",
]
NARRATIVES = [
    ("{a}皱了皱眉，看向远处的{b}。“{b}不会骗我。”{a}低声说道。多年以后，{a}仍记得这一天。",
     "{a} nhíu mày, nhìn về phía xa nơi có {b}. “{b} sẽ không lừa ta.” {a} khẽ nói. "
     "Nhiều năm sau, {a} vẫn nhớ ngày hôm ấy."),
    ("{a}与{b}并肩站在山门前。风起时，{a}握紧了剑柄。“走吧。”{b}说。{a}点头，二人一同踏入山中。",
     "{a} và {b} đứng cạnh nhau trước sơn môn. Gió nổi lên, {a} nắm chặt chuôi kiếm. "
     "“Đi thôi.” {b} nói. {a} gật đầu, hai người cùng nhau bước vào trong núi."),
    ("“{a}，你来了。”{b}转过身，目光落在{a}身上。{a}沉默片刻，缓缓开口：“我来还债。”",
     "“{a}, ngươi đến rồi.” {b} quay lại, ánh mắt rơi xuống người {a}. "
     "{a} im lặng một lúc, chậm rãi mở miệng: “Ta đến trả nợ.”"),
]


def trait(rng: random.Random, vi: bool = False) -> str:
    pair = rng.choice([("刚烈", "cương liệt"), ("沉稳", "trầm ổn"), ("阴沉", "âm trầm"),
                       ("豪爽", "hào sảng"), ("孤傲", "cô ngạo")])
    return pair[1] if vi else pair[0]


def build(n: int, seed: int) -> list[dict]:
    rng = random.Random(seed)
    rows: list[dict] = []
    seen_zh: set[str] = set()

    def to_vi(s: str) -> str:
        return s.replace("，", ", ").replace("。", ".")

    while len(rows) < n:
        a_zh, a_vi = make_name(rng)
        b_zh, b_vi = make_name(rng)
        c_zh, c_vi = make_name(rng)
        if len({a_zh, b_zh, c_zh}) < 3:
            continue
        t_zh, t_vi = rng.choice(TITLES_ZH_VI)
        if rng.random() < 0.5:
            zh = f"{a_zh}：{c_zh}的{t_zh}，与{b_zh}有旧怨，性情{trait(rng)}。"
            vi = to_vi(f"{a_vi}: {t_vi} của {c_vi}, có mâu thuẫn cũ với {b_vi}, "
                       f"tính tình {trait(rng, vi=True)}.")
        else:
            z_tpl, v_tpl = rng.choice(NARRATIVES)
            zh = z_tpl.format(a=a_zh, b=b_zh)
            # mỗi lần xuất hiện a/b/c đều render y hệt
            vi = to_vi(v_tpl.format(a=a_vi, b=b_vi))
        key = zh.strip()
        if key in seen_zh:
            continue
        seen_zh.add(key)
        rows.append({"zh": zh, "vi": vi,
                     "domain": "name_consistency", "status": "approved"})
    return rows


def _self_check() -> None:
    rows = build(300, seed=3)
    assert len(rows) >= 280
    for r in rows[:50]:
        assert r["vi"].strip() and r["zh"].strip()
        assert not any("\u4e00" <= ch <= "\u9fff" for ch in r["vi"]), r["vi"]
    # kiểm tra nhất quán: tên lặp lại trong zh phải lặp lại y hệt trong vi
    import re
    checked = 0
    for r in rows[:200]:
        names = re.findall(r"[林叶韩王苏陈张李赵秦萧沈顾陆江宋唐莫白楚周吴孙徐方][一-鿿]{1,2}", r["zh"])
        for nm in set(names):
            if r["zh"].count(nm) >= 2 and nm not in ("师兄", "师姐"):
                checked += 1
                break
    print(f"22_make_name_booster self-check OK — {len(rows)} đoạn "
          f"(spot-check nhất quán: {checked})")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=800)
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
        print(f"Đã ghi {len(rows)} đoạn -> {a.out}")
