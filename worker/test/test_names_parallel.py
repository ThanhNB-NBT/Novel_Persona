"""Trích tên riêng chạy NỀN, chương dịch không chờ (26/07).

Đo trên VPS: một call LLM tốn 38-79s (cùng key/model từ máy nhà chỉ 2-3s — khác biệt còn
lại duy nhất là IP đi ra), trong khi Hachimi dịch xong chương trong ~24s. Và 100% hàng đợi
là chương ≤20, tức chương nào cũng gọi trích tên. Bắt chương chờ = nhân ba thời gian dịch.
"""
import threading
import time

from novelworker.translator import worker


def test_save_detected_names_bo_ten_da_co_va_ten_hong(monkeypatch):
    rows_seen = {}
    monkeypatch.setattr(worker.db, "insert_glossary_suggestions",
                        lambda rows: rows_seen.update(rows=rows) or set())
    monkeypatch.setattr(worker.db, "record_glossary_conflicts", lambda *a, **k: None)
    monkeypatch.setattr(worker, "_glossary_conflicts", lambda *a, **k: [])

    detected = [
        {"zh": "林松", "vi": "Lâm Tùng", "type": "person"},
        {"zh": "玛利亚", "vi": "Maria", "type": "person"},   # đã có sẵn → bỏ
        {"zh": "林松", "vi": "Lâm Tùng", "type": "person"},   # trùng trong cùng lô → bỏ
        "rác không phải dict",
    ]
    n = worker.save_detected_names(7, 3, detected, terms=[], preexisting_zh={"玛利亚"})
    assert n == 1
    assert [r["term_zh"] for r in rows_seen["rows"]] == ["林松"]
    assert rows_seen["rows"][0]["first_chapter"] == 3
    assert rows_seen["rows"][0]["approved"] is False


def test_loi_khi_luu_khong_lam_vo_chuong(monkeypatch):
    """Bản dịch + job đã commit; glossary phụ trợ hỏng không được ném ngược lên."""
    def boom(_rows):
        raise RuntimeError("DB sập")
    monkeypatch.setattr(worker.db, "insert_glossary_suggestions", boom)
    assert worker.save_detected_names(7, 1, [{"zh": "林松", "vi": "Lâm Tùng", "type": "person"}],
                                      terms=[], preexisting_zh=set()) == 0


def test_bg_trich_ten_roi_tu_luu(monkeypatch):
    saved = {}
    monkeypatch.setattr(worker, "_analyze_names", lambda llm, chunk: [{"zh": "林松"}])
    monkeypatch.setattr(worker, "save_detected_names",
                        lambda nid, idx, names, terms, pre: saved.update(
                            nid=nid, idx=idx, names=names) or len(names))
    worker._extract_names_bg(None, "林松来了", 7, 3, [], set())
    assert saved == {"nid": 7, "idx": 3, "names": [{"zh": "林松"}]}


def test_chuong_khong_cho_ket_qua_trich_ten():
    """Nếu quay lại kiểu chờ (join) thì submit sẽ chặn và test hết giờ."""
    llm_started = threading.Event()
    llm_done = threading.Event()

    def slow_llm():
        llm_started.set()
        time.sleep(1.0)          # giả LLM chậm như trên VPS
        llm_done.set()

    t0 = time.time()
    worker._NAME_POOL.submit(slow_llm)
    assert llm_started.wait(2), "task nền không chạy"
    dich_xong = time.time() - t0          # 'chương' kết thúc ngay, không chờ LLM

    assert dich_xong < 0.5, f"chương bị chặn {dich_xong:.2f}s — đã quay lại kiểu chờ"
    assert not llm_done.is_set(), "LLM đã xong trước khi chương kết thúc — test vô nghĩa"
    assert llm_done.wait(5), "task nền không chạy tới nơi"
