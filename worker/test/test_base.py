"""Parser Retry-After (P3) + gom latency (P2b-0) — nhánh nhỏ chi phối backoff/đo, giữ check."""
from novelworker.crawler import base
from novelworker.crawler.base import _record_fetch, _retry_after_seconds


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
