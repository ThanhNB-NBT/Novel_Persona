from eval_translation import (
    _dialogue_self_minh, _self_reference_omissions, fidelity_issues, lint, narrator_terms,
)


def test_patch_replacements_include_old_vietnamese_and_han_residue():
    from novelworker.translator.worker import _patch_replacements

    repls = _patch_replacements([
        {'wrong_vi': 'Lâm', 'correct_vi': 'Lâm Tùng'},
        {'term_zh': '林同', 'correct_vi': 'Lâm Tùng'},
    ])

    assert ('Lâm', 'Lâm Tùng') in repls
    assert ('林同', 'Lâm Tùng') in repls


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
    """Omission chỉ dùng để đánh giá prompt; production không sửa lại bản dịch hậu kỳ."""
    from novelworker.translator.worker import _quality_fuse
    res = type("R", (), {"text": "Hắn không đồng ý. " * 30, "model": "test"})()
    _quality_fuse("老夫不答应。" * 30)(res)  # không raise


def test_clean_style_drops_junk():
    """Style bible chỉ giữ mô tả ổn định; rules tự sinh không được sống xuyên truyện."""
    from novelworker.translator.worker import _clean_style
    st = _clean_style({"pov": "ngôi ba", "junk": "x" * 999, "rules": ["a", 5, "b" * 200]})
    assert st == {"pov": "ngôi ba"}
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


def test_call_stats_count_real_retry_and_rejected_tokens(monkeypatch):
    """Mỗi HTTP retry và token của output bị fuse loại đều phải hiện trong log."""
    from novelworker import db
    from novelworker.translator import providers as P
    health = []
    monkeypatch.setattr(db, "record_model_call", lambda model, ms, ok, error=None: health.append(ok))
    monkeypatch.setattr(P, "_wait_for_rate_slot", lambda _key: None)
    monkeypatch.setattr(P.TranslationProvider.complete.retry, "wait", lambda _state: 0)

    class Completions:
        calls = 0
        def create(self, **_kwargs):
            self.calls += 1
            text = "bị fuse" if self.calls == 1 else "đạt"
            return type("Resp", (), {
                "usage": type("Usage", (), {"prompt_tokens": 10, "completion_tokens": 5})(),
                "choices": [type("Choice", (), {
                    "finish_reason": "stop",
                    "message": type("Message", (), {"content": text})(),
                })()],
            })()

    provider = object.__new__(P.TranslationProvider)
    provider.model, provider.provider, provider.api_key = "m", "nvidia", "key"
    provider.client = type("Client", (), {
        "chat": type("Chat", (), {"completions": Completions()})()
    })()

    def validate(result):
        if result.text == "bị fuse":
            raise RuntimeError("output kém")

    P.reset_call_stats()
    assert provider.complete("s", "u", validate=validate).text == "đạt"
    assert P.get_call_stats() == {
        "calls": 2, "failures": 1, "prompt_tokens": 20, "completion_tokens": 10,
    }
    assert health == [False, True]


def test_audit_reason_only_blocks_structural_errors():
    from novelworker.translator.worker import _audit_reason
    assert _audit_reason("他笑了。", "Anh ta bật cười.") is None
    assert _audit_reason("老子不服。", "Ta không phục.") is None
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


def test_apply_line_fixes_accepts_single_object_and_line_map():
    from novelworker.translator.worker import _apply_line_fixes
    vi = "Hắn cúi đầu.\nTrên áo còn chữ Trung."
    fixed, n = _apply_line_fixes(vi, {"line": 2, "new": "Trên áo viết chữ tù."})
    assert n == 1 and fixed.endswith("chữ tù.")
    fixed, n = _apply_line_fixes(vi, {"2": "Trên áo viết chữ tù."})
    assert n == 1 and fixed.endswith("chữ tù.")


def test_apply_line_fixes_accepts_old_new_format():
    """SYSTEM_REVISE cũ dạy old/new — model trả kiểu đó vẫn phải áp được (v5: 0 câu thay)."""
    from novelworker.translator.worker import _apply_line_fixes
    vi = "Hắn cười lớn.\nHắn không khỏi thở dài."
    fixed, applied = _apply_line_fixes(
        vi, [{"old": "Hắn không khỏi thở dài.", "new": "Hắn bất giác thở dài."}])
    assert applied == 1 and fixed.endswith("Hắn bất giác thở dài.")


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
    """Văn phiên âm máy móc được ngăn từ prompt, không hard-fail hậu kỳ bằng heuristic."""
    from novelworker.translator import prompts
    system = prompts.build_main_chapter_system([], "原文")
    assert "Không ghép nửa dịch nghĩa nửa phiên âm" in system
    assert "Tránh văn convert" in system


def test_english_onomatopoeia():
    assert any("tượng thanh" in p for p in lint("咳咳。", '"Cough cough, thôi đi."'))


def test_han_residue_single_char():
    assert any("Hán sót lẻ" in p for p in lint("门外传来。", "Bên ngoài cửa truyền来 tiếng ồn."))


def test_quality_fuse_blocks_any_han_residue():
    from novelworker.translator.worker import check_translation
    problem = check_translation("衣服写着囚字。", 'Áo viết chữ "囚".')
    assert "1 ký tự Hán" in problem and "mẫu '囚'" in problem


def test_quality_fuse_allows_sparse_han_for_postprocess_but_blocks_raw_chinese():
    from novelworker.translator.worker import _quality_fuse

    sparse = "Đoạn dịch tiếng Việt " * 80 + "垂天地玄黄宇宙洪荒"
    res = type("R", (), {"text": sparse, "model": "test"})()
    _quality_fuse("原文" * 400)(res)  # 9 chữ khác nhau nhưng đủ thưa để TSV sửa.

    raw = type("R", (), {"text": "天地玄黄宇宙洪荒日月盈昃辰宿列张" * 20,
                          "model": "test"})()
    try:
        _quality_fuse("原文" * 100)(raw)
        raise AssertionError("Raw Chinese phải bị quality fuse chặn")
    except RuntimeError as error:
        assert "ký tự Hán" in str(error)


