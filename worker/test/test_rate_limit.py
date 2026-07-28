"""Self-check chống 429: không retry khi bị rate limit, key dính bị bắt nghỉ,
và số request đang bay trên mỗi key bị chặn trần. Không mạng, không LLM."""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker import db
from novelworker.translator import providers as P

db.record_model_call = lambda model, ms, ok, error=None: None


def _provider(key: str) -> P.TranslationProvider:
    p = P.TranslationProvider("https://example.invalid/v1", key, "m", "nvidia")
    p.client = None  # chặn mọi call thật lọt ra ngoài
    return p


class _Boom:
    """Giả client: đếm số lần bị gọi, luôn raise lỗi cho trước."""
    def __init__(self, exc):
        self.exc, self.n = exc, 0

    def create(self, **kw):
        self.n += 1
        raise self.exc


def _install(p: P.TranslationProvider, boom: _Boom) -> None:
    p.client = type("C", (), {"chat": type("Ch", (), {"completions": boom})()})()


def main() -> None:
    # 429 → gọi ĐÚNG 1 lần (tenacity không retry) và key bị đẩy lịch ~60s
    p = _provider("k429")
    boom = _Boom(RuntimeError("Error code: 429 - Too Many Requests"))
    _install(p, boom)
    try:
        p.complete("s", "u")
        raise AssertionError("phải raise 429")
    except RuntimeError as e:
        assert "429" in str(e)
    assert boom.n == 1, f"429 bị retry {boom.n} lần"
    assert P._next_request_at["k429"] - time.monotonic() > 50, "key dính 429 phải bị bắt nghỉ"

    # lỗi thường (timeout) vẫn retry 1 lần như cũ
    p = _provider("kto")
    boom = _Boom(RuntimeError("timeout"))
    _install(p, boom)
    try:
        p.complete("s", "u")
        raise AssertionError("phải raise timeout")
    except RuntimeError:
        pass
    assert boom.n == 2, f"lỗi thường phải retry, thấy {boom.n} lần gọi"

    # trần request đang bay: cùng key dùng chung 1 semaphore, khác key thì riêng
    assert P._key_semaphore("ka") is P._key_semaphore("ka")
    assert P._key_semaphore("ka") is not P._key_semaphore("kb")
    sem = P._key_semaphore("ka")
    for _ in range(P._MAX_INFLIGHT_PER_KEY):
        assert sem.acquire(blocking=False)
    assert not sem.acquire(blocking=False), "quá trần vẫn lọt request"


if __name__ == "__main__":
    main()
    print("OK — test_rate_limit pass")
