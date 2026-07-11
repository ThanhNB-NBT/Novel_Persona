from eval_translation import _dialogue_self_minh, _self_reference_omissions, lint, narrator_terms


def test_self_reference_omission():
    assert _self_reference_omissions("老夫不答应。", "Ta không đồng ý.")
    assert not _self_reference_omissions("老夫不答应。", "Lão phu không đồng ý.")


def test_narrator_terms_ignore_dialogue():
    assert narrator_terms('Hắn quay đi. “Lão tử không sợ!” Nàng im lặng.') == {
        "hắn": 1,
        "nàng": 1,
    }


def test_convertese_warning():
    assert any("không khỏi" in problem for problem in lint("他笑了。", "Hắn không khỏi bật cười."))


# feedback user 2026-07-11 (bộ Q0 đầu tiên)

def test_mot_dau_measure_word():
    assert any("một đầu" in p for p in lint("一头魔龙。", "Một đầu ma long kinh khủng."))
    assert not any("một đầu" in p for p in lint("首先。", "Một đầu tiên là vậy."))


def test_pinyin_leak():
    assert any("pinyin" in p for p in lint("狼牙棒。", "Cây lāng yá bàng."))


def test_chang_density():
    assert any("'chẳng'" in p for p in lint("。", "Chẳng ai. Chẳng thể. Chẳng còn. Chẳng biết."))
    assert not any("'chẳng'" in p for p in lint("。", "Chẳng ai tin nổi."))


def test_dialogue_self_minh():
    assert _dialogue_self_minh('“Mình chắc chắn đã bỏ lỡ điều gì đó.”')
    assert not _dialogue_self_minh('“Chúng mình đi thôi, của mình đây.”')
    assert not _dialogue_self_minh("Nàng nghĩ về chính mình đã từng.")


def test_gia_toc_style():
    assert any("gia tộc" in p for p in lint("洛家。", "Gia tộc Lạc không đồng ý."))


# lỗi tự tìm thấy khi đọc 5 file baseline chưa được user chấm (2026-07-12)

def test_transliteration_fuse():
    """n1052: cả chương phiên âm Hán-Việt từng chữ, 0% chữ Hán nên fuse cũ lọt."""
    from novelworker.translator.worker import check_translation
    translit = ("Vân Ẩn quần sơn chiếm địa thiên lý, chủ phong cao sủng nhập vân, "
                "thường niên vân vụ liễu nhiễu, do như tiên cảnh! Lạc Ly thán hơi "
                "nhất thanh, song mục mãn thị ngưng trọng, chúng nhân giai thị hữu "
                "đại sự phát sinh, thử tam nhân kỳ trung nhất nhân tức thị tự kỷ. ") * 8
    problem = check_translation("原文" * 200, translit)
    assert problem and "phiên âm" in problem, problem
    real = ("Hắn nhìn quanh bốn phía, mục đích của chuyến đi này là tìm linh dược. "
            "Giai đoạn đầu tu luyện tốn không ít chi phí, nhưng theo nguyên tắc của "
            "tông môn, đệ tử nội môn được cấp linh thạch hàng tháng. Nàng khẽ gật đầu, "
            "đưa cho hắn một chiếc túi gấm, bên trong là hài nhi thảo vừa hái sáng nay. ") * 8
    assert check_translation("原文" * 100, real) is None


def test_english_onomatopoeia():
    assert any("tượng thanh" in p for p in lint("咳咳。", '"Cough cough, thôi đi."'))


def test_han_residue_single_char():
    assert any("Hán sót lẻ" in p for p in lint("门外传来。", "Bên ngoài cửa truyền来 tiếng ồn."))


def test_style_flags_and_apply():
    from novelworker.translator.worker import _apply_fixes, _style_flags
    vi = ('Hắn chẳng thể tin nổi. "Ngài cần phu nhân chăng?" Chẳng lẽ vậy sao?\n'
          "Nàng gật đầu một cái rồi rời đi.")
    flags = _style_flags(vi)
    flagged = " | ".join(s for s, _ in flags)
    assert "chẳng thể tin" in flagged and "chăng?" in flagged and "gật đầu một cái" in flagged
    assert all("Chẳng lẽ vậy sao" not in s for s, _ in flags)  # 'chẳng lẽ' hợp lệ
    fixed, n = _apply_fixes(vi, [
        {"old": "Hắn chẳng thể tin nổi.", "new": "Hắn không thể tin nổi."},
        {"old": "không có trong bản dịch", "new": "bị bỏ qua"},
        {"old": "Nàng gật đầu một cái rồi rời đi.", "new": "Nàng gật đầu rồi rời đi."},
    ])
    assert n == 2 and "không thể tin" in fixed and "gật đầu rồi rời đi" in fixed


def test_style_revise_with_fake_llm():
    from novelworker.translator.worker import _style_revise

    class FakeRes:
        text = '[{"old": "Hắn chẳng nói gì.", "new": "Hắn không nói gì."}]'

    class FakeLLM:
        def complete(self, system, user, **kw):
            assert "CÂU:" in user
            return FakeRes()

    assert _style_revise(FakeLLM(), "Hắn chẳng nói gì.") == "Hắn không nói gì."
    # không có câu lỗi → không gọi LLM, trả nguyên văn
    class Boom:
        def complete(self, *a, **k):
            raise AssertionError("không được gọi")
    assert _style_revise(Boom(), "Hắn im lặng rời đi.") == "Hắn im lặng rời đi."
