import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.translator.worker import (
    GLOSSARY_LINE, _clean_output, _extract_json, _merge_names, _pop_summary,
    _fix_register, _register_violation, _split_chunks, _strip_meta, check_translation, han_ratio,
)


def main() -> None:
    data = _extract_json('metadata:\n```json\n{"title_vi":"Tên truyện"}\n```')
    assert data["title_vi"] == "Tên truyện"

    # _extract_json: JSON trơn, JSON lẫn chữ thừa 2 đầu, ngoặc/quote lồng trong string
    assert _extract_json('{"a": 1}') == {"a": 1}
    assert _extract_json('Đây là kết quả: [{"a": 1}] xong.') == [{"a": 1}]
    assert _extract_json('rác {"s": "có } và \\" bên trong", "n": 2} rác') == \
        {"s": 'có } và " bên trong', "n": 2}
    try:
        _extract_json("không có json nào")
        raise AssertionError("phải raise khi không có JSON")
    except Exception:
        pass

    # check_translation: phủ từng nhánh hỏng + ca đạt
    zh5 = "第一行\n第二行\n第三行\n第四行\n第五行\n第六行"
    assert check_translation("原文", "") == "nội dung dịch rỗng"
    assert "ký tự Hán" in (check_translation("原文", "还是中文没有翻译") or "")
    assert "quá ngắn" in (check_translation("原" * 100, "cụt") or "")
    assert "mất hết xuống dòng" in (check_translation(zh5, "một khối chữ liền dài " * 3) or "")
    assert check_translation("原文本", "Bản dịch ổn.\nĐủ dòng.") is None
    assert check_translation("", "Chỉ soi tỷ lệ Hán khi thiếu bản gốc.") is None
    # lời kể: chỉ bắt cụm không thể nhầm (anh ta/cô ấy/tôi...)
    assert _register_violation("Anh ta quay người.")
    assert _register_violation("Tôi bước tới.")
    assert _register_violation("Tôi bước tới.", allow_toi=True) is None  # truyện ngôi nhất
    from novelworker.translator.worker import _is_first_person
    assert _is_first_person("我走了过去。“你好。”")            # 我 trong lời kể
    assert not _is_first_person("他走了。“我不去！”他说。")     # 我 chỉ trong thoại
    assert _register_violation("Cô ta bước đi.")   # nữ trong lời kể phải 'nàng'
    assert _register_violation("Hắn quay người.") is None
    assert _register_violation("Cô gái bước đi.") is None   # danh từ, hợp lệ
    # từ ghép chứa 'anh/cô/tôi' KHÔNG được dính oan (từng chặn nhầm cả chương)
    for ok in ("Anh hùng xuất thiếu niên.", "Hắn đạt tới Nguyên Anh kỳ.",
               "Đám tinh anh của tông môn.", "Anh trai quay người.",
               "Cô nương kia cười.", "Hắn tôi luyện thân thể."):
        assert _register_violation(ok) is None, ok
    # thoại trong ngoặc kép: anh/em/tôi được phép, cả ngoặc thẳng lẫn ngoặc cong
    assert _register_violation('"Anh chờ em với!" Nàng gọi.') is None
    assert _register_violation("“Tôi không tin anh.” Hắn lắc đầu.") is None
    assert _register_violation("“Cô ấy đâu rồi?” Hắn hỏi.") is None
    assert _register_violation('"Lâm ca, anh xem này." Hắn đưa kiếm cho anh ta.')  # ngoài ngoặc vẫn bắt
    # vá máy móc đại từ kể sai: ngoài ngoặc thay, trong thoại giữ nguyên
    assert _fix_register("Cô ta bước đi. Anh ta cười.") == "Nàng bước đi. Hắn cười."
    assert _fix_register("Ông ta gật đầu.") == "Lão gật đầu."
    # 'Cô/Anh' trần đầu câu kể → vá; danh từ/từ ghép/giữa câu giữ nguyên
    assert _fix_register("Cô không tin. Cô gái cười.") == "Nàng không tin. Cô gái cười."
    assert _fix_register("Anh bước tới. Anh hùng cứu mỹ nhân.") == "Hắn bước tới. Anh hùng cứu mỹ nhân."
    assert _fix_register("Cô Lâm dạy học.") == "Cô Lâm dạy học."  # 'Cô' + tên riêng giữ nguyên
    assert _fix_register('"Cô ấy đâu?" Cô ấy đã đi rồi.') == '"Cô ấy đâu?" Nàng đã đi rồi.'
    assert _fix_register("Anh trai hắn tới.") == "Anh trai hắn tới."  # 'anh trai' không bị vá
    assert _register_violation(_fix_register("Cô ta nhìn anh ta.")) is None
    # gốc dài mà bản dịch < 1.2x → dịch sót (ngưỡng 0.3 cũ chỉ bắt cụt thảm họa)
    assert "quá ngắn" in (check_translation("字" * 400, "v" * 450) or "")
    assert check_translation("字" * 400, "v" * 500) is None
    # gốc ≥10 đoạn mà bản dịch mất >40% số đoạn → model nuốt đoạn
    zh12 = "\n".join("第几行内容在这里" * 8 for _ in range(12))
    vi5_du_dai = "\n".join("dòng dịch đủ dài để qua kiểm tra độ dài tổng thể nhé " * 8 for _ in range(5))
    assert "mất đoạn" in (check_translation(zh12, vi5_du_dai) or "")
    vi12 = "\n".join("dòng dịch đủ dài để qua kiểm tra độ dài tổng thể nhé " * 4 for _ in range(12))
    assert check_translation(zh12, vi12) is None

    # _pop_title: khuôn «TIÊU ĐỀ: ...», nhãn biến thể, fallback dòng đầu ngắn, dòng đầu dài → không bóc
    from novelworker.translator.worker import _pop_title
    assert _pop_title("TIÊU ĐỀ: Gió nổi\nThân chương.") == ("Gió nổi", "Thân chương.")
    assert _pop_title("## Tiêu đề chương: Gió nổi\nThân.") == ("Gió nổi", "Thân.")
    assert _pop_title("Gió nổi\nThân chương.") == ("Gió nổi", "Thân chương.")  # quên nhãn
    # model bọc «»/quote quanh nhãn, hoặc tự chế "Chương N:" — phải dọn sạch (gặp thật 2026-07)
    assert _pop_title("«TIÊU ĐỀ: Thế giới game bỗng hiện»\nThân.") == ("Thế giới game bỗng hiện", "Thân.")
    assert _pop_title("Chương 2: Giết goblin\nThân.") == ("Giết goblin", "Thân.")
    long_first = "câu mở đầu rất dài " * 10
    assert _pop_title(f"{long_first}\nThân.") == (None, f"{long_first}\nThân.")
    assert _pop_title("chỉ một dòng") == (None, "chỉ một dòng")

    body, s = _pop_summary("Bản dịch dài.\nĐoạn hai.\nSUMMARY: Lâm Tùng gặp sư phụ.")
    assert body == "Bản dịch dài.\nĐoạn hai." and s == "Lâm Tùng gặp sư phụ."

    body, s = _pop_summary("Không có tóm tắt.")
    assert body == "Không có tóm tắt." and s is None

    # "SUMMARY:" nằm sâu giữa nội dung (cách cuối >1500 ký tự) thì không được ăn nhầm
    long_text = "x\nSUMMARY: giả\n" + "a" * 2000
    assert _pop_summary(long_text) == (long_text, None)

    assert han_ratio("Bản dịch thuần Việt.") == 0
    assert han_ratio("哈哈" * 50) == 1.0
    assert 0 < han_ratio("Lẫn một chữ 松 thôi trong câu khá dài này đây.") < 0.05

    # chunk chương dài: ngắn giữ nguyên, dài cắt theo đoạn, ghép lại không mất chữ
    assert _split_chunks("ngắn") == ["ngắn"]
    paras = [f"đoạn {i} " + "字" * 300 for i in range(20)]
    long_ch = "\n".join(paras)
    chunks = _split_chunks(long_ch, limit=1000)
    assert all(len(c) <= 1000 for c in chunks)
    assert "\n".join(chunks) == long_ch

    # merge tên: chỉ thêm tên mới có đủ zh+vi, bỏ trùng/thiếu; đếm đúng số tên mới
    terms = [{"term_zh": "林松", "correct_vi": "Lâm Tùng"}]
    existing = {t["term_zh"] for t in terms}
    added = _merge_names(terms, existing, [
        {"zh": "苏雨", "vi": "Tô Vũ", "type": "person", "note": "nữ"},  # mới
        {"zh": "林松", "vi": "Lâm Tùng"},                               # trùng → bỏ
        {"zh": "无名", "vi": ""},                                        # thiếu vi → bỏ
        {"vi": "Thiếu zh"},                                             # thiếu zh → bỏ
        "không phải dict",                                              # rác → bỏ
    ])
    assert [nm["zh"] for nm in added] == ["苏雨"] and len(terms) == 2
    assert terms[-1]["term_zh"] == "苏雨" and terms[-1]["note"] == "nữ"
    # gọi lại với chính tên đó → không thêm nữa
    assert _merge_names(terms, existing, [{"zh": "苏雨", "vi": "Tô Vũ"}]) == []

    # _tail: cắt đuôi tại ranh giới đoạn, ngắn thì giữ nguyên, rỗng → None
    from novelworker.translator.worker import _tail
    assert _tail(None) is None and _tail("  ") is None
    assert _tail("ngắn thôi") == "ngắn thôi"
    long = ("đoạn một " * 30) + "\n" + ("đoạn cuối " * 20)
    tail = _tail(long, limit=100)
    assert tail is not None and len(tail) <= 100 and not tail.startswith("đoạn một")

    # GLOSSARY_LINE phải ăn cả khi model bọc mảng trong ```json fence (lỗi phình 5-6x cũ)
    plain = 'Thân chương.\nGLOSSARY_JSON: [{"zh": "林松", "vi": "Lâm Tùng"}]'
    fenced = 'Thân chương.\nGLOSSARY_JSON:\n```json\n[{"zh": "林松",\n "vi": "Lâm Tùng"}]\n```'
    for txt in (plain, fenced):
        m = GLOSSARY_LINE.search(txt)
        assert m and '"林松"' in m.group(1), txt

    # _clean_output: cắt JSON sót khi regex trượt, bỏ fence + markdown đậm, gộp cụm nói lắp
    assert _clean_output("Thân bài.\nGLOSSARY_JSON kiểu lạ [...]") == "Thân bài."
    assert _clean_output("```\nCó **tên đậm** ở đây.\n```") == "Có tên đậm ở đây."
    assert _clean_output("Hắn đứng cuối câu cuối câu này.") == "Hắn đứng cuối câu này."
    assert _clean_output("Trời xanh xanh, nước từ từ chảy.") == "Trời xanh xanh, nước từ từ chảy."  # từ láy giữ nguyên

    # _strip_meta: fuse đo trên THÂN bản dịch (bỏ SUMMARY + GLOSSARY khỏi phép đo)
    assert _strip_meta(fenced + "\nSUMMARY: tóm tắt.") == "Thân chương."

    # check_translation bắt phình bất thường (chỉ khi gốc đủ dài >400)
    zh = "字" * 500
    assert check_translation(zh, "v" * 1500) is None            # ~3x: bình thường
    assert "phình" in (check_translation(zh, ("về " * 1200)) or "")  # ~4.8x: hỏng

    # nvidia đa key: mỗi slot ghim 1 key, wrap vòng khi slot > số key
    os.environ["LLM_PROVIDER"] = "nvidia"
    os.environ["NVIDIA_API_KEYS"] = "keyA,keyB"
    from novelworker.config import Settings
    from novelworker.translator import providers
    providers.settings = Settings()  # nạp lại env vừa set
    def _key(slot):  # build_chain luôn bọc FallbackChain
        return providers.build_chain(slot).providers[0][1].client.api_key
    assert _key(0) == "keyA"
    assert _key(1) == "keyB"
    assert _key(2) == "keyA"


if __name__ == "__main__":
    main()
    print("OK — tất cả test pass")
