"""Tầng trừu tượng LLM — đổi provider không sửa pipeline."""
from __future__ import annotations

import threading
import time
from dataclasses import dataclass, replace
from typing import Callable

from openai import OpenAI
from tenacity import retry, stop_after_attempt, wait_exponential

from ..config import settings

# Đếm REQUEST thật + token cho MỘT chương (per-thread: mỗi luồng dịch một chương).
# Đặt trong TranslationProvider.complete nên mỗi lượt tenacity retry đều được tính.
_stats = threading.local()
_rate_lock = threading.Lock()
_next_request_at: dict[str, float] = {}


def _wait_for_rate_slot(api_key: str) -> None:
    """Giãn đều request theo từng key; mọi lane/retry trong process dùng chung lịch."""
    interval = 60.0 / settings.nvidia_rpm_limit
    with _rate_lock:
        now = time.monotonic()
        ready = max(now, _next_request_at.get(api_key, now))
        _next_request_at[api_key] = ready + interval
    if ready > now:
        time.sleep(ready - now)


def reset_call_stats() -> None:
    _stats.calls = _stats.failures = 0
    _stats.prompt_tokens = _stats.completion_tokens = 0


def get_call_stats() -> dict:
    return {"calls": getattr(_stats, "calls", 0),
            "failures": getattr(_stats, "failures", 0),
            "prompt_tokens": getattr(_stats, "prompt_tokens", 0),
            "completion_tokens": getattr(_stats, "completion_tokens", 0)}


@dataclass
class LLMResult:
    text: str
    model: str
    prompt_tokens: int
    completion_tokens: int
    provider: str = ""


class TranslationProvider:
    """OpenAI-compatible client — dùng chung cho OpenRouter / Fireworks / NVIDIA NIM."""

    def __init__(self, base_url: str, api_key: str, model: str, provider: str = "",
                 timeout_sec: int | None = None):
        # timeout ngắn + không retry ngầm: provider nghẽn (NIM free hay xếp hàng)
        # phải fail nhanh để FallbackChain chuyển provider kế, thay vì treo 10'+
        self.timeout_sec = timeout_sec or settings.llm_timeout_sec
        self.client = OpenAI(base_url=base_url, api_key=api_key,
                             timeout=self.timeout_sec, max_retries=0)
        self.model = model
        self.provider = provider
        self.base_url = base_url
        self.api_key = api_key

    def with_model(self, model: str) -> "TranslationProvider":
        return TranslationProvider(self.base_url, self.api_key, model, self.provider, self.timeout_sec)

    @retry(stop=stop_after_attempt(2), wait=wait_exponential(min=2, max=10), reraise=True)
    def complete(
        self, system: str, user: str, temperature: float = 0.3, max_tokens: int = 8192,
        validate: Callable[[LLMResult], None] | None = None,
    ) -> LLMResult:
        from .. import db

        t0 = time.time()
        _stats.calls = getattr(_stats, "calls", 0) + 1
        _wait_for_rate_slot(self.api_key)
        try:
            resp = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                temperature=temperature,
                max_tokens=max_tokens,
            )
            usage = resp.usage
            prompt_tokens = usage.prompt_tokens if usage else 0
            completion_tokens = usage.completion_tokens if usage else 0
            # Tính cả token của output bị fuse/length loại vì request đó vẫn tiêu quota.
            _stats.prompt_tokens = getattr(_stats, "prompt_tokens", 0) + prompt_tokens
            _stats.completion_tokens = getattr(_stats, "completion_tokens", 0) + completion_tokens
            # bị cắt vì chạm trần max_tokens → output cụt NGẦM (thiếu câu cuối + mất
            # SUMMARY/GLOSSARY) mà các check độ dài có thể lọt → coi là lỗi, để chain retry
            if resp.choices[0].finish_reason == "length":
                raise RuntimeError(f"Output bị cắt vì chạm max_tokens (model {self.model})")
            result = LLMResult(
                text=resp.choices[0].message.content or "",
                model=self.model,
                prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
                provider=self.provider,
            )
            if validate:
                validate(result)
            db.record_model_call(self.model, (time.time() - t0) * 1000, ok=True)
            return result
        except Exception as exc:
            _stats.failures = getattr(_stats, "failures", 0) + 1
            db.record_model_call(
                self.model, (time.time() - t0) * 1000, ok=False, error=str(exc))
            raise


class FallbackChain:
    """Thử lần lượt từng provider theo thứ tự LLM_PROVIDER cho tới khi thành công.

    Từ 2026-07-10 chỉ còn nvidia (nhiều key) — chain giữ lại vì cho phép
    nhiều lane key và fuse chất lượng validate nằm trong cùng vòng thử.
    """

    def __init__(self, providers: list[tuple[str, TranslationProvider]]):
        self.providers = providers

    def complete(
        self, system: str, user: str, temperature: float = 0.3, max_tokens: int = 8192,
        validate: Callable[[LLMResult], None] | None = None,
    ) -> LLMResult:
        """Thử lần lượt provider. `validate` (nếu có) raise khi output kém chất lượng
        (trả nguyên văn tiếng Trung / quá ngắn) → coi như provider lỗi, chuyển provider
        kế NGAY trong cùng lần dịch thay vì fail job (fuse chất lượng nằm TRONG chain)."""
        import logging
        log = logging.getLogger(__name__)
        last_exc: Exception | None = None
        for name, p in self.providers:
            try:
                # validate truyền VÀO provider: fuse chất lượng fail → tenacity retry
                # cùng model trước (quan trọng khi chỉ còn 1 provider), rồi mới coi là lỗi
                res = p.complete(system, user, temperature=temperature,
                                 max_tokens=max_tokens, validate=validate)
                return replace(res, provider=name)
            except Exception as e:
                last_exc = e
                log.warning("Provider '%s' lỗi (%s) — chuyển provider kế tiếp", name, e)
        raise last_exc if last_exc else RuntimeError("Không có provider nào khả dụng")

    def pin(self, provider: str, model: str) -> "FallbackChain":
        """Khôi phục đúng provider/model đã ghim cho một truyện.

        Truyện còn ghim provider đã gỡ (openrouter/fireworks cũ) → dùng chain
        hiện tại (nvidia) thay vì fail job; giọng đổi một lần rồi ổn định.
        """
        for name, item in self.providers:
            if name == provider:
                return FallbackChain([(name, item.with_model(model))])
        import logging
        logging.getLogger(__name__).warning(
            "Provider đã ghim '%s' không còn — dùng nvidia thay", provider)
        return self


_NVIDIA_BASE_URL = "https://integrate.api.nvidia.com/v1"


def build_chain(slot: int = 0) -> FallbackChain:
    """Chain provider cho 1 luồng dịch (slot) — chỉ NVIDIA NIM.

    Khai NHIỀU key (nvidia_api_keys, phân cách phẩy) → mỗi luồng ghim
    key[slot % số_key] để 2+ key chạy SONG SONG (mỗi key 1 lane 40 RPM).
    """
    keys = settings.nvidia_keys
    if not keys:
        raise ValueError("Thiếu NVIDIA_API_KEYS — kiểm tra .env")
    provider = TranslationProvider(
        _NVIDIA_BASE_URL, keys[slot % len(keys)], settings.nvidia_model, "nvidia")
    # Luôn bọc FallbackChain (kể cả 1 provider) để `complete(validate=...)` đồng nhất.
    return FallbackChain([("nvidia", provider)])
