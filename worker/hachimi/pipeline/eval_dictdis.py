"""So bản dịch nhiều model CT2 trên câu TƯƠI (KHÁC bộ train DictDis) — 18 term đa nghĩa/jargon.

    python eval_dictdis.py <ct2_dir_1> <ct2_dir_2> ...
Không tham số: so v5-base (candidates/v5) vs v5-dictdis mặc định.
Nhãn = nghĩa đúng mong đợi; đọc tay để chấm.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # worker/
DEFAULT = [
    ROOT / "models" / "hachimi-v5-hf" / "ct2-int8_float32",
    ROOT / "models" / "hachimi-v5-dictdis" / "ct2-int8_float32",
]
V5_CANON = ROOT / "hachimi" / "models" / "candidates" / "v5" / "ct2-int8_float32"

# Câu TƯƠI — KHÁC bộ train. (term, nhãn nghĩa, zh)
TESTS = [
    # target cũ
    ("自摸/mạt chược", "他这把牌运气好，一上来就自摸了。"),
    ("自摸/tự sờ",     "他半夜睡不着，一个人在床上自摸。"),          # test HỒI QUY
    ("脉动/Mizone",    "他一边打游戏一边灌脉动。"),                    # test MISS 灌
    ("脉动/nhịp đập",  "他能感觉到符阵中传来的脉动。"),
    # đô thị
    ("副本/bản sao",   "麻烦复印一份合同副本给我。"),
    ("副本/dungeon",   "公会今晚要一起刷副本。"),
    ("秒杀/flash-sale","双十一零点，她准时蹲守秒杀。"),
    ("秒杀/insta-kill","他技能一放，直接秒杀了对面射手。"),
    ("刷新/phá kỷ lục","他的百米成绩再次刷新了。"),
    ("刷新/respawn",   "精英怪被清了，得等它刷新。"),
    ("刷新/refresh",   "系统卡了，刷新一下重新登录。"),
    ("隐身/offline",   "他嫌烦，干脆在QQ上设置了隐身。"),
    ("隐身/tàng hình", "他潜行时开了隐身，摸到了敌方后方。"),
    ("种草/muốn mua",  "看了她的分享，我又被种草了一双鞋。"),
    ("走光/lộ hàng",   "她弯腰捡东西时差点走光。"),
    ("上头/nghiện",    "这剧太上头了，我一口气追到凌晨。"),
    # võng du
    ("人头/mạng",      "他蹲在草丛里，专门捡人头。"),
    ("输出/sát thương","队友都是脆皮输出，需要好好保护。"),
    ("兵线/làn lính",  "对面在推兵线，快去防守。"),
    ("抓人/gank",      "中路太危险，敌方打野一直来抓人。"),
    ("补刀/last-hit",  "新手最难练的就是补刀。"),
    ("上分/leo rank",  "他就想安安静静上分，别打扰。"),
    ("开黑/team",      "放假天天窝在家开黑。"),
    ("坦克/game-tank", "这局没人玩坦克，团战全崩。"),
    ("发育/farm",      "他前期一直在打野发育，不参团。"),
    ("开大/ultimate",  "残血了他立刻开大反杀逃生。"),
    ("团战/giao tranh","一场团战下来，双方各损两人。"),
    ("平A/đánh thường","没蓝了，只能靠平A收尾。"),
    ("高能/cao trào",  "预警，前方高能片段来了。"),
    ("挂机/afk",       "他一生气，直接挂机不打了。"),
    ("越塔/dive",      "对面越塔强杀，结果被反杀。"),
    ("内卷/khốc liệt", "今年考研太内卷，报录比吓人。"),
    ("送人头/feed",    "他孤身深入，白白送了个人头。"),
    ("吃土/cháy túi",  "冲动消费之后，他这个月只能吃土。"),
]


def main(dirs: list[Path]) -> None:
    from novelworker.translator.hachimi_engine import _Engine
    dirs = [d for d in dirs if (d / "model.bin").is_file()]
    if not dirs:
        raise SystemExit("Không thấy model.bin trong các dir đã cho")
    engines = [(d.parent.name if d.name.startswith("ct2") else d.name, _Engine(str(d))) for d in dirs]
    print("Model so sánh:", [n for n, _ in engines], "\n")
    for tag, zh in TESTS:
        print(f"[{tag}] {zh}")
        for name, eng in engines:
            vi = eng.translate_lines([zh])[0]
            print(f"    {name:22} -> {vi}")
        print()


if __name__ == "__main__":
    args = [Path(a) for a in sys.argv[1:]]
    if not args:
        base = DEFAULT[0] if (DEFAULT[0] / "model.bin").is_file() else V5_CANON
        args = [base, DEFAULT[1]]
    main(args)
