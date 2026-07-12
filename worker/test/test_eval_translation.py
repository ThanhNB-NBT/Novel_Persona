from eval_translation import (
    _dialogue_self_minh, _self_reference_omissions, fidelity_issues, lint, narrator_terms,
)


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


def test_clean_style_drops_junk():
    """Style bible JSON rác không được sống xuyên truyện (P2-8)."""
    from novelworker.translator.worker import _clean_style
    st = _clean_style({"pov": "ngôi ba", "junk": "x" * 999, "rules": ["a", 5, "b" * 200]})
    assert st == {"pov": "ngôi ba", "rules": ["a", "b" * 120]}
    assert _clean_style("không phải dict") is None
    assert _clean_style({"junk": 1}) is None


def test_benchmark_timeout_override_does_not_change_provider_default(monkeypatch):
    import novelworker.translator.providers as providers
    seen = []

    class FakeClient:
        def __init__(self, **kwargs):
            seen.append(kwargs)

    monkeypatch.setattr(providers, "OpenAI", FakeClient)
    p = providers.TranslationProvider("https://example.test", "key", "model", timeout_sec=45)
    assert p.timeout_sec == 45 and seen[-1]["timeout"] == 45
    assert p.with_model("other").timeout_sec == 45


def test_call_stats_accumulate_across_pin(monkeypatch):
    """Counter per-chương phải cộng dồn qua pin() (pin tạo FallbackChain mới)."""
    from novelworker import db
    from novelworker.translator import providers as P
    from novelworker.translator.providers import FallbackChain, LLMResult

    monkeypatch.setattr(db, "record_model_call", lambda *a, **k: None)

    class FakeP:
        model = "m"
        def complete(self, *a, **k):
            return LLMResult(text="x", model="m", prompt_tokens=10, completion_tokens=5)
        def with_model(self, m):
            return self

    chain = FallbackChain([("nvidia", FakeP())])
    P.reset_call_stats()
    chain.complete("s", "u")
    chain.pin("nvidia", "m2").complete("s", "u")
    assert P.get_call_stats() == {"calls": 2, "prompt_tokens": 20, "completion_tokens": 10}


def test_register_violation_ta_threshold():
    """'ta' lẻ tẻ = nghĩ thầm không ngoặc (hợp lệ); dày ≥3 = trôi POV (bug n1007 v3)."""
    from novelworker.translator.worker import _register_violation
    assert _register_violation("Xem ra ta đã tái sinh. Hắn đứng dậy.") is None
    assert _register_violation("Ta đi tới. Ta nhìn quanh. Ta thở dài.") is not None
    assert _register_violation("Anh ta cười.") is not None  # cụm không thể nhầm: chặn từ 1
    assert _register_violation("Tôi đi. Tôi về. Tôi ngủ.", allow_toi=True) is None
    assert _register_violation("Hắn nhìn quanh.\n— Ta không sợ.") is None


def test_audit_reason_includes_hard_register_and_self_reference_errors():
    from novelworker.translator.worker import _audit_reason
    assert _audit_reason("他笑了。", "Anh ta bật cười.")
    assert _audit_reason("老子不服。", "Ta không phục.")
    assert _audit_reason("他笑了。", "Hắn bật cười.") is None


def test_audit_requeues_at_most_25_chapters(monkeypatch):
    import novelworker.translator.worker as worker
    bad = [({"id": i, "novel_id": 1, "chapter_index": i}, "lỗi") for i in range(40)]
    queued = []
    monkeypatch.setattr(worker, "scan_bad_chapters", lambda: bad)
    monkeypatch.setattr(worker, "requeue_bad", lambda batch: queued.extend(batch))
    worker.handle_audit({})
    assert len(queued) == 25 and queued == bad[:25]


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


def test_narrator_terms_ignore_dash_dialogue():
    assert narrator_terms('Hắn quay đi.\n— Mình không sợ!\nNàng im lặng.') == {
        "hắn": 1,
        "nàng": 1,
    }


def test_narrator_terms_ignore_reflexive_and_kinship_words():
    assert narrator_terms('Hắn thấy mình trong gương. Cậu Lưu đi tới.') == {"hắn": 1}


def test_fidelity_cases_for_confirmed_name_and_title_errors():
    assert fidelity_issues("棒梗那个小屁孩偷东西。", "Xoạ Trụ từ nhỏ đã trộm cắp.")
    assert fidelity_issues("傻柱走上前。", "Xoạ Trụ bước tới.")
    assert fidelity_issues("一大爷易中海站出来。", "Dượng Dịch Trung Hải bước ra.")
    assert not fidelity_issues("傻柱走上前。", "Ngốc Trụ bước tới.")


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
    # 1 chữ 我 lẻ (từ ghép 自我安慰) giữa 36 chữ 他 KHÔNG được lật cả chương sang ngôi nhất
    assert "NGÔI BA" in _register_line('他也只能自我安慰。' + '他走了。' * 3)


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


def test_analyze_names_shapes():
    """Pass tên trả LIST term; nhận cả shape object {terms:[...]} lẫn mảng cũ; rác → []."""
    from novelworker.translator.worker import _analyze_names

    class FakeLLM:
        def __init__(self, text):
            self._t = text
        def complete(self, *a, **k):
            return type("R", (), {"text": self._t})()

    assert _analyze_names(FakeLLM('{"terms": [{"zh": "林松", "vi": "Lâm Tùng"}]}'), "x")[0]["vi"] == "Lâm Tùng"
    assert _analyze_names(FakeLLM('[{"zh": "林松", "vi": "Lâm Tùng"}]'), "x")  # mảng cũ
    assert _analyze_names(FakeLLM("not json"), "x") == []


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
