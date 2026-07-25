"""Bộ chấm n-best: chọn giả thuyết sạch xưng hô/số/Hán thay vì giả thuyết xác suất cao nhất."""
from novelworker.translator.hachimi_engine import _rank_penalty


SOURCE = "他握紧长枪，转身离去。"


def best(source: str, *candidates: str) -> str:
    return min(candidates, key=lambda text: _rank_penalty(source, text))


def test_loai_dai_tu_hien_dai():
    assert best(SOURCE, "Tôi nắm chặt thương rồi rời đi.", "Hắn nắm chặt thương rồi rời đi.") \
        == "Hắn nắm chặt thương rồi rời đi."


def test_loai_ban_con_sot_chu_han():
    assert best(SOURCE, "Hắn nắm chặt 长枪 rồi đi.", "Hắn nắm chặt trường thương rồi đi.") \
        == "Hắn nắm chặt trường thương rồi đi."


def test_loai_ban_lam_hong_so():
    source = "他杀了3只妖兽。"
    assert best(source, "Hắn giết 5 con yêu thú.", "Hắn giết 3 con yêu thú.") == "Hắn giết 3 con yêu thú."


def test_khong_phat_quote_khi_nguon_da_lech():
    # Câu dài bị cắt: mảnh này chỉ có dấu mở, phạt mù sẽ chọn nhầm bản tệ hơn.
    source = "“我不去，"
    assert _rank_penalty(source, "“Ta không đi,") == _rank_penalty(source, "Ta không đi,")
