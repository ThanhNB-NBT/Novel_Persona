from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Supabase
    supabase_url: str
    supabase_service_role_key: str

    # LLM
    llm_provider: str = "openrouter"  # openrouter | fireworks | nvidia
    openrouter_api_key: str = ""
    openrouter_model: str = "deepseek/deepseek-chat-v3-0324"
    fireworks_api_key: str = ""
    fireworks_model: str = "accounts/fireworks/models/deepseek-v3"
    nvidia_api_key: str = ""
    nvidia_model: str = "deepseek-ai/deepseek-r1"

    # Crawler
    crawl_interval_min: int = 45
    http_proxy_url: str = ""
    fanqie_cookie: str = ""

    # Worker
    worker_id: str = "worker-1"
    translator_concurrency: int = 2


settings = Settings()
