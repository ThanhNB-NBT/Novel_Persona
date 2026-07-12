from eval_translation import _dialogue_self_minh, _self_reference_omissions, lint, narrator_terms


def test_self_reference_omission():
    assert _self_reference_omissions("老夫不答应。", "Ta không đồng ý.")
    assert not _self_reference_omissions("老夫不答应。", "Lão phu không đồng ý.")


def test_self_reference_no_false_block():
    """Từ ghép trùng mặt chữ không được tính là tự xưng — check này từng gây oan."""
    assert not _self_reference_omissions("他站在下面看着。", "Hắn đứng phía dưới nhìn lên.")
    assert not _self_reference_omissions("他们是老夫老妻了。", "Bọn họ là vợ chồng già rồi.")
    assert not _self_reference_omissions("晚辈不敢。", "Hậu bối không dám.")
    assert not _self_reference_omissions("分身与本尊汇合。", "Phân thân hợp nhất với chân thân.")
    assert _self_reference_omissions("在下告辞。", "Ta xin cáo từ.")  # tự xưng thật vẫn bắt


def test_quality_fuse_does_not_block_omission():
    """Omission KHÔNG nằm trong fuse: retry mù không chữa được model lì (n1007 kẹt
    3/3 lượt → job fail vĩnh viễn). Lượt _fix_omissions sửa có mục tiêu sau dịch."""
    from novelworker.translator.worker import _quality_fuse
    res = type("R", (), {"text": "Hắn không đồng ý. " * 30, "model": "test"})()
    _quality_fuse("老夫不答应。" * 30)(res)  # không raise


def test_scene_line_drops_none_addressee():
    """addressee=None từng lọt thành 'X nói với None' trong prompt (P2-7)."""
    from novelworker.translator.prompts import build_scene_line
    assert build_scene_line({"speakers": [{"speaker": "Lâm Tùng", "addressee": None}]}) is None
    out = build_scene_line({"speakers": [
        {"speaker": "Lâm Tùng", "addressee": "lão giả", "self_term": "vãn bối"}]})
    assert "Lâm Tùng nói với lão giả" in out and "None" not in out


def test_clean_style_drops_junk():
    """Style bible JSON rác không được sống xuyên truyện (P2-8)."""
    from novelworker.translator.worker import _clean_style
    st = _clean_style({"pov": "ngôi ba", "junk": "x" * 999, "rules": ["a", 5, "b" * 200]})
    assert st == {"pov": "ngôi ba", "rules": ["a", "b" * 120]}
    assert _clean_style("không phải dict") is None
    assert _clean_style({"junk": 1}) is None


def test_merge_scene_relations():
    """Cặp đã chốt đè lên đoán mới; cặp mới có term thì trả về để lưu (P1-4)."""
    from novelworker.translator.worker import _merge_scene_relations
    relations = {("A", "B"): {"self_term": "vi sư", "address_term": "đồ nhi"}}
    scene = {"speakers": [
        {"speaker": "A", "addressee": "B", "self_term": "ta", "address_term": "ngươi"},
        {"speaker": "C", "addressee": "D", "self_term": "tại hạ"},
        {"speaker": "E", "addressee": None, "self_term": "ta"},
    ]}
    new = _merge_scene_relations(relations, scene, 7, 12)
    assert scene["speakers"][0]["self_term"] == "vi sư"  # bản lưu thắng
    assert new == [{"novel_id": 7, "speaker": "C", "addressee": "D", "self_term": "tại hạ",
                    "address_term": None, "tone": None, "last_chapter": 12}]
    assert ("C", "D") in relations  # chunk sau cùng chương cũng dùng ngay


