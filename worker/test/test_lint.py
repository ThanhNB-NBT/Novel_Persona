from novelworker.translator.lint import lint_score
from novelworker.translator.worker import _gated_tail


def test_lint_score_clean_dirty_and_no_source():
    assert lint_score("他笑了。", "Hắn bật cười.") == 0
    assert lint_score("他笑了。", "Hắn không khỏi bật cười, còn chữ 来.") > 0
    assert lint_score(None, "Bản dịch bình thường.") == 0


def test_narrator_mix_han_vs_y():
    from novelworker.translator.lint import lint_warnings
    mixed = ("Hắn bước tới. Hắn rút kiếm. Hắn cười.\n"
             "Y nhìn quanh. Y thu dao. Y bỏ đi.")
    assert any("trộn 'hắn'" in w for w in lint_warnings(None, mixed))
    # chỉ 'hắn' hoặc 'y' thưa → không bắt oan; 'y' trong thoại không tính
    assert not any("trộn" in w for w in lint_warnings(None, "Hắn đi. Hắn cười. Hắn ngủ. Y đứng."))
    assert not any("trộn" in w for w in lint_warnings(
        None, 'Hắn đi. Hắn cười. Hắn ngủ. “Y là ai? Y đâu? Y chạy rồi.”'))


def test_gated_tail_keeps_summary_and_only_drops_dirty_tail():
    dirty = {"summary_vi": "Tóm tắt", "content_vi": "Đuôi bẩn", "lint_score": 5}
    assert dirty["summary_vi"] == "Tóm tắt" and _gated_tail(dirty) is None
    assert _gated_tail({"content_vi": "Đuôi sạch", "lint_score": 0}) == "Đuôi sạch"
    # biên ngưỡng: 2 giữ, 3 bỏ
    assert _gated_tail({"content_vi": "Đuôi biên", "lint_score": 2}) == "Đuôi biên"
    assert _gated_tail({"content_vi": "Đuôi biên", "lint_score": 3}) is None
    # score NULL (chương cũ chưa đo) → lint tại chỗ: sạch giữ tail, bẩn bỏ tail
    assert _gated_tail({"content_vi": "Đuôi cũ", "lint_score": None}) == "Đuôi cũ"
    dirty_old = "Hắn không khỏi cười. Trên thực tế còn sót chữ 来 và **markdown** lọt vào."
    assert _gated_tail({"content_vi": dirty_old, "lint_score": None}) is None
    assert _gated_tail({"content_vi": None, "lint_score": None}) is None
