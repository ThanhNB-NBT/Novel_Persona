"""Mô tả truyện: bỏ rác nguồn trước khi dịch, và dịch bằng engine của truyện."""
from novelworker.translator.worker import _DESC_JUNK


def strip(text: str) -> str:
    return _DESC_JUNK.sub("", text).strip()


def test_bo_khoi_tieu_de_tac_gia_gioi_thieu():
    raw = "《《虚无至尊道》》作者:忘情至尊,简介:三世轮回的独孤风，剑祖。"
    assert strip(raw) == "三世轮回的独孤风，剑祖。"


def test_bo_loi_keu_goi_va_link():
    assert strip("本书又名《大佬》 剧情很好 求收藏求推荐 https://x.com/a") == "剧情很好"


def test_giu_nguyen_mo_ta_sach():
    raw = "女主网游。让我作间谍？凭啥？"
    assert strip(raw) == raw
