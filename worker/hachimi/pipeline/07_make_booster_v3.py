"""Sinh booster cho vòng teacher-v3: khoá xưng hô TRONG LỜI THOẠI + nghĩa của 枪.

Hai lỗi đo được ở bản teacher-v2 (experiments/hachimi_teacher_v2_eval.md):
1. `tôi/cháu/cậu` lọt vào lời thoại (25 hit/60 cảnh, current chỉ 15) — data train sạch
   đại từ nên đây là trôi văn phong, phải dạy trực tiếp bằng cặp thoại.
2. 枪 trong bối cảnh cổ trang bị dịch thành "súng" (把枪叉入地里 → "cắm súng xuống đất").
   Booster dạy CẢ HAI nghĩa để không lật ngược các câu bắn súng hiện đại.

Cả zh lẫn vi đều tự điền theo slot nên đáp án đúng theo cấu tạo, không cần thầy.
"""
from __future__ import annotations

import itertools
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "data" / "gold" / "booster_v3.jsonl"

# --- 1. Xưng hô trong lời thoại ---------------------------------------------
# (zh chủ ngữ, vi chủ ngữ) — trong thoại 我=ta, 你=ngươi, KHÔNG tôi/cậu/cháu.
SPEAKERS = [("我", "ta"), ("你", "ngươi"), ("他", "hắn"), ("她", "nàng")]
PLURALS = [("我们", "chúng ta"), ("你们", "các ngươi"), ("他们", "bọn họ")]
DIALOGUE_VERBS = [
    ("不去", "không đi"),
    ("知道了", "biết rồi"),
    ("明白了", "hiểu rồi"),
    ("先走一步", "đi trước một bước"),
    ("等你回来", "đợi ngươi trở về"),
    ("信你一次", "tin ngươi một lần"),
    ("已经准备好了", "đã chuẩn bị xong"),
    ("不会怪你", "sẽ không trách ngươi"),
    ("需要一点时间", "cần một chút thời gian"),
    ("会想办法的", "sẽ nghĩ cách"),
    ("留在这里", "ở lại nơi này"),
    ("答应过师父", "đã hứa với sư phụ"),
    ("没有别的选择", "không còn lựa chọn nào khác"),
    ("记得那件事", "còn nhớ chuyện đó"),
    ("不想再说了", "không muốn nói nữa"),
    ("这就出发", "lập tức lên đường"),
]
# Xưng hô người trên trong thoại: dễ kéo model về "cháu/chú" — ép về ta/ngươi.
ELDERS = [
    ("二叔", "nhị thúc"),
    ("大伯", "đại bá"),
    ("师父", "sư phụ"),
    ("爷爷", "gia gia"),
    ("师兄", "sư huynh"),
    ("前辈", "tiền bối"),
]
ELDER_LINES = [
    ("你喜欢什么，我去给你找", "Ngươi thích thứ gì, ta đi tìm cho ngươi"),
    ("你放心，我心里有数", "Ngươi yên tâm, ta có tính toán"),
    ("我不能收你这份礼", "Ta không thể nhận lễ vật này của ngươi"),
    ("你先回去，我随后就到", "Ngươi về trước, ta lát nữa sẽ tới"),
    ("我等你这句话很久了", "Ta đợi câu này của ngươi đã lâu"),
    ("你若信我，就随我来", "Nếu ngươi tin ta, hãy đi theo ta"),
]
ATTRIBUTIONS = [
    ("他说道。", " hắn nói."),
    ("她轻声说道。", " nàng nhẹ giọng nói."),
    ("老者摇头道。", " lão giả lắc đầu nói."),
    ("", ""),
]

