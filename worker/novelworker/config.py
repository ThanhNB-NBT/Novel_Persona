from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Supabase
    supabase_url: str
    supabase_service_role_key: str

    # LLM — thứ tự ưu tiên, phân cách phẩy; lỗi/rate-limit thì tự chuyển provider kế.
    # free-first: nvidia (chính) → openrouter (dự phòng free) → fireworks (lưới cuối trả phí).
    llm_provider: str = "nvidia,openrouter,fireworks"
    openrouter_api_key: str = ""
    openrouter_model: str = "google/gemma-4-31b-it:free"
    fireworks_api_key: str = ""
    fireworks_model: str = "accounts/fireworks/models/deepseek-v4-flash"
    # nvidia có thể khai NHIỀU key (phân cách phẩy) — mỗi key 1 lane 40 RPM chạy song song.
    # nvidia_api_key (số ít) giữ để tương thích .env cũ.
    nvidia_api_key: str = ""
    nvidia_api_keys: str = ""
    nvidia_model: str = "mistralai/mistral-small-4-119b-2603"

    @property
    def nvidia_keys(self) -> list[str]:
        raw = self.nvidia_api_keys.strip() or self.nvidia_api_key.strip()
        return [k.strip() for k in raw.split(",") if k.strip()]

    # Crawler
    crawl_interval_min: int = 45
    http_proxy_url: str = ""
    # Discovery: số truyện MỚI tối đa thêm mỗi nguồn mỗi chu kỳ. Chiến lược "ít mà chất":
    # nguồn có ranking chỉ lấy từ ranking (lượt đọc = bộ lọc chất lượng), trần nhỏ.
    discover_new_per_cycle: int = 10
    # Lọc truyện mỏng: đang-ra dưới ngần này chương thì ẩn, không dịch metadata/chương mẫu
    # (truyện hoàn thành không bị lọc — ngắn mà trọn bộ vẫn đáng đọc).
    discover_min_chapters: int = 200
    # Refresh: số truyện canonical soi mục lục (bắt chương mới) mỗi nguồn mỗi chu kỳ,
    # xoay vòng theo last_checked_at. Trần để không nặng nhất thời khi kho truyện lớn.
    refresh_per_cycle: int = 60
    # Sức khoẻ nguồn: số chu kỳ TOÀN fetch fail liên tiếp trước khi tự tắt nguồn.
    source_fail_limit: int = 5

    # Worker
    worker_id: str = "worker-1"
    translator_concurrency: int = 2
    # Cầu chì chi phí: tổng số chương dịch tối đa mỗi ngày (mọi user).
    # 2-5 user, model free → 1000 quá thoải mái để đọc; cầu chì chỉ chặn bug app spam.
    max_chapters_per_day: int = 1000
    # Job 'running' quá số phút này (worker chết giữa chừng) sẽ được trả về hàng đợi
    stale_job_minutes: int = 10
    # Audit định kỳ: mỗi X phút quét chương done hỏng (còn tiếng Trung/cụt/mất đoạn) →
    # tự xếp lại dịch. Fuse đã chặn chương mới nên đây chủ yếu dọn nợ cũ; đặt thưa cho nhẹ.
    audit_interval_min: int = 120

    # Ưu tiên dịch theo người đang đọc (nhỏ = làm trước):
    active_read_hours: int = 8   # truyện có reader trong ngần này giờ = "đang đọc"
    prio_read: int = 5           # chương của truyện đang đọc — cực cao
    prio_follow: int = 30        # chương MỚI của truyện trong tủ sách — dịch đón trước
    prio_idle: int = 75          # chương đọc thử + chương truyện không ai đọc — nền
    sample_chapters: int = 1     # số chương dịch sẵn "đọc thử" khi có truyện mới
    # Timeout 1 call LLM (giây) — quá là fail nhanh để fallback sang provider kế
    llm_timeout_sec: int = 150


settings = Settings()
