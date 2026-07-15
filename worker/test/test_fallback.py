"""Self-check FallbackChain: đổi provider khi lỗi HTTP / output kém, hết chain thì raise.
Provider giả + chặn db.record_model_call (không mạng, không LLM)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker import db
from novelworker.translator.providers import FallbackChain, LLMResult

calls: list[tuple[str, bool]] = []
db.record_model_call = lambda model, ms, ok, error=None: calls.append((model, ok))


class Fake:
    """Provider giả: text=None nghĩa là raise (mô phỏng 429/timeout)."""
    def __init__(self, name: str, text: str | None):
        self.model = name
        self.text = text

    def complete(self, system, user, temperature=0.3, max_tokens=8192, validate=None):
        if self.text is None:
            calls.append((self.model, False))
            raise RuntimeError(f"{self.model} lỗi")
        res = LLMResult(text=self.text, model=self.model, prompt_tokens=1, completion_tokens=1)
        calls.append((self.model, True))
        return res


def main() -> None:
    # provider đầu OK → dùng luôn, không gọi provider sau
    calls.clear()
    chain = FallbackChain([("a", Fake("a", "bản dịch tốt")), ("b", Fake("b", "không tới lượt"))])
    assert chain.complete("s", "u").model == "a"
    assert calls == [("a", True)]

    # provider đầu raise → tự chuyển provider kế trong CÙNG lần gọi
    calls.clear()
    chain = FallbackChain([("a", Fake("a", None)), ("b", Fake("b", "cứu"))])
    assert chain.complete("s", "u").model == "b"
    assert calls == [("a", False), ("b", True)]

    # cả chain fail → raise lỗi cuối cùng
    chain = FallbackChain([("a", Fake("a", None)), ("b", Fake("b", None))])
    try:
        chain.complete("s", "u")
        raise AssertionError("phải raise khi mọi provider fail")
    except RuntimeError as e:
        assert "b lỗi" in str(e)


if __name__ == "__main__":
    main()
    print("OK — test_fallback pass")