def test_register_violation_ta_threshold():
    """'ta' lẻ tẻ = nghĩ thầm không ngoặc (hợp lệ); dày ≥3 = trôi POV (bug n1007 v3)."""
    from novelworker.translator.worker import _register_violation
    assert _register_violation("Xem ra ta đã tái sinh. Hắn đứng dậy.") is None
    assert _register_violation("Ta đi tới. Ta nhìn quanh. Ta thở dài.") is not None
    assert _register_violation("Anh ta cười.") is not None  # cụm không thể nhầm: chặn từ 1
    assert _register_violation("Tôi đi. Tôi về. Tôi ngủ.", allow_toi=True) is None


def test_apply_line_fixes_accepts_wrapped_object():
    from novelworker.translator.worker import _apply_line_fixes
    vi = "Hắn cười lớn.\nHắn đi ra ngoài."
    fixed, applied = _apply_line_fixes(vi, {"fixes": [{"line": 2, "new": "Rồi đi ra ngoài."}]})
    assert applied == 1 and fixed.endswith("Rồi đi ra ngoài.")


def test_apply_line_fixes_accepts_old_new_format():
    """SYSTEM_REVISE cũ dạy old/new — model trả kiểu đó vẫn phải áp được (v5: 0 câu thay)."""
    from novelworker.translator.worker import _apply_line_fixes
    vi = "Hắn cười lớn.\nHắn không khỏi thở dài."
    fixed, applied = _apply_line_fixes(
        vi, [{"old": "Hắn không khỏi thở dài.", "new": "Hắn bất giác thở dài."}])
    assert applied == 1 and fixed.endswith("Hắn bất giác thở dài.")


def test_fix_soft_style_convertese():
    """'không khỏi'/'tổng cảm thấy' lì đòn → vá máy móc, không phó mặc LLM revise (v4)."""
    from novelworker.translator.worker import _fix_soft_style
    assert _fix_soft_style("Diệp Lăng không khỏi thở dài.") == "Diệp Lăng thở dài."
    assert _fix_soft_style("Không khỏi bật cười.") == "Bật cười."
    # nghĩa thật (y học/kết quả) phải giữ nguyên
    assert _fix_soft_style("Bệnh này chữa không khỏi.") == "Bệnh này chữa không khỏi."
    assert _fix_soft_style("Hắn lo mãi không khỏi bệnh.") == "Hắn lo mãi không khỏi bệnh."
    assert _fix_soft_style("Tổng cảm thấy có gì đó sai.") == "Cứ cảm thấy có gì đó sai."


def test_revise_rule_han_repeat_any_distance():
    """Luật lặp 'hắn' của worker phải khớp evaluator: ≥3/câu kể cả cách nhau >60 ký tự."""
    from novelworker.translator.worker import _style_flags
    sent = ("Hắn vẫn còn nhớ rõ cảnh hoàng đế nghe tin con gái yêu bị một kẻ bạc phận "
            "tam đẳng bá tước như hắn hủy hoại thanh danh, định lăng trì xử hắn.")
    assert any("lặp 'hắn'" in issue for _, issue in _style_flags(sent))
    assert not any("lặp 'hắn'" in issue
                   for _, issue in _style_flags("Hắn cười. Hắn đi. Hắn ngủ."))


def test_han_repeat_not_across_paragraphs():
    """'.”' và xuống dòng phải kết thúc câu — từng dính oan 3 'hắn' vắt qua 2 đoạn."""
    from eval_translation import _han_repeat_density
    assert not _han_repeat_density("hóa ra hắn thật sự tái sinh.”\n\nHắn không tin. Hắn im lặng.")
    assert _han_repeat_density("Hắn nhìn hắn rồi hắn cười.")


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


def test_quality_fuse_blocks_any_han_residue():
    from novelworker.translator.worker import check_translation
    assert "ký tự Hán" in check_translation("衣服写着囚字。", 'Áo viết chữ "囚".')


