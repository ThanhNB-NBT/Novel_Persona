"""Self-check conditional GET cho soi mục lục (ETag/Last-Modified → 304 bỏ qua parse)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler import sync
from novelworker.crawler.base import ChapterRef, SourceTransient
from novelworker.crawler.biquge import BiqugeAdapter


def _biquge(config=None):
    return BiqugeAdapter(base_url="https://www.xqiushubang.com",
                         config={"novel_path": "/index/{book_id}/",
                                 "conditional_toc": True, **(config or {})},
                         source_row={"name": "qiushubang"})


class _Resp:
    def __init__(self, status=304, content=b"", headers=None):
        self.status_code = status
        self.content = content
        self.headers = headers or {}

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")


def main() -> None:
    a = _biquge()
    assert a._toc_probe_path("77") == "/index/77/"

    # --- _get_if_changed: 304 → (None, etag|lm giữ nguyên), tính là fetch_ok
    seen_headers = []

    def sess_get(url, timeout=None, headers=None):
        seen_headers.append(headers)
        return _Resp(304, b"", {"X": "y"})

    a._session = type("S", (), {"get": staticmethod(sess_get)})()
    out = a._get_if_changed("/index/77/", etag='"abc"', last_modified="Tue, 22 Aug 2026")
    assert out == (None, '"abc"', "Tue, 22 Aug 2026"), out
    assert a.fetch_ok == 1 and a.fetch_err == 0
    assert seen_headers[0]["If-None-Match"] == '"abc"'
    assert seen_headers[0]["If-Modified-Since"].startswith("Tue")

    # --- 200 kèm header mới → trả html + mốc mới (curl_cffi headers phân loại hoa-thường,
    # fake dùng key viết thường như thực tế server trả về)
    def sess_get_200(url, timeout=None, headers=None):
        return _Resp(200, "<html>toc</html>".encode(),
                     {"etag": '"v2"', "last-modified": "Wed, 23 Aug 2026"})

    a._session = type("S", (), {"get": staticmethod(sess_get_200)})()
    html, e2, lm2 = a._get_if_changed("/index/77/", etag='"abc"')
    assert html == "<html>toc</html>" and e2 == '"v2"' and lm2 == "Wed, 23 Aug 2026"

    # --- fetch_chapter_list_conditional: 304 → None + xoá last_toc_status sót
    a.last_toc_status = "completed"  # giá trị của truyện SOI TRƯỚC
    a._session = type("S", (), {"get": staticmethod(sess_get)})()
    refs, e2, lm2 = a.fetch_chapter_list_conditional("77", etag='"abc"', last_modified="T")
    assert refs is None and e2 == '"abc"' and lm2 == "T"
    assert a.last_toc_status is None

    # --- lỗi cứng 404 → raise thẳng (không SourceTransient)
    def sess_get_404(url, timeout=None, headers=None):
        err = Exception("not found")
        err.response = _Resp(404)
        raise err

    a2 = _biquge()
    a2._session = type("S", (), {"get": staticmethod(sess_get_404)})()
    try:
        a2._get_if_changed("/index/77/")
        raise SystemExit("phải raise")
    except SourceTransient:
        raise SystemExit("404 phải là lỗi cứng, không phải transient")
    except Exception:
        pass  # đúng kỳ vọng

    # --- sync_chapter_list: 304 → trả tổng đã lưu, KHÔNG đụng fetch_chapter_list,
    # không ghi gì vào chapters/novels.
    class _Q:
        def __init__(self, table):
            self.table = table

        def select(self, *_a, **_k):
            return self

        def eq(self, *_a, **_k):
            return self

        def is_(self, *_a, **_k):
            return self

        def order(self, *_a, **_k):
            return self

        def limit(self, *_a, **_k):
            return self

        def single(self):
            return self

        def execute(self):
            if getattr(self, "_table_name", "") == "":
                pass
            return type("R", (), {"data": {
                "chapter_count_source": 500, "toc_etag": '"e1"',
                "toc_last_modified": "lm1"}})()

    class _SB:
        def table(self, name):
            q = _Q(name)
            return q

    calls = {"fetch_full": 0}

    class _Fake:
        config = {"conditional_toc": True}
        name = "fake"
        last_toc_status = None

        @staticmethod
        def fetch_chapter_list_conditional(bid, etag=None, last_modified=None):
            return None, '"e1"', "lm1"

        @staticmethod
        def fetch_chapter_list(bid):
            calls["fetch_full"] += 1
            return [ChapterRef(i + 1, f"77/{i}", "c") for i in range(10)]

    originals = (sync.db.sb, sync.time.sleep)
    sync.db.sb = lambda: _SB()
    sync.time.sleep = lambda *_a: None
    try:
        total, added = sync.sync_chapter_list(_Fake(), 9, "77", limit_stubs=0,
                                              allow_conditional=True)
    finally:
        sync.db.sb, sync.time.sleep = originals
    assert (total, added) == (500, 0), (total, added)
    assert calls["fetch_full"] == 0  # 304 thì không tải mục lục đầy đủ


if __name__ == "__main__":
    main()
    print("OK — conditional TOC test pass")