def test_register_line_uses_source_pov():
    from novelworker.translator.worker import _register_line
    assert "NGÔI BA" in _register_line('他看向四周。“我不怕。”')
    assert "NGÔI NHẤT" in _register_line('我看向四周。')
    # 1 chữ 我 lẻ (từ ghép 自我安慰) giữa 36 chữ 他 KHÔNG được lật cả chương sang ngôi nhất
    assert "NGÔI BA" in _register_line('他也只能自我安慰。' + '他走了。' * 3)


def test_style_line_and_narrator_term():
    from novelworker.translator import prompts
    line = prompts.build_style_line({
        "pov": "ngôi ba", "setting": "tu tiên cổ đại", "han_viet": "đậm",
        "tone": "gọn, lạnh", "rules": ["hệ thống nói giọng tưng tửng"]})
    assert "ngôi ba" in line and "tu tiên cổ đại" in line and "tưng tửng" not in line
    assert prompts.build_style_line(None) is None
    assert prompts.build_style_line({}) is None
    system = prompts.build_main_chapter_system(
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


def test_fix_han_residue_by_line():
    from novelworker.translator.worker import (
        _fix_han_residue, _hanviet_fallback, _replace_glossary_han,
        _valid_suggested_zh,
    )

    class FakeLLM:
        def complete(self, *a, **k):
            return type("R", (), {
                "text": '[{"line": 2, "new": "Trên áo viết chữ tù."}]'})()

    assert _fix_han_residue(FakeLLM(), "Hắn cúi đầu.\nTrên áo viết chữ 囚.") == (
        "Hắn cúi đầu.\nTrên áo viết chữ Tù.")

    class NoFixLLM:
        def complete(self, *a, **k):
            return type("R", (), {"text": '{"line": 2, "new": "Trên áo vẫn viết chữ 囚."}'})()

    # Glossary chính xác hơn phiên âm từng chữ và phải chạy trước LLM.
    assert _fix_han_residue(NoFixLLM(), "Dòng 鲜血 tràn ra.", [
        {"term_zh": "鲜血", "correct_vi": "máu tươi"}
    ]) == "Dòng máu tươi tràn ra."
    # LLM không sửa được → bảng Hán-Việt là fallback cuối, không làm fail cả chương.
    fixed, n = _hanviet_fallback("Trên áo còn chữ 囚.")
    assert fixed == "Trên áo còn chữ Tù." and n == 1
    fixed, n = _hanviet_fallback("Cành liễu rủ 垂 xuống.")
    assert fixed == "Cành liễu rủ Thuỳ xuống." and n == 1
    fixed, _ = _hanviet_fallback("Vết thương phun 鲜血 tung tóe.")
    assert fixed == "Vết thương phun máu tươi tung tóe."
    fixed, _ = _hanviet_fallback("Nhận được vật phẩm 鲜血 trong kho đồ.")
    assert fixed == "Nhận được vật phẩm Tiên Huyết trong kho đồ."
    # Ngữ cảnh hành động phải thắng từ khóa vật phẩm; không nhìn lố sang câu bên cạnh.
    fixed, _ = _hanviet_fallback("Hắn đánh rơi vật phẩm. Vết thương phun 鲜血 tung tóe.")
    assert fixed.endswith("Vết thương phun máu tươi tung tóe.")
    fixed, _ = _hanviet_fallback("Bình linh dược vỡ, tay hắn chảy 鲜血.")
    assert fixed == "Bình linh dược vỡ, tay hắn chảy máu tươi."
    # Tên được đóng ngoặc hoặc có hậu tố loại vật phẩm thì giữ âm Hán-Việt.
    fixed, _ = _hanviet_fallback("Nhận được 【鲜血】.")
    assert fixed == "Nhận được 【Tiên Huyết】."
    fixed, _ = _hanviet_fallback("Hắn luyện thành 鲜血丹.")
    assert fixed == "Hắn luyện thành Tiên Huyết Đan."
    # Glossary rác từ model không được làm hỏng lượt sửa.
    assert _fix_han_residue(NoFixLLM(), "Trên áo còn chữ 囚.", ["bad"]) == (
        "Trên áo còn chữ Tù.")

    # Regression thực tế: glossary rác `h -> H` từng viết hoa hàng trăm chữ h
    # trong bản tiếng Việt. Postprocess chỉ được thay term có ít nhất một chữ Hán.
    original = "hắn hạ kiếm, hơi thở hỗn loạn."
    fixed, replaced = _replace_glossary_han(original, [
        {"term_zh": "h", "correct_vi": "H"},
        {"term_zh": "t3", "correct_vi": "T3"},
    ])
    assert fixed == original and replaced == 0
    assert not _valid_suggested_zh("h")
    assert _valid_suggested_zh("t3")
    assert _valid_suggested_zh("t2重型装甲")


def test_context_echo_is_removed_only_from_leading_lines():
    from novelworker.translator.worker import _drop_context_echo
    previous = "Lâm Tùng khép cửa lại.\nĐêm nay hắn không ngủ."
    assert _drop_context_echo(previous + "\nSáng hôm sau, hắn lên đường.", previous) == (
        "Sáng hôm sau, hắn lên đường.")
    assert _drop_context_echo("Sáng hôm sau, hắn lên đường.", previous) == "Sáng hôm sau, hắn lên đường."
