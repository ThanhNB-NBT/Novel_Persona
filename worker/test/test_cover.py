"""Self-check cache bìa: idempotent với URL storage, phát hiện đuôi, nuốt lỗi tải."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker import db
from novelworker.crawler import sync


class _FakeAdapter:
    def __init__(self, result=None, exc=None):
        self._result = result
        self._exc = exc

    def fetch_bytes(self, url):
        if self._exc:
            raise self._exc
        return self._result


def main() -> None:
    uploaded = {}
    db.upload_cover = lambda path, data, ctype: uploaded.update(path=path, ctype=ctype, n=len(data))
    db.cover_public_url = lambda path: f"https://x.supabase.co/storage/v1/object/public/covers/{path}"

    # None / rỗng → None
    assert sync.cache_cover(_FakeAdapter(), 1, None) is None

    # đã là URL storage của mình → trả nguyên (không tải lại)
    already = "https://x.supabase.co/storage/v1/object/public/covers/9.jpg"
    assert sync.cache_cover(_FakeAdapter(exc=RuntimeError("phải không được gọi")), 9, already) == already

    # bìa jpg bình thường → upload + trả public url, đuôi .jpg
    img = b"\xff\xd8\xff" + b"x" * 500
    url = sync.cache_cover(_FakeAdapter((img, "image/jpeg")), 42, "http://src/cover")
    assert url.endswith("/covers/42.jpg"), url
    assert uploaded["path"] == "42.jpg" and uploaded["n"] == len(img)

    # content-type png → đuôi .png
    uploaded.clear()
    url = sync.cache_cover(_FakeAdapter((b"\x89PNG" + b"y" * 500, "image/png")), 7, "http://src/x")
    assert url.endswith("/covers/7.png"), url

    # tải lỗi → None (giữ hotlink cũ)
    assert sync.cache_cover(_FakeAdapter(exc=RuntimeError("timeout")), 5, "http://src/dead") is None

    # ảnh quá nhỏ (hỏng/trống) → None
    assert sync.cache_cover(_FakeAdapter((b"tiny", "image/jpeg")), 6, "http://src/small") is None


if __name__ == "__main__":
    main()
    print("OK — cache cover test pass")
