"""Chuẩn hoá nguồn ZH trước khi dịch: xoá dấu chống crawl bọc lẻ từng chữ.

Nguồn crawl chèn cặp dấu (『』 / 〖〗 …) quanh từng chữ để phá scraper. Chúng
KHÔNG phải nội dung nên phải xoá tất định trước khi đưa vào model — ở cả lúc
train (kaggle_train) lẫn lúc dịch thật (inference). Đây là single source of
truth cho việc đó; thêm dấu mới chỉ cần bổ sung vào ANTI_CRAWL_MARKS.
"""

from __future__ import annotations

import re


# Dấu chống crawl bọc-lẻ cố định. Thêm dấu mới ở đây hoặc để hàm tự phát hiện.
ANTI_CRAWL_MARKS = ("『", "』", "〖", "〗", "【", "】", "〔", "〕", "〈", "〉", "⦅", "⦆", "‹", "›", "«", "»")

# Danh sách ký tự tàng hình / zero-width space / BOM do web chèn phá crawl
INVISIBLE_CHARS = ("\u200b", "\u200c", "\u200d", "\ufeff", "\u00ad", "\u200e", "\u200f", "\u202a", "\u202c")


def clean_source(text: str) -> str:
    """Tự động xoá dấu chống crawl bọc lẻ từng chữ và ký tự rác tàng hình, giữ nguyên nội dung."""
    if not text:
        return ""
    
    # 1. Xoá ký tự tàng hình / BOM
    for inv in INVISIBLE_CHARS:
        text = text.replace(inv, "")

    # 2. Tự động xoá các cặp dấu bọc lẻ ĐÚNG 1 chữ Hán (ngoặc kép/vuông/tròn/nhọn bất kỳ)
    # Ví dụ: 脸上『露』出神『色』 -> 脸上露出神色, ⦅一⦆⦅下⦆ -> 一下
    text = re.sub(r'([^\w\s\u4e00-\u9fff\n])([\u4e00-\u9fff])([^\w\s\u4e00-\u9fff\n])', r'\2', text)

    # 3. Fallback xoá các dấu cố định thuộc ANTI_CRAWL_MARKS nếu còn sót
    for mark in ANTI_CRAWL_MARKS:
        text = text.replace(mark, "")

    return text.strip()


if __name__ == "__main__":
    assert clean_source("脸上『露』出神『色』") == "脸上露出神色"
    assert clean_source("〖测〗试") == "测试"
    assert clean_source("  không có dấu  ") == "không có dấu"
    assert clean_source("⦅一⦆⦅下⦆") == "一下"
    assert clean_source("‹是›") == "是"
    assert clean_source("\u200b测试\ufeff") == "测试"
    print("text_clean OK")