# --- 2. Nghĩa của 枪 ---------------------------------------------------------
SPEAR = [
    ("他握紧手中长枪。", "Hắn nắm chặt trường thương trong tay."),
    ("少年挺枪刺出。", "Thiếu niên vung thương đâm ra."),
    ("枪尖上寒光闪烁。", "Trên mũi thương hàn quang lấp lánh."),
    ("他把枪插入地里。", "Hắn cắm thương xuống đất."),
    ("那杆枪重达百斤。", "Cây thương đó nặng cả trăm cân."),
    ("他将木枝当做枪来练习。", "Hắn lấy cành cây làm thương để luyện tập."),
    ("一枪刺穿了妖兽的胸口。", "Một thương đâm xuyên qua ngực yêu thú."),
    ("他的枪法已臻化境。", "Thương pháp của hắn đã đạt tới hóa cảnh."),
    ("银枪如龙般刺出。", "Ngân thương đâm ra như rồng."),
    ("他背着一杆长枪走进山门。", "Hắn vác một cây trường thương bước vào sơn môn."),
    ("枪影层层叠叠。", "Thương ảnh trùng trùng điệp điệp."),
    ("他收枪而立。", "Hắn thu thương đứng thẳng."),
]
GUN = [
    ("他掏出手枪。", "Hắn rút súng lục ra."),
    ("玩家买了一把步枪。", "Người chơi mua một khẩu súng trường."),
    ("他扣动扳机开枪。", "Hắn bóp cò nổ súng."),
    ("狙击枪的子弹打空了。", "Đạn của súng bắn tỉa đã hết."),
    ("这把枪械威力很大。", "Khẩu súng này uy lực rất lớn."),
    ("手枪局他只买了防弹衣。", "Round súng lục hắn chỉ mua giáp chống đạn."),
    ("枪声在走廊里回荡。", "Tiếng súng vang vọng trong hành lang."),
    ("他换上默认的USP手枪。", "Hắn đổi sang khẩu súng lục USP mặc định."),
]
SPEAR_CONTEXT = [
    ("在演武场上，", "Trên diễn võ trường, "),
    ("走出洞府后，", "Sau khi ra khỏi động phủ, "),
    ("面对妖兽，", "Đối mặt yêu thú, "),
    ("", ""),
]
GUN_CONTEXT = [
    ("在副本里，", "Trong phó bản, "),
    ("这一局，", "Ván này, "),
    ("枪战开始后，", "Sau khi cuộc đấu súng bắt đầu, "),
    ("", ""),
]


def cap(text: str) -> str:
    return text[:1].upper() + text[1:]


def lower_first(text: str) -> str:
    return text[:1].lower() + text[1:]


def dialogue_rows() -> list[dict]:
    rows = []
    for (zs, vs), (zv, vv), (za, va) in itertools.product(SPEAKERS + PLURALS, DIALOGUE_VERBS, ATTRIBUTIONS):
        rows.append({"zh": f"“{zs}{zv}。”{za}", "vi": f"“{cap(vs)} {vv}.”{va}"})
    for (ze, ve), (zl, vl), (za, va) in itertools.product(ELDERS, ELDER_LINES, ATTRIBUTIONS):
        rows.append({"zh": f"“{ze}，{zl}。”{za}", "vi": f"“{cap(ve)}, {lower_first(vl)}.”{va}"})
    return rows


def term_rows() -> list[dict]:
    rows = []
    for pairs, contexts in ((SPEAR, SPEAR_CONTEXT), (GUN, GUN_CONTEXT)):
        for (zh, vi), (zc, vc) in itertools.product(pairs, contexts):
            rows.append({"zh": f"{zc}{zh}", "vi": f"{vc}{vi if not vc else lower_first(vi)}"})
    return rows


def build() -> list[dict]:
    seen: set[str] = set()
    rows = []
    for row in dialogue_rows() + term_rows():
        if row["zh"] in seen:
            continue
        seen.add(row["zh"])
        rows.append({**row, "domain": "booster_v3", "status": "approved"})
    return rows


def self_check() -> None:
    import re

    modern = re.compile(r"(?i)(?<!\w)(?:tôi|mình|bạn|cậu|cháu|anh ta|cô ta|cô ấy|ông ta|bà ta)(?!\w)")
    rows = build()
    assert len(rows) == len({row["zh"] for row in rows}), "trùng nguồn Trung"
    for row in rows:
        assert not modern.search(row["vi"]), row["vi"]
        assert row["vi"].count("“") == row["vi"].count("”"), row["vi"]
        assert not re.search(r"[㐀-鿿]", row["vi"]), row["vi"]
    assert any("thương" in row["vi"] for row in rows) and any("súng" in row["vi"] for row in rows)
    print(f"07_make_booster_v3 OK — {len(rows)} câu")


def main() -> None:
    rows = build()
    OUT.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
    print(f"Sinh {len(rows)} câu booster -> {OUT}")
    for row in rows[:2] + rows[-2:]:
        print("  ", row["zh"], "->", row["vi"])


if __name__ == "__main__":
    import sys

    self_check() if "--self-check" in sys.argv else main()
