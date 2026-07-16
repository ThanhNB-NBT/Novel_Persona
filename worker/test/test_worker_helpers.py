import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.translator.worker import (
    GLOSSARY_LINE, _clean_output, _extract_json, _glossary_conflicts, _merge_names, _pop_summary, _term_dicts,
    _is_unique_violation, _split_chunks, _strip_meta,
    CHUNK_LIMIT, _build_synopsis_input, _should_keep_old_summary,
    _valid_summary, _valid_synopsis, check_translation, han_ratio,
)


def main() -> None:
    class UniqueError(Exception):
        code = "23505"

    assert _is_unique_violation(UniqueError())
    assert _is_unique_violation(RuntimeError("duplicate key value violates unique constraint"))
    assert not _is_unique_violation(RuntimeError("network timeout"))
    from novelworker.translator.worker import _needs_style_refresh
    assert _needs_style_refresh({"src_chapter": 2})
    assert not _needs_style_refresh({"src_chapter": 1})
    assert not _needs_style_refresh({"tone": "co phong"})

    from novelworker.translator import worker as worker_mod
    refreshed = []
    original_refresh = worker_mod.db.refresh_job_lock

    class StopAfterOne:
        calls = 0

        def wait(self, interval):
            self.calls += 1
            return self.calls > 1

    try:
        worker_mod.db.refresh_job_lock = lambda job_id, worker_id: refreshed.append(
            (job_id, worker_id)
        )
        worker_mod._keep_job_lock(7, "worker:test", StopAfterOne(), 30)
    finally:
        worker_mod.db.refresh_job_lock = original_refresh
    assert refreshed == [(7, "worker:test")]

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
    assert "Cyrillic" in (check_translation("原文本", "Bản dịch có либо bị sót") or "")
    assert check_translation("", "Chỉ soi tỷ lệ Hán khi thiếu bản gốc.") is None
    from novelworker.translator.worker import _is_first_person
    assert _is_first_person("我走了过去。“你好。”")            # 我 trong lời kể
    assert not _is_first_person("他走了。“我不去！”他说。")     # 我 chỉ trong thoại
    # Chỉ chặn bản cụt rõ ràng (<60% gốc), không bắt oan văn dịch cô đọng.
    assert "quá ngắn" in (check_translation("字" * 400, "v" * 200) or "")
    assert check_translation("字" * 400, "v" * 250) is None
    # Gốc ≥10 đoạn: chỉ chặn khi mất >70% số đoạn.
    zh12 = "\n".join("第几行内容在这里" * 8 for _ in range(12))
    vi3_du_dai = "\n".join("dòng dịch đủ dài để qua kiểm tra độ dài tổng thể nhé " * 8 for _ in range(3))
    assert "mất đoạn" in (check_translation(zh12, vi3_du_dai) or "")
    vi4 = "\n".join("dòng dịch đủ dài để qua kiểm tra độ dài tổng thể nhé " * 12 for _ in range(4))
    assert check_translation(zh12, vi4) is None

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
    assert _valid_summary("Lâm Tùng an toàn.") == "Lâm Tùng an toàn."
    assert _valid_summary("Lâm 松") is None
    too_long = ("Một câu đủ dài. " * 30) + "đoạn dang dở"
    clipped = _valid_summary(too_long)
    assert clipped and len(clipped) <= 400 and clipped.endswith(".")
    assert _valid_synopsis("Lâm Tùng tiến vào bí cảnh.") == "Lâm Tùng tiến vào bí cảnh."
    assert _valid_synopsis("Lâm 松") is None
    assert len(_valid_synopsis("a" * 700) or "") == 600
    # nhãn/markdown model dán thêm bị bóc máy
    assert _valid_synopsis("SYNOPSIS: **Lâm Tùng** vào bí cảnh.") == "Lâm Tùng vào bí cảnh."
    assert "Bối cảnh cũ:\nCũ" in _build_synopsis_input("Cũ", ["c2", "c1"])
    assert "Tên nhân vật chuẩn (giữ nguyên): Lâm Tùng" in _build_synopsis_input(None, ["c1"], ["Lâm Tùng"])
    # chỉ nén khi đủ 10 summary liền nhau kết thúc tại chương hiện tại
    from novelworker.translator.worker import _synopsis_ready
    full = [{"chapter_index": i} for i in range(11, 21)]
    assert _synopsis_ready(full, 20)
    assert not _synopsis_ready(full[1:], 20)                       # thiếu c11
    assert not _synopsis_ready(full[:9] + [{"chapter_index": 9}], 20)  # thủng giữa, vá bằng chương cũ
    assert _should_keep_old_summary(True, "summary cũ")
    assert not _should_keep_old_summary(False, "summary cũ")
    assert not _should_keep_old_summary(True, None)

    # vá văn phong máy: thay an toàn + toàn bộ ngoại lệ giữ nguyên nghĩa
    from novelworker.translator.worker import _fix_register, _fix_soft_style
    assert _fix_soft_style("Chẳng ai tin. Hắn chẳng nói gì.") == "Không ai tin. Hắn không nói gì."
    keep = ("Chẳng lẽ vậy? Chẳng qua là đùa. Chẳng hạn như y. Chẳng những thế. "
            "Chẳng mấy chốc trời sáng. Chẳng trách hắn giận. Chẳng thà chết. "
            "Cực chẳng đã mới làm. Ai mà chẳng thích.")
    assert _fix_soft_style(keep) == keep
    assert _fix_soft_style("Hắn không khỏi bật cười.") == "Hắn bật cười."
    for s in ("Bệnh chữa không khỏi đâu.", "Vết thương vẫn không khỏi.",
              "Trị mãi không khỏi được."):
        assert _fix_soft_style(s) == s
    assert _fix_soft_style("Tổng cảm thấy sai sai.") == "Cứ cảm thấy sai sai."
    assert _fix_soft_style("Trên thực tế, hắn sợ.") == "Thật ra, hắn sợ."
    assert _fix_soft_style("Hắn gật đầu một cái rồi cười một cái.") == "Hắn gật đầu rồi bật cười."
    # vá đại từ kể: chỉ ngoài thoại; trong ngoặc kép giữ nguyên
    assert _fix_register('Cô ấy đi rồi. “Anh ta là ai?” Ông ta hỏi.') == \
        'Nàng đi rồi. “Anh ta là ai?” Lão hỏi.'
    assert _fix_register("Anh hùng cứu tinh anh dũng.") == "Anh hùng cứu tinh anh dũng."

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
    default_chunks = _split_chunks(long_ch)
    assert CHUNK_LIMIT == 5000  # trần theo output 8192 tok; 3000/12-đoạn là di sản marker đã gỡ
    assert all(len(c) <= CHUNK_LIMIT for c in default_chunks)

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
    # chữ phổ thông/danh từ chung bị chặn; 朕 là person vẫn là tên hợp lệ.
    assert _merge_names(terms, existing, [{"zh": "的", "vi": "của"}, {"zh": "鲜血", "vi": "máu tươi"}]) == []
    assert _merge_names(terms, existing, [{"zh": "朕", "vi": "Trẫm", "type": "person"}])
    assert _merge_names(terms, existing, [
        {"zh": "火焰剑", "vi": "Kiếm Lửa", "type": "item"},
        {"zh": "清虚山", "vi": "Núi Thanh Hư", "type": "place"},
        {"zh": "火球术", "vi": "Hỏa Cầu Thuật", "type": "skill"},
    ])
    suspect = {"zh": "白衣少女", "vi": "cô gái áo trắng", "type": "person"}
    _merge_names(terms, existing, [suspect])
    assert terms[-1]["note"] == "nghi sai" and terms[-1]["approved"] is False
    # term ghép lệch term gốc (丧尸→zombie đã chốt mà đề xuất "Táng Thi") → nghi sai
    terms_zomb = [{"term_zh": "丧尸", "correct_vi": "zombie"}]
    existing_zomb = {"丧尸"}
    _merge_names(terms_zomb, existing_zomb, [
        {"zh": "滑翔丧尸", "vi": "Hoạt Tường Táng Thi", "type": "other"},
        {"zh": "地行丧尸", "vi": "zombie địa hành", "type": "other"},
    ])
    by_zh = {t["term_zh"]: t for t in terms_zomb}
    assert by_zh["滑翔丧尸"]["note"] == "nghi sai"      # lệch gốc → chặn inject
    assert by_zh["地行丧尸"].get("note") != "nghi sai"  # kế thừa "zombie" → hợp lệ
    from novelworker.translator.prompts import _build_glossary_block
    assert "白衣少女" not in _build_glossary_block(terms, "白衣少女来了")
    terms[-1]["approved"] = True
    assert "白衣少女" in _build_glossary_block(terms, "白衣少女来了")
    # tiêu đề "第x章..." phải được bóc số chương trước khi vào prompt
    from novelworker.translator.worker import TITLE_CHAPTER_PREFIX
    assert TITLE_CHAPTER_PREFIX.sub("", "第158章“引灭雷光”！").strip() == "“引灭雷光”！"
    assert TITLE_CHAPTER_PREFIX.sub("", "第一百二十章 决战").strip() == "决战"
    assert TITLE_CHAPTER_PREFIX.sub("", "决战").strip() == "决战"
    # 鲜血/máu tươi từng được cho merge; nay là danh từ chung cần chặn.
    assert _term_dicts(["rác", {"zh": "鲜血", "vi": "máu tươi"}, None]) == [
        {"zh": "鲜血", "vi": "máu tươi"}
    ]

    # Gợi ý mâu thuẫn chỉ được lộ ra để duyệt, không sửa term đang dùng.
    current = {"id": 9, "novel_id": 7, "term_zh": "林松", "correct_vi": "Lâm Tùng",
               "term_type": "other", "approved": True, "conflict_vi": None}
    conflicts = _glossary_conflicts([current], [{"zh": "林松", "vi": "Lâm Tồng", "type": "other"}], 105)
    assert conflicts == [{"term_zh": "林松", "candidate_vi": "Lâm Tồng", "conflict_vi": "Lâm Tồng (c105)"}]
    assert current["correct_vi"] == "Lâm Tùng" and current["approved"] is True
    assert _glossary_conflicts([current], [{"zh": "林松", "vi": "Lâm Tùng", "type": "other"}], 105) == []
    current["conflict_vi"] = "Lâm Tồng (c105)"
    assert _glossary_conflicts([current], [{"zh": "林松", "vi": "Khác", "type": "other"}], 106) == []
    current["conflict_vi"] = None
    assert _glossary_conflicts([current], [{"zh": "林松", "vi": "Lâm Tồng", "type": "person"}], 105) == []

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
    assert [_key(i) for i in range(8)] == ["keyA", "keyB"] * 4

    # Limiter dùng chung theo key: cùng key cách đều 60/RPM, key khác không phải đợi.
    providers._next_request_at.clear()
    clock = [100.0]
    sleeps = []
    old_monotonic, old_sleep = providers.time.monotonic, providers.time.sleep
    try:
        providers.time.monotonic = lambda: clock[0]
        providers.time.sleep = lambda seconds: sleeps.append(seconds)
        providers._wait_for_rate_slot("keyA")
        providers._wait_for_rate_slot("keyA")
        providers._wait_for_rate_slot("keyB")
    finally:
        providers.time.monotonic, providers.time.sleep = old_monotonic, old_sleep
        providers._next_request_at.clear()
    assert len(sleeps) == 1
    assert abs(sleeps[0] - 60 / providers.settings.nvidia_rpm_limit) < 0.001

    # dừng mượt: cờ _shutdown đã set → _consume_loop thoát NGAY, không claim job nào
    import threading
    import novelworker.translator.worker as W
    old_bc, old_claim = W.build_chain, W.db.claim_next_job
    claimed = []
    W.build_chain = lambda slot: object()
    W.db.claim_next_job = lambda wid: claimed.append(wid)  # KHÔNG được gọi
    try:
        W._shutdown.set()
        W._consume_loop("t:0", 0, threading.Event(), 0.01)  # phải return ngay
    finally:
        W._shutdown.clear()
        W.build_chain, W.db.claim_next_job = old_bc, old_claim
    assert claimed == [], "shutdown set mà vẫn claim job"


if __name__ == "__main__":
    main()
    print("OK — tất cả test pass")
