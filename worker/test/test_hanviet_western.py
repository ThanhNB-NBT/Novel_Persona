"""Tên Tây phiên qua tiếng Trung phải giữ chữ Latin; tên Trung vẫn ép Hán-Việt."""
from novelworker.translator.hanviet import looks_western, reconcile, transliteration_suspect


def test_nhan_dang_ten_phien_am():
    assert looks_western("埃尔顿")      # Elton
    assert looks_western("玛利亚")      # Maria
    assert looks_western("索菲娅")      # Sophia
    assert looks_western("罗林·埃尔顿")  # có dấu chấm giữa tên
    assert not looks_western("龙傲天")
    assert not looks_western("华凝霜")
    assert not looks_western("长生仙尊")
    # Tên/địa danh Trung tuy toàn chữ nằm trong bảng phiên âm vẫn phải giữ Hán-Việt.
    assert not looks_western("林黛玉")
    assert not looks_western("李希希")
    assert not looks_western("马夫人")
    assert not looks_western("哈尔滨")
    assert not looks_western("内蒙古")
    # Dấu chấm giữa cụm không đủ: tên chiêu thức và tựa sách cũng dùng nó.
    assert not looks_western("内力型·瞬身")
    assert not looks_western("人教版·领主驭下宝典")
    assert looks_western("托尼·斯塔克")


def test_giu_ten_tay_nhieu_tu():
    assert reconcile("西蒙·埃尔顿", "Simon Elton", "person") == "Simon Elton"
    assert reconcile("玛利亚", "Maria", "person") == "Maria"
    assert not transliteration_suspect("玛利亚", "Maria", "person")


def test_van_sua_pinyin_cua_ten_trung():
    # "Long Aotian" là pinyin, không phải tên Tây → bảng tra vẫn sửa.
    assert reconcile("龙傲天", "Long Aotian", "person") == "Long Ngạo Thiên"
    assert reconcile("龙傲天", "Long Ngao Thien", "person") == "Long Ngạo Thiên"
