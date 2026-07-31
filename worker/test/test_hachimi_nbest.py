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


def test_loai_ban_bia_chu_ngu():
    # 开口说道 lược chủ ngữ: model hay tự thêm "Hắn/Nàng" rồi đoán giới bừa.
    source = "开口说道：“不必了。”"
    assert best(source, "Nàng mở miệng nói: “Không cần đâu.”", "Mở miệng nói: “Không cần đâu.”") \
        == "Mở miệng nói: “Không cần đâu.”"


def test_giu_chu_ngu_khi_nguon_that_su_co_dai_tu():
    # Nguồn có 他 thì "Hắn" là dịch đúng, không được phạt.
    assert _rank_penalty(SOURCE, "Hắn nắm chặt thương rồi rời đi.") \
        == _rank_penalty(SOURCE, "Nắm chặt thương rồi rời đi.")


def test_ho_khong_tinh_la_chu_ngu_so_it():
    # 他们 = "bọn họ"; nguồn vẫn lược chủ ngữ nên "Nàng" vẫn là bịa.
    source = "开口回应：“原本他们三天前就想让我回去的。”"
    assert best(source, "Nàng mở miệng đáp: “Vốn bọn họ ba ngày trước đã muốn ta về.”",
                "Mở miệng đáp: “Vốn bọn họ ba ngày trước đã muốn ta về.”") \
        == "Mở miệng đáp: “Vốn bọn họ ba ngày trước đã muốn ta về.”"


def test_dai_tu_trong_thoai_khong_cuu_duoc_chu_ngu_bia():
    # 他 nằm trong lời thoại là người thứ ba nhân vật nhắc tới, không phải chủ ngữ câu kể.
    source = "怒声道：“将他的四肢打断。”"
    assert best(source, "Hắn tức giận nói: “Đánh gãy tứ chi của hắn.”",
                "Tức giận nói: “Đánh gãy tứ chi của hắn.”") \
        == "Tức giận nói: “Đánh gãy tứ chi của hắn.”"


def test_khong_phat_quote_khi_nguon_da_lech():
    # Câu dài bị cắt: mảnh này chỉ có dấu mở, phạt mù sẽ chọn nhầm bản tệ hơn.
    source = "“我不去，"
    assert _rank_penalty(source, "“Ta không đi,") == _rank_penalty(source, "Ta không đi,")
