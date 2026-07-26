"""Trích tên riêng chạy song song với dịch Hachimi (26/07).

LLM chỉ chờ mạng, không ăn CPU — để nó chặn luồng CT2 là phí. Đo trên VPS trước khi sửa:
chương dính 2 call timeout mất 324s trong khi phần dịch thật chỉ ~25s.
"""
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from novelworker.translator import providers, worker


def test_gop_so_lieu_tu_luong_khac():
    """stats là thread-local: không gộp thì dòng log 'LLM n call' và token/chương báo 0."""
    providers.reset_call_stats()
    providers.add_call_stats({"calls": 2, "failures": 1, "prompt_tokens": 30,
                              "completion_tokens": 7})
    providers.add_call_stats({"calls": 1, "prompt_tokens": 5})
    st = providers.get_call_stats()
    assert (st["calls"], st["failures"]) == (3, 1)
    assert (st["prompt_tokens"], st["completion_tokens"]) == (35, 7)


def test_extract_bg_dem_rieng_trong_luong_cua_no(monkeypatch):
    monkeypatch.setattr(worker, "_analyze_names",
                        lambda llm, chunk: (providers.add_call_stats({"calls": 1}), [{"zh": "林松"}])[1])
    providers.reset_call_stats()
    providers.add_call_stats({"calls": 99})  # sổ của luồng chính, không được dính vào kết quả
    with ThreadPoolExecutor(max_workers=1) as pool:
        names, st = pool.submit(worker._extract_names_bg, None, "林松来了").result()
    assert names == [{"zh": "林松"}]
    assert st["calls"] == 1, st
    assert providers.get_call_stats()["calls"] == 99  # luồng chính không bị reset theo


def test_llm_va_dich_chay_chong_nhau():
    """Không đo thời gian (dễ nhấp nháy): LLM chặn tới khi dịch báo đã bắt đầu.

    Nếu quay lại tuần tự thì `translating` không bao giờ được set trong lúc LLM còn chờ
    → wait() hết giờ và test đỏ."""
    translating = threading.Event()
    llm_done = threading.Event()

    def fake_llm(_llm, _chunk):
        assert translating.wait(5), "dịch chưa chạy khi LLM còn chờ → vẫn tuần tự"
        llm_done.set()
        return [{"zh": "林松"}], {"calls": 1}

    def fake_translate(_text):
        translating.set()
        time.sleep(0.05)
        return "đã dịch"

    with ThreadPoolExecutor(max_workers=1) as pool:
        job = pool.submit(fake_llm, None, "林松")
        out = fake_translate("林松来了")
        names, st = job.result(timeout=5)

    assert out == "đã dịch" and llm_done.is_set()
    assert names and st["calls"] == 1
