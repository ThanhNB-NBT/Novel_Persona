"""Tầng trừu tượng LLM — đổi provider không sửa pipeline."""
from __future__ import annotations

from dataclasses import dataclass

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
        self.client = OpenAI(base_url=base_url, api_key=api_key)
        self.model = model

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=2, max=30), reraise=True)
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
        return LLMResult(
            text=resp.choices[0].message.content or "",
            model=self.model,
            prompt_tokens=usage.prompt_tokens if usage else 0,
            completion_tokens=usage.completion_tokens if usage else 0,
        )


def get_provider() -> TranslationProvider:
    p = settings.llm_provider.lower()
    if p == "openrouter":
        return TranslationProvider("https://openrouter.ai/api/v1", settings.openrouter_api_key, settings.openrouter_model)
    if p == "fireworks":
        return TranslationProvider("https://api.fireworks.ai/inference/v1", settings.fireworks_api_key, settings.fireworks_model)
    if p == "nvidia":
        return TranslationProvider("https://integrate.api.nvidia.com/v1", settings.nvidia_api_key, settings.nvidia_model)
    raise ValueError(f"LLM_PROVIDER không hợp lệ: {p}")