def test_fix_register_bare_anh_in_narration_only():
    from novelworker.translator.worker import _fix_register
    text = 'Linh hồn anh chiếm lấy thân xác. Anh nhìn quanh. "Anh đi đâu?" Một vị anh hùng tới.'
    assert _fix_register(text) == 'Linh hồn hắn chiếm lấy thân xác. Hắn nhìn quanh. "Anh đi đâu?" Một vị anh hùng tới.'


def test_third_person_rejects_narrator_ta_but_not_dialogue():
    from novelworker.translator.worker import _register_line, _register_violation
    # 'ta' trong thoại không tính; lời kể chỉ chặn khi dày ≥3 (nghĩ thầm lẻ tẻ hợp lệ)
    assert _register_violation('Ta nhìn quanh. Ta bước đi. Ta dừng lại. "Ta không sợ."')
    assert not _register_violation('Hắn nhìn quanh. "Ta không sợ." Ta sai rồi chăng?')
    assert "NGÔI BA" in _register_line('他看向四周。“我不怕。”')
    assert "NGÔI NHẤT" in _register_line('我看向四周。')


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


def test_scene_analysis_survives_twopass_off():
    from novelworker.translator.worker import _needs_scene_analysis
    assert _needs_scene_analysis("“Ngươi là ai?”", False)
    assert _needs_scene_analysis("Không có hội thoại.", True)
    assert not _needs_scene_analysis("Không có hội thoại.", False)


def test_fix_omissions_with_fake_llm():
    from novelworker.translator.worker import _fix_omissions, check_translation

    class FakeRes:
        text = '[{"line": 1, "new": "Ai nói bậy, ông đây xé nát mồm!"}]'

    class FakeLLM:
        def complete(self, system, user, **kw):
            assert "老子" in user and "BẢN DỊCH" in user
            return FakeRes()

    zh = "谁在胡说八道，老子撕烂他的嘴！"
    vi = "Ai nói bậy, ta xé nát mồm!"
    assert _fix_omissions(FakeLLM(), zh, vi) == "Ai nói bậy, ông đây xé nát mồm!"

    class Boom:
        def complete(self, *a, **k):
            raise AssertionError("không được gọi khi không thiếu gì")
    assert _fix_omissions(Boom(), "他笑了。", "Hắn bật cười.") == "Hắn bật cười."
    # omission KHÔNG còn chặn ở fuse — không tạo job kẹt vĩnh viễn
    assert check_translation(zh * 30, ("Ai nói bậy, ta xé nát mồm! Hắn nhìn quanh đầy giận dữ. " * 30)) is None


def test_fix_han_residue_by_line():
    from novelworker.translator.worker import _fix_han_residue

    class FakeLLM:
        def complete(self, *a, **k):
            return type("R", (), {
                "text": '[{"line": 2, "new": "Trên áo viết chữ tù."}]'})()

    assert _fix_han_residue(FakeLLM(), "Hắn cúi đầu.\nTrên áo viết chữ 囚.") == (
        "Hắn cúi đầu.\nTrên áo viết chữ tù.")


def test_style_revise_with_fake_llm():
    from novelworker.translator.worker import _style_revise

    class FakeRes:
        text = '[{"line": 1, "new": "Ngài có cần phu nhân không?"}]'

    class FakeLLM:
        def complete(self, system, user, **kw):
            assert "DÒNG 1:" in user
            return FakeRes()

    assert _style_revise(FakeLLM(), "Ngài cần phu nhân chăng?") == "Ngài có cần phu nhân không?"

    class BadLLM:
        def complete(self, *a, **k):
            return type("R", (), {"text": '[{"line": 1, "new": "囚"}]'})()
    assert _style_revise(BadLLM(), "Ngài cần phu nhân chăng?", "他说。") == "Ngài cần phu nhân chăng?"
    # không có câu lỗi → không gọi LLM, trả nguyên văn
    class Boom:
        def complete(self, *a, **k):
            raise AssertionError("không được gọi")
    assert _style_revise(Boom(), "Hắn im lặng rời đi.") == "Hắn im lặng rời đi."
