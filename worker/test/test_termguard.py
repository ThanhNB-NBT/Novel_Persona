"""Termguard: mã placeholder không được rò ra bản dịch.

Bug 26/07: `_line_terms` ghim cả chữ số làm term để giữ nguyên số; term số được thay
TRƯỚC (approved) nên sinh mã 'ZX000Q', rồi term số kế tiếp ('00') khớp vào giữa chính mã
đó và ăn mất nó. `_restore_complete` đếm mã trên bản đã hỏng (0 == 0) nên tưởng restore
xong, mảnh 'ZX'/'0Q' đi thẳng ra người đọc — 16/4173 chương đang dính.
"""
from novelworker.translator import termguard as tg


def test_selfcheck_module():
    tg._self_check()


def test_term_so_khong_an_mat_ma():
    zh = "丧尸001只，编号00。"
    terms = tg._line_terms(zh, [{"term_zh": "丧尸", "correct_vi": "táng thi"}])
    for family, alphabet in (
        (tg._ALNUM_CODES, tg._UPPER),
        (tg._CODES, tg._L),
        (tg._BRACKET_CODES, f"⟦{tg._UPPER}⟧"),
    ):
        protected, mapping = tg._protect_with_codes(zh, terms, family)
        assert all(protected.count(code) == 1 for code in mapping), protected
        # model "ngoan": trả nguyên bản có mã → restore phải sạch, số phải còn nguyên
        out = tg._restore_complete(protected, protected, mapping, alphabet)
        assert out is not None
        assert "ZX" not in out and "⟦" not in out and "⟧" not in out, out
        assert "001" in out and "编号 00" in out, out


def test_ma_bi_an_thi_bo_ho_ma_thay_vi_de_rac_lot():
    # Term ngắn hơn được thay SAU (thứ tự dài→ngắn) nên có thể khớp vào thân mã đã chèn:
    # 'AA' nằm trong 'ZXAAAQ' của term trước. Thà bỏ cưỡng chế còn hơn để mảnh mã lọt.
    zh = "甲乙丙AA"
    terms = [{"term_zh": "甲乙丙", "correct_vi": "Giáp Ất Bính", "approved": True},
             {"term_zh": "AA", "correct_vi": "AA", "approved": True}]
    protected, mapping = tg._protect_with_codes(zh, terms, ["ZXAAAQ", "ZXAABQ"])
    assert (protected, mapping) == (zh, {}), (protected, mapping)


def test_quet_mảnh_ma_o_dau_ra():
    bad = ["Thái Thản zombie ZX01Q, hắn cười.", "câu lành"]
    plain = ["Thái Thản zombie thây ma, hắn cười.", "câu lành"]
    assert tg._drop_leaked(bad, plain) == plain


def test_khong_doi_dong_lanh():
    lines = ["Nhai Tý đến rồi.", "hắn cười."]
    assert tg._drop_leaked(lines, ["khác 1", "khác 2"]) == lines
