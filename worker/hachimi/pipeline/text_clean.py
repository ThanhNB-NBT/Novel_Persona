"""Chuẩn hoá nguồn ZH trước khi dịch: xoá dấu chống crawl bọc lẻ từng chữ.

Nguồn crawl chèn cặp dấu (『』 / 〖〗 …) quanh từng chữ để phá scraper. Chúng
KHÔNG phải nội dung nên phải xoá tất định trước khi đưa vào model — ở cả lúc
train (kaggle_train) lẫn lúc dịch thật (inference).
"""

from __future__ import annotations

import re


# Danh sách ký tự tàng hình / zero-width space / BOM do web chèn phá crawl
INVISIBLE_CHARS = ("\u200b", "\u200c", "\u200d", "\ufeff", "\u00ad", "\u200e", "\u200f", "\u202a", "\u202c")
_WRAPPED_HAN = re.compile(
    r"(?:(?<=[\u4e00-\u9fff])[『〖【〔〈⦅‹«]([\u4e00-\u9fff])[』〗】〕〉⦆›»]|"
    r"[『〖【〔〈⦅‹«]([\u4e00-\u9fff])[』〗】〕〉⦆›»](?=[\u4e00-\u9fff]))"
)
_RARE_WRAPPED_HAN = re.compile(r"[⦅‹«]([\u4e00-\u9fff])[⦆›»]")
_TRAILING_SLASH = re.compile(r"(?<=[\u3002\uff01\uff1f!?])/[ \t]*(?=\r?$)", re.M)
_EMPTY_BRACKETS = re.compile(r"^[ \t]*[\uff08(][ \t]*[\uff09)][ \t]*(?:\r?\n|\Z)", re.M)
_HAN_STAR = re.compile(r"(?<=[\u4e00-\u9fff])\*(?=[\u4e00-\u9fff])")
_PUNCT_RUN = re.compile(r"([\u3002\uff01\uff1f!?])[\u3002\uff01\uff1f!?]+")


def _balance_dialogue_quotes(text: str) -> str:
    """Đổi dấu mở `“` thứ hai thành dấu đóng khi nguồn gõ nhầm trong cùng dòng."""
    out: list[str] = []
    for line in text.splitlines(keepends=True):
        opened = False
        for char in line:
            if char == "\u201c":
                out.append("\u201d" if opened else char)
                opened = not opened
            elif char == "\u201d":
                out.append(char)
                opened = False
            else:
                out.append(char)
    return "".join(out)


def clean_source(text: str) -> str:
    """Tự động xoá dấu chống crawl bọc lẻ từng chữ và ký tự rác tàng hình, giữ nguyên nội dung."""
    if not text:
        return ""
    
    # 1. Xoá ký tự tàng hình / BOM
    for inv in INVISIBLE_CHARS:
        text = text.replace(inv, "")
    text = _balance_dialogue_quotes(text)
    text = _TRAILING_SLASH.sub("", text)
    text = _EMPTY_BRACKETS.sub("", text)
    text = _HAN_STAR.sub("", text)
    text = _PUNCT_RUN.sub(r"\1", text)

    # 2. Chỉ gỡ cặp chống crawl nằm GIỮA chuỗi Hán; giữ thoại và nhãn game hợp lệ.
    text = _RARE_WRAPPED_HAN.sub(r"\1", text)
    while (cleaned := _WRAPPED_HAN.sub(lambda m: m.group(1) or m.group(2), text)) != text:
        text = cleaned

    return text.strip()


if __name__ == "__main__":
    assert clean_source("脸上『露』出神『色』") == "脸上露出神色"
    assert clean_source("〖测〗试") == "测试"
    assert clean_source("  không có dấu  ") == "không có dấu"
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
