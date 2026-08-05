"""Bộ chấm n-best: chọn giả thuyết sạch xưng hô/số/Hán thay vì giả thuyết xác suất cao nhất."""
from novelworker.translator.hachimi_engine import _fix_lead_gender, _rank_penalty


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


def test_uu_tien_nam_tu_hon_nguoi_dan_ong():
    # 男子 → "nam tử" (register tiên hiệp), không phải "người đàn ông" (convert hiện đại).
    source = "两名中年男子快速走了过来。"
    assert best(source, "Hai người đàn ông trung niên bước tới.", "Hai nam tử trung niên bước tới.") \
        == "Hai nam tử trung niên bước tới."


def test_soft_modern_khong_de_len_bia_chu_ngu():
    # Phạt danh từ (4) phải NHẸ hơn bịa chủ ngữ (6): thà giữ "người đàn ông" còn hơn bịa "Hắn".
    source = "将目光投向了左侧男子。"  # lược chủ ngữ
    assert best(source, "Hắn đưa mắt nhìn gã đàn ông bên trái.",
                "Ánh mắt đổ dồn về phía người đàn ông bên trái.") \
        == "Ánh mắt đổ dồn về phía người đàn ông bên trái."


def test_khong_phat_quote_khi_nguon_da_lech():
    # Câu dài bị cắt: mảnh này chỉ có dấu mở, phạt mù sẽ chọn nhầm bản tệ hơn.
    source = "“我不去，"
    assert _rank_penalty(source, "“Ta không đi,") == _rank_penalty(source, "Ta không đi,")


# --- ép giới đại từ mở đầu (_fix_lead_gender) ---

def test_ep_gioi_nam_ra_nang():
    # Nguồn 他 (nam) mà bản dịch mở "Nàng" → ép về "Hắn".
    assert _fix_lead_gender("他握紧长枪。", "Nàng nắm chặt trường thương.") \
        == "Hắn nắm chặt trường thương."


def test_ep_gioi_nu_ra_han():
    # Nguồn 她 (nữ) mà bản dịch mở "Hắn/Y/Gã" → ép về "Nàng".
    assert _fix_lead_gender("她转身离去。", "Gã xoay người rời đi.") == "Nàng xoay người rời đi."


def test_khong_dung_khi_dung_gioi():
    # Đúng giới thì giữ nguyên (không đổi Ả→Nàng khi nguồn là 她).
    assert _fix_lead_gender("她冷笑。", "Ả cười lạnh.") == "Ả cười lạnh."
    assert _fix_lead_gender("他大笑。", "Hắn cười lớn.") == "Hắn cười lớn."


def test_khong_dung_khi_nguon_luoc_chu_ngu():
    # Nguồn không có đại từ giới ở lời kể → không ép (để cổng bịa-chủ-ngữ lo).
    assert _fix_lead_gender("开口说道：“不必了。”", "Nàng mở miệng nói: “Không cần.”") \
        == "Nàng mở miệng nói: “Không cần.”"


def test_ho_so_nhieu_khong_kich_hoat():
    # 他们 = "bọn họ" (số nhiều) — không phải chủ ngữ số ít, không ép giới.
    assert _fix_lead_gender("他们走了过来。", "Nàng bọn họ bước tới.") == "Nàng bọn họ bước tới."


def test_dai_tu_trong_thoai_khong_kich_hoat():
    # 他 nằm trong thoại, lời kể lược chủ ngữ → không lấy làm căn cứ ép giới.
    assert _fix_lead_gender("怒声道：“打断他。”", "Nàng tức giận nói: “Đánh gãy hắn.”") \
        == "Nàng tức giận nói: “Đánh gãy hắn.”"
