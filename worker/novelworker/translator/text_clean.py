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
    assert clean_source("“回房间休息吧“，她说道！") == "“回房间休息吧”，她说道！"
    assert clean_source("“甲。”“乙。”") == "“甲。”“乙。”"
    assert clean_source("厅下都在议论！/\n( )") == "厅下都在议论！"
    assert clean_source("埃尔顿*希里说道。") == "埃尔顿希里说道。"
    assert clean_source("好。!!别担心。") == "好。别担心。"
    assert clean_source("图纸*1") == "图纸*1"
    assert clean_source("\u200b测试\ufeff") == "测试"
    print("text_clean OK")
