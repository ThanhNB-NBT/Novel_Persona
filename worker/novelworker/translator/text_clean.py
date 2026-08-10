"""Chuẩn hoá nguồn ZH trước khi dịch: xoá dấu chống crawl bọc lẻ từng chữ.

Bản runtime cho worker (song sinh với hachimi_finetune/text_clean.py dùng lúc
train trên Kaggle). Giữ hai bản đồng bộ khi sửa luật; đây là bản mà engine dịch
gọi thật ở inference.
"""
from __future__ import annotations

import re

# Ký tự tàng hình / zero-width / BOM do web chèn phá crawl.
INVISIBLE_CHARS = ("​", "‌", "‍", "﻿", "­", "‎", "‏", "‪", "‬")
_WRAPPED_HAN = re.compile(
    r"(?:(?<=[一-鿿])[『〖【〔〈⦅‹«]([一-鿿])[』〗】〕〉⦆›»]|"
    r"[『〖【〔〈⦅‹«]([一-鿿])[』〗】〕〉⦆›»](?=[一-鿿]))"
)
_RARE_WRAPPED_HAN = re.compile(r"[⦅‹«]([一-鿿])[⦆›»]")
_TRAILING_SLASH = re.compile(r"(?<=[。！？!?])/[ \t]*(?=\r?$)", re.M)
_EMPTY_BRACKETS = re.compile(r"^[ \t]*[（(][ \t]*[）)][ \t]*(?:\r?\n|\Z)", re.M)
_HAN_STAR = re.compile(r"(?<=[一-鿿])\*(?=[一-鿿])")
_PUNCT_RUN = re.compile(r"([。！？!?])[。！？!?]+")
# Nhãn hệ thống/bảng thông số bọc 〈…〉 〖…〗 〔…〕: model quen nhãn game 【…】 (giữ sạch),
# ngoặc lạ thì nó dịch 〈 ra "·", 〖 ra "flash"/"fan" và 〗 ra "Ặc"/"Răng" — đo truyện 2163:
# 31/31 dòng bảng thông số 〖〗 hỏng. Đồng nhất về 【…】 trước khi nạp vào model.
_ANGLE_LABEL = re.compile(r"[〈〖〔]([^〈〉〖〗〔〕\n]*)[〉〗〕]")
# Nguồn hay gõ thừa ：/； ngay trước ngoặc đóng (〖姓名：洪均：〗) → bỏ cho hết dấu lơ lửng.
_LABEL_TAIL = re.compile(r"[：；:;]+(?=】)")
# Lời nhắn của tác giả xen giữa truyện (xin vé, xin quảng cáo, cảm ơn quà). Không phải văn
# truyện, dịch ra chỉ tổ vỡ; riêng 【咕叽咕叽～点催更哦！】 còn làm model lặp tới trần token
# và giết cả chương 158 truyện 2163. Chỉ xoá khi dòng BỌC TRỌN trong 【…】 hoặc mở đầu bằng
# "ps:" — câu kể có chữ 催更/广告 (江宇苍龙体全力催更…) không dính.
_NOTE_KEYS = re.compile(r"催更|广告|好评|礼物|打赏|月票|推荐票|求票|订阅|加更|鲜花")
_AUTHOR_NOTE = re.compile(r"^[ \t]*(?:[Pp][SsDd][:：].*|【[^【】\n]*】)[ \t]*$")


def _balance_dialogue_quotes(text: str) -> str:
    """Đổi dấu mở `“` thứ hai thành dấu đóng khi nguồn gõ nhầm trong cùng dòng."""
    out: list[str] = []
    for line in text.splitlines(keepends=True):
        opened = False
        for char in line:
            if char == "“":
                out.append("”" if opened else char)
                opened = not opened
            elif char == "”":
                out.append(char)
                opened = False
            else:
                out.append(char)
    return "".join(out)


def _is_author_note(line: str) -> bool:
    return bool(_AUTHOR_NOTE.match(line) and _NOTE_KEYS.search(line))


def clean_source(text: str) -> str:
    """Xoá dấu chống crawl bọc lẻ từng chữ và ký tự rác tàng hình, giữ nguyên nội dung."""
    if not text:
        return ""
    for inv in INVISIBLE_CHARS:
        text = text.replace(inv, "")
    text = _balance_dialogue_quotes(text)
    text = _TRAILING_SLASH.sub("", text)
    text = _EMPTY_BRACKETS.sub("", text)
    text = _HAN_STAR.sub("", text)
    text = _PUNCT_RUN.sub(r"\1", text)
    text = _ANGLE_LABEL.sub(r"【\1】", text)
    text = _LABEL_TAIL.sub("", text)
    text = "\n".join(line for line in text.split("\n") if not _is_author_note(line))
    # Chỉ gỡ cặp chống crawl nằm GIỮA chuỗi Hán. Không đụng thoại “哼！”,
    # nhãn game 【提示】 hay ngoặc sách hợp lệ.
    text = _RARE_WRAPPED_HAN.sub(r"\1", text)
    while (cleaned := _WRAPPED_HAN.sub(lambda m: m.group(1) or m.group(2), text)) != text:
        text = cleaned
    return text.strip()


if __name__ == "__main__":
    assert clean_source("脸上『露』出神『色』") == "脸上露出神色"
    assert clean_source("⦅一⦆⦅下⦆") == "一下"
    assert clean_source("‹是›") == "是"
    assert clean_source("“哼！”") == "“哼！”"
    assert clean_source("【提示】") == "【提示】"
    assert clean_source("〈叮！〉") == "【叮！】"
    assert clean_source("〈机缘暴击系统绑定中……〉") == "【机缘暴击系统绑定中……】"
    # Bảng thông số 〖…〗 → 【…】, bỏ luôn dấu ： thừa trước ngoặc đóng.
    assert clean_source("〖姓名：洪均：〗") == "【姓名：洪均】"
    assert clean_source("〖体质：九炎雷体【已激活50％】：〗") == "【体质：九炎雷体【已激活50％】】"
    assert clean_source("〔提示〕") == "【提示】"
    # Lời nhắn tác giả bị xoá; câu kể có cùng chữ thì KHÔNG.
    assert clean_source("【帮点点催更呗！】") == ""
    assert clean_source("【咕叽咕叽～点催更哦！】") == ""
    assert clean_source("〖帮看个免费广告呗……〗") == ""
    assert clean_source("ps：感谢【秀儿】的礼物") == ""
    assert clean_source("江宇苍龙体全力催更，鳞甲发出光芒。") == "江宇苍龙体全力催更，鳞甲发出光芒。"
    assert clean_source("【不过是小疼而已，这一点点疼痛我还是能……】").startswith("【不过")
    assert clean_source("甲。\n【帮点催更！】\n乙。") == "甲。\n乙。"
    assert clean_source("脸〈色〉苍白") == "脸色苍白"  # chống-crawl giữa Hán vẫn gỡ sạch
    assert clean_source("“回房间休息吧“，她说道！") == "“回房间休息吧”，她说道！"
    assert clean_source("“甲。”“乙。”") == "“甲。”“乙。”"
    assert clean_source("厅下都在议论！/\n( )") == "厅下都在议论！"
    assert clean_source("埃尔顿*希里说道。") == "埃尔顿希里说道。"
    assert clean_source("好。!!别担心。") == "好。别担心。"
    assert clean_source("图纸*1") == "图纸*1"
    assert clean_source("\u200b测试\ufeff") == "测试"
    print("text_clean OK")
