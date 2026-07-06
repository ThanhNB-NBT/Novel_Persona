"""Tầng trừu tượng LLM — đổi provider không sửa pipeline."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from openai import OpenAI
from tenacity import retry, stop_after_attempt, wait_exponential

from ..config import settings


@dataclass
class LLMResult:
    text: str
    model: str
    prompt_tokens: int
    completion_tokens: int


class TranslationProvider:
    """OpenAI-compatible client — dùng chung cho OpenRouter / Fireworks / NVIDIA NIM."""

    def __init__(self, base_url: str, api_key: str, model: str):
        # timeout ngắn + không retry ngầm: provider nghẽn (NIM free hay xếp hàng)
        # phải fail nhanh để FallbackChain chuyển provider kế, thay vì treo 10'+
        self.client = OpenAI(base_url=base_url, api_key=api_key,
                             timeout=settings.llm_timeout_sec, max_retries=0)
        self.model = model

    @retry(stop=stop_after_attempt(2), wait=wait_exponential(min=2, max=10), reraise=True)
    def complete(self, system: str, user: str, temperature: float = 0.3, max_tokens: int = 8192) -> LLMResult:
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
        # bị cắt vì chạm trần max_tokens → output cụt NGẦM (thiếu câu cuối + mất
        # SUMMARY/GLOSSARY) mà các check độ dài có thể lọt → coi là lỗi, để chain retry
        if resp.choices[0].finish_reason == "length":
            raise RuntimeError(f"Output bị cắt vì chạm max_tokens (model {self.model})")
        return LLMResult(
            text=resp.choices[0].message.content or "",
            model=self.model,
            prompt_tokens=usage.prompt_tokens if usage else 0,
            completion_tokens=usage.completion_tokens if usage else 0,
        )


class FallbackChain:
    """Thử lần lượt từng provider theo thứ tự LLM_PROVIDER cho tới khi thành công.

    Ví dụ LLM_PROVIDER=nvidia,fireworks,openrouter:
    NVIDIA NIM free là chính; bị rate-limit (429) hoặc lỗi thì tự chuyển
    Fireworks rồi OpenRouter trong cùng lần gọi — job không fail oan.
    (Mỗi provider bên trong đã có tenacity retry 3 lần riêng.)
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
        import time
        from .. import db
        log = logging.getLogger(__name__)
        last_exc: Exception | None = None
        for name, p in self.providers:
            t0 = time.time()
            try:
                res = p.complete(system, user, temperature=temperature, max_tokens=max_tokens)
                if validate:
                    validate(res)  # raise → provider này coi như hỏng, thử provider kế
                db.record_model_call(res.model, (time.time() - t0) * 1000, ok=True)
                return res
            except Exception as e:
                db.record_model_call(p.model, (time.time() - t0) * 1000, ok=False, error=str(e))
                last_exc = e
                log.warning("Provider '%s' lỗi (%s) — chuyển provider kế tiếp", name, e)
        raise last_exc if last_exc else RuntimeError("Không có provider nào khả dụng")


_BASE_URLS = {
    "openrouter": "https://openrouter.ai/api/v1",
    "fireworks": "https://api.fireworks.ai/inference/v1",
    "nvidia": "https://integrate.api.nvidia.com/v1",
}
_MODELS = {
    "openrouter": lambda: settings.openrouter_model,
    "fireworks": lambda: settings.fireworks_model,
    "nvidia": lambda: settings.nvidia_model,
}


def _make(name: str, api_key: str) -> tuple[str, TranslationProvider]:
    return name, TranslationProvider(_BASE_URLS[name], api_key, _MODELS[name]())


def build_chain(slot: int = 0) -> TranslationProvider | FallbackChain:
    """Chain provider cho 1 luồng dịch (slot).

    nvidia có thể khai NHIỀU key (nvidia_api_keys, phân cách phẩy) → mỗi luồng ghim
    key[slot % số_key] để 2+ key chạy SONG SONG (mỗi key 1 lane 40 RPM). Cùng model
    nên văn phong không lệch. openrouter/fireworks là fallback dùng chung.
    Provider chưa có key thì bỏ qua.
    """
    names = [n.strip().lower() for n in settings.llm_provider.split(",") if n.strip()]
    chain: list[tuple[str, TranslationProvider]] = []
    for n in names:
        if n == "nvidia":
            keys = settings.nvidia_keys
            if keys:
                chain.append(_make("nvidia", keys[slot % len(keys)]))
        elif n in ("openrouter", "fireworks"):
            key = settings.openrouter_api_key if n == "openrouter" else settings.fireworks_api_key
            if key:
                chain.append(_make(n, key))
        else:
            raise ValueError(f"LLM_PROVIDER không hợp lệ: {n}")
    if not chain:
        raise ValueError("Không có provider nào có API key — kiểm tra .env")
    # Luôn bọc FallbackChain (kể cả 1 provider) để `complete(validate=...)` đồng nhất.
    return FallbackChain(chain)
