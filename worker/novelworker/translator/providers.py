"""Tầng trừu tượng LLM — đổi provider không sửa pipeline."""
from __future__ import annotations

import threading
import time
from dataclasses import dataclass, replace
from typing import Callable

from openai import OpenAI
from tenacity import retry, retry_if_exception, stop_after_attempt, wait_exponential

from ..config import settings

# Đếm REQUEST thật + token cho MỘT chương (per-thread: mỗi luồng dịch một chương).
# Đặt trong TranslationProvider.complete nên mỗi lượt tenacity retry đều được tính.
_stats = threading.local()
_rate_lock = threading.Lock()
_next_request_at: dict[str, float] = {}

# Giãn 30 rpm/key vẫn dính 429 từng chùm dù 2 key là 2 tài khoản riêng → trần thật
# không chỉ tính theo PHÚT mà cả số request ĐANG BAY (call từ VPS mất 38-79s, 2 lane
# dịch + 6 luồng trích tên nền = cả nắm request chồng nhau trên cùng key).
# ponytail: hằng số 2; nếu vẫn 429 thì hạ xuống 1 trước khi đụng tới rpm.
_MAX_INFLIGHT_PER_KEY = 2
_inflight: dict[str, threading.Semaphore] = {}
# 429 rồi mà bắn tiếp là tự kéo dài lệnh cấm → cho KEY ĐÓ nghỉ trọn 1 phút.
_RATE_LIMIT_COOLDOWN_SEC = 60.0


def _is_rate_limited(exc: BaseException) -> bool:
    return getattr(exc, "status_code", None) == 429 or "429" in str(exc)


def _wait_for_rate_slot(api_key: str) -> None:
    """Giãn đều request theo từng key; mọi lane/retry trong process dùng chung lịch."""
    interval = 60.0 / settings.nvidia_rpm_limit
    with _rate_lock:
        now = time.monotonic()
        ready = max(now, _next_request_at.get(api_key, now))
        _next_request_at[api_key] = ready + interval
    if ready > now:
        time.sleep(ready - now)


def _note_rate_limited(api_key: str) -> None:
    """Đẩy lịch của key lùi 1 phút — mọi lane trong process cùng nhịn, không riêng lane dính."""
    with _rate_lock:
        _next_request_at[api_key] = max(
            _next_request_at.get(api_key, 0.0), time.monotonic() + _RATE_LIMIT_COOLDOWN_SEC)


def _key_semaphore(api_key: str) -> threading.Semaphore:
    with _rate_lock:
        return _inflight.setdefault(api_key, threading.Semaphore(_MAX_INFLIGHT_PER_KEY))


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

    # 429 KHÔNG retry: thử lại sau 2s lúc quota đang cạn chỉ nhân đôi số request bị
    # chặn (log VPS: 45 dòng 429/12h thực chất ~20 sự cố bị nhân đôi). Job tự quay lại
    # hàng đợi, lúc đó key đã hết cooldown.
    @retry(stop=stop_after_attempt(2), wait=wait_exponential(min=2, max=10), reraise=True,
           retry=retry_if_exception(lambda e: not _is_rate_limited(e)))
    def complete(
        self, system: str, user: str, temperature: float = 0.3, max_tokens: int = 8192,
        validate: Callable[[LLMResult], None] | None = None,
    ) -> LLMResult:
        from .. import db

        t0 = time.time()
        _stats.calls = getattr(_stats, "calls", 0) + 1
        _wait_for_rate_slot(self.api_key)
        try:
            with _key_semaphore(self.api_key):
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
            if _is_rate_limited(exc):
                _note_rate_limited(self.api_key)
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
                # Kèm model: chain giờ có nhiều model cùng tên provider 'nvidia', thiếu nó
                # thì log không cho biết con nào chết.
                log.warning("Provider '%s' model '%s' lỗi (%s) — thử cái kế tiếp",
                            name, p.model, e)
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
    key = keys[slot % len(keys)]
    # nvidia_model nhận NHIỀU model, cách nhau dấu phẩy. NIM treo/khai tử theo TỪNG model
    # (deepseek-v4-flash timeout 184s từ VPS 10/08, qwen3-next EOL 27/07) — model đầu hỏng
    # thì thử con kế NGAY trong cùng job, thay vì hỏng job rồi chờ retry với đúng model đó.
    # Đặt danh sách ở worker_settings.llm_model nên đổi thứ tự khỏi cần deploy.
    models = [m.strip() for m in settings.nvidia_model.split(",") if m.strip()]
    # Luôn bọc FallbackChain (kể cả 1 provider) để `complete(validate=...)` đồng nhất.
    return FallbackChain([("nvidia", TranslationProvider(_NVIDIA_BASE_URL, key, m, "nvidia"))
                          for m in models])
