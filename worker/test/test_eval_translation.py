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


def test_fix_soft_style_chang():
    from novelworker.translator.worker import _fix_soft_style
    out = _fix_soft_style("Hắn chẳng nói. Chẳng ai tin. Chẳng lẽ vậy sao? Nó chẳng qua là mơ.")
    assert out == "Hắn không nói. Không ai tin. Chẳng lẽ vậy sao? Nó chẳng qua là mơ."


def test_style_flags_and_apply():
    from novelworker.translator.worker import _apply_fixes, _style_flags
    vi = ('"Ngài cần phu nhân chăng?" "Mình chắc chắn đã bỏ lỡ gì đó."\n'
          "Nàng gật đầu một cái rồi rời đi. Hắn im lặng.")
    flags = _style_flags(vi)
    flagged = " | ".join(s for s, _ in flags)
    assert "chăng?" in flagged and "Mình chắc chắn" in flagged and "một cái" in flagged
    assert all("Hắn im lặng" not in s for s, _ in flags)
    fixed, n = _apply_fixes(vi, [
        {"old": '"Ngài cần phu nhân chăng?"', "new": '"Ngài có cần phu nhân không?"'},
        {"old": "không có trong bản dịch", "new": "bị bỏ qua"},
        {"old": "Nàng gật đầu một cái rồi rời đi.", "new": "Nàng gật đầu rồi rời đi."},
    ])
    assert n == 2 and "có cần phu nhân không" in fixed and "gật đầu rồi rời đi" in fixed


def test_style_line_and_narrator_term():
    from novelworker.translator import prompts
    line = prompts.build_style_line({
        "pov": "ngôi ba", "setting": "tu tiên cổ đại", "han_viet": "đậm",
        "tone": "gọn, lạnh", "rules": ["hệ thống nói giọng tưng tửng"]})
    assert "ngôi ba" in line and "tu tiên cổ đại" in line and "tưng tửng" in line
    assert prompts.build_style_line(None) is None
    assert prompts.build_style_line({}) is None
    system = prompts.build_chapter_system(
        [{"term_zh": "洛离", "correct_vi": "Lạc Ly", "term_type": "person",
          "note": "nam, thiếu niên", "narrator_term": "y"}], "洛离睁开双目")
    assert "[người kể gọi: y]" in system
    user = prompts.build_chapter_user(None, "原文", style_line="[Văn phong truyện: X]")
    assert "[Văn phong truyện: X]" in user


def test_scene_line_and_analyze_shapes():
    from novelworker.translator import prompts
    from novelworker.translator.worker import _analyze_names
    line = prompts.build_scene_line({
        "speakers": [
            {"speaker": "Lâm Tùng", "addressee": "lão giả", "self_term": "vãn bối",
             "address_term": "tiền bối", "tone": "cung kính"},
            {"speaker": "?", "addressee": "Lâm Tùng"},  # uncertain → bỏ
        ],
        "pov": "ngôi ba bám theo Lâm Tùng"})
    assert "Lâm Tùng nói với lão giả" in line and "vãn bối" in line
    assert line.count("nói với") == 1
    assert prompts.build_scene_line(None) is None
    assert prompts.build_scene_line({"speakers": []}) is None

    class FakeLLM:
        def __init__(self, text):
            self._t = text
        def complete(self, *a, **k):
            return type("R", (), {"text": self._t})()

    # shape object mới
    terms, scene = _analyze_names(FakeLLM(
        '{"terms": [{"zh": "林松", "vi": "Lâm Tùng"}], "speakers": [], "pov": "ngôi ba"}'), "x")
    assert terms[0]["vi"] == "Lâm Tùng" and scene["pov"] == "ngôi ba"
    # shape mảng cũ vẫn nhận
    terms, scene = _analyze_names(FakeLLM('[{"zh": "林松", "vi": "Lâm Tùng"}]'), "x")
    assert terms and scene is None
    # rác → không vỡ
    assert _analyze_names(FakeLLM("not json"), "x") == ([], None)


def test_style_revise_with_fake_llm():
    from novelworker.translator.worker import _style_revise

    class FakeRes:
        text = '[{"old": "Ngài cần phu nhân chăng?", "new": "Ngài có cần phu nhân không?"}]'

    class FakeLLM:
        def complete(self, system, user, **kw):
            assert "CÂU:" in user
            return FakeRes()

    assert _style_revise(FakeLLM(), "Ngài cần phu nhân chăng?") == "Ngài có cần phu nhân không?"
    # không có câu lỗi → không gọi LLM, trả nguyên văn
    class Boom:
        def complete(self, *a, **k):
            raise AssertionError("không được gọi")
    assert _style_revise(Boom(), "Hắn im lặng rời đi.") == "Hắn im lặng rời đi."
