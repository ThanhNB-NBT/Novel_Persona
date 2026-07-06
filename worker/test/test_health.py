"""Self-check bộ đếm sức khoẻ nguồn: _get đếm ok/err, reset đúng."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.biquge import BiqugeAdapter


class _Resp:
    def __init__(self, ok: bool):
        self._ok = ok
        self.content = b"<html>x</html>"

    def raise_for_status(self):
        if not self._ok:
            raise RuntimeError("HTTP 500")


def main() -> None:
    a = BiqugeAdapter(base_url="https://x.com", config={}, source_row={"name": "x"})
    assert a.fetch_ok == 0 and a.fetch_err == 0

    a._session.get = lambda url: _Resp(True)
    a._get("/1/")
    a._get("/2/")
    assert a.fetch_ok == 2 and a.fetch_err == 0

    # fetch lỗi → err++ và vẫn ném ra (không nuốt)
    a._session.get = lambda url: _Resp(False)
    for _ in range(3):
        try:
            a._get("/dead/")
            assert False, "phải ném lỗi"
        except RuntimeError:
            pass
    assert a.fetch_ok == 2 and a.fetch_err == 3

    a.reset_health_counters()
    assert a.fetch_ok == 0 and a.fetch_err == 0


if __name__ == "__main__":
    main()
    print("OK — health counter test pass")
