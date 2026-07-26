"""Cổng ghim term gợi ý: tên Trung khớp Hán-Việt, tên Tây giữ chữ Latin."""
from novelworker.db import _is_safe_pending_term


def term(correct_vi: str, term_type: str = "person", term_zh: str = "x") -> dict:
    return {"term_zh": term_zh, "correct_vi": correct_vi, "term_type": term_type}


def test_ten_trung_phai_khop_han_viet():
    assert _is_safe_pending_term(term("Long Ngạo Thiên"), "Long Ngạo Thiên")
    assert not _is_safe_pending_term(term("Long Ngạo Trời"), "Long Ngạo Thiên")


def test_ten_tay_giu_chu_latin_van_duoc_ghim():
    # hanviet(玛利亚) = "Mã Lợi Á" nhưng bản đúng là "Maria" — trước đây bị loại.
    assert _is_safe_pending_term(term("Maria"), "Mã Lợi Á")
    assert _is_safe_pending_term(term("Simon Elton"), "Tây Mông Ai Nhĩ Đốn")
    assert _is_safe_pending_term(term("GG-Captain"), None)


def test_khong_ghim_danh_tu_chung_bi_gan_nhan_person():
    # LLM hay gắn 爸爸/师父 là person; ghim lại thì mọi chỗ "cha" thành "Ba Ba".
    assert not _is_safe_pending_term(term("Ba Ba", term_zh="爸爸"), "Ba Ba")
    assert not _is_safe_pending_term(term("Sư Phụ", term_zh="师父"), "Sư Phụ")


def test_dia_danh_mon_phai_khong_duoc_huong_ngoai_le_latin():
    """Bug 26/07: ngoại lệ tên-Tây cho cả place/sect → 1137 term tiếng Anh dịch nghĩa lọt
    vào bản dịch (组织→"Organization", A基地→"A Base") rồi bị termguard cưỡng chế."""
    assert not _is_safe_pending_term(term("Organization", "sect", "组织"), "Tổ Chức")
    assert not _is_safe_pending_term(term("Youth League", "sect", "青年团"), "Thanh Niên Đoàn")
    assert not _is_safe_pending_term(term("A Base", "place", "A基地"), None)
    # nhưng địa danh KHỚP Hán-Việt vẫn qua (nhánh 1) — kể cả khi không có dấu
    assert _is_safe_pending_term(term("Giang Nam", "place", "江南"), "Giang Nam")


def test_ten_nguoi_qua_dai_la_cum_dich_nghia():
    assert _is_safe_pending_term(term("Mary Ann"), "Mã Lệ An")       # 2 từ: tên thật
    assert not _is_safe_pending_term(term("A City Central Hospital"), None)


def test_khong_ghim_ban_dich_nghia_hay_sai_loai():
    assert not _is_safe_pending_term(term("Dây chuyền Thiền Định", "item"), "Minh Tưởng Hạng Liên")
    assert not _is_safe_pending_term(term("chủ gia tộc Hoa"), "Hoa Gia Chủ")
    assert not _is_safe_pending_term(term(""), "Hoa Phong")
