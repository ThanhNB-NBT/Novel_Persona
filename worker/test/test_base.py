"""Parser Retry-After (P3) + gom latency (P2b-0) — nhánh nhỏ chi phối backoff/đo, giữ check."""
import pytest
from novelworker.crawler import base
from novelworker.crawler.base import _is_transient_status, _record_fetch, _retry_after_seconds


class _Resp:
    def __init__(self, headers):
        self.headers = headers


def test_retry_after_seconds():
    assert _retry_after_seconds(_Resp({"Retry-After": "5"})) == 5.0
    assert _retry_after_seconds(_Resp({"retry-after": "12"})) == 12.0  # lowercase
    assert _retry_after_seconds(_Resp({"Retry-After": "-3"})) == 0.0    # âm → kẹp 0
    assert _retry_after_seconds(_Resp({})) == 0.0                       # không có header
    assert _retry_after_seconds(_Resp({"Retry-After": "Wed, 21 Oct"})) == 0.0  # HTTP-date → bỏ
    assert _retry_after_seconds(None) == 0.0


def test_transient_http_status():
    assert _is_transient_status(None)       # lỗi mạng/timeout
    assert _is_transient_status(403)        # chặn IP
    assert _is_transient_status(429)        # rate-limit
    assert _is_transient_status(503)
    assert not _is_transient_status(404)    # URL chương thật sự không tồn tại


def test_record_fetch_accumulates_then_resets(monkeypatch):
    import novelworker.db as db
    written = []
    monkeypatch.setattr(db, "record_crawl_latency", lambda *a: written.append(a))
    base._fetch_stats.pop("t", None)
    for _ in range(base._STATS_EVERY - 1):
        _record_fetch("t", 1.0)
    assert base._fetch_stats["t"]["n"] == base._STATS_EVERY - 1  # còn đang gom
    assert written == []                                         # chưa chạm ngưỡng, chưa ghi
    _record_fetch("t", None, timeout=True)                       # fetch fail (dt=None) chạm ngưỡng
    assert base._fetch_stats["t"]["n"] == 0                       # → ghi DB + reset
    assert base._fetch_stats["t"]["lat"] == []
    # (source, n, ok, p50, p95, max, timeouts, r429)
    src, n, ok, _p50, _p95, mx, timeouts, r429 = written[0]
    assert (src, n, ok, timeouts, r429) == ("t", base._STATS_EVERY, base._STATS_EVERY - 1, 1, 0)
    assert mx == 1.0


def test_empty_200_body_is_blocked_not_success(monkeypatch):
    """Fanqie 27/08 trả HTTP 200 body 0 byte khi chặn IP. Trước đây _get coi là thành
    công → adapter vỡ ở nơi parse và cả chu kỳ đánh oan hàng chục truyện thành failed."""
    from novelworker.crawler.base import SourceBlocked
    from novelworker.crawler.biquge import BiqugeAdapter

    a = BiqugeAdapter(base_url="https://ex.com", config={"novel_path": "/b/{book_id}/"},
                      source_row={"name": "ex"})
    calls = []

    class _R:
        status_code = 200
        content = b"  \n "
        headers: dict = {}

        def raise_for_status(self):
            pass

    a._session = type("S", (), {"get": staticmethod(
        lambda *args, **kw: (calls.append(1), _R())[1])})()
    with pytest.raises(SourceBlocked):
        a._get("/b/1/")
    assert len(calls) == 1        # chặn IP: KHÔNG retry, retry chỉ nuôi mức chặn
    assert a.fetch_ok == 0        # và không được tính là fetch khỏe
