"""Chuẩn hoá nguồn ZH trước khi dịch: xoá dấu chống crawl bọc lẻ từng chữ.

Bản runtime cho worker (song sinh với hachimi_finetune/text_clean.py dùng lúc
train trên Kaggle). Giữ hai bản đồng bộ khi sửa luật; đây là bản mà engine dịch
gọi thật ở inference.
"""
from __future__ import annotations

import re

# Dấu chống crawl bọc-lẻ cố định. Thêm dấu mới ở đây hoặc để hàm tự phát hiện.
ANTI_CRAWL_MARKS = ("『", "』", "〖", "〗", "【", "】", "〔", "〕", "〈", "〉", "⦅", "⦆", "‹", "›", "«", "»")

# Ký tự tàng hình / zero-width / BOM do web chèn phá crawl.
INVISIBLE_CHARS = ("​", "‌", "‍", "﻿", "­", "‎", "‏", "‪", "‬")


def clean_source(text: str) -> str:
    """Xoá dấu chống crawl bọc lẻ từng chữ và ký tự rác tàng hình, giữ nguyên nội dung."""
    if not text:
        return ""
    for inv in INVISIBLE_CHARS:
        text = text.replace(inv, "")
    # Cặp dấu bọc lẻ ĐÚNG 1 chữ Hán: 脸上『露』出神『色』 -> 脸上露出神色
    text = re.sub(r"([^\w\s一-鿿\n])([一-鿿])([^\w\s一-鿿\n])", r"\2", text)
    for mark in ANTI_CRAWL_MARKS:
        text = text.replace(mark, "")
    return text.strip()
