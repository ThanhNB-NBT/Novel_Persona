from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

# Trỏ tuyệt đối vào worker/.env để script chạy từ thư mục con (hachimi/pipeline, hachimi/eval)
# vẫn đọc được cấu hình; trong container cwd đã là /app nên không đổi hành vi.
_ENV_FILE = Path(__file__).resolve().parents[1] / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=(".env", _ENV_FILE), extra="ignore")

    # Supabase
    supabase_url: str
    supabase_service_role_key: str

    # LLM — chỉ NVIDIA NIM (bỏ openrouter/fireworks 2026-07-10: fallback deepseek làm lệch giọng dịch).
    llm_provider: str = "nvidia"
    # nvidia có thể khai NHIỀU key (phân cách phẩy) — mỗi key 1 lane 40 RPM chạy song song.
    # nvidia_api_key (số ít) giữ để tương thích .env cũ.
    nvidia_api_key: str = ""
    nvidia_api_keys: str = ""
    # Nhánh Hachimi chỉ còn dùng LLM để TRÍCH TÊN cho glossary (+ dịch metadata). Đo trên
    # 6 chương truyện 32 (hachimi/eval/benchmark_analyze_names.py), tính điểm SAU bước
    # hanviet.reconcile vì đó mới là thứ vào glossary: qwen3-next 5/5, mistral-small 4/5
    # (nó viết "Erlton" — chữ Latin nên bảng tra không sửa được, sai là sai luôn),
    # gemma-4-31b 4/5 và chậm hơn, llama-4-maverick chỉ trích 4 term/chương nên sót nhiều.
    nvidia_model: str = "qwen/qwen3-next-80b-a3b-instruct"
    # Pacing theo từng API key, thấp hơn trần NVIDIA 40 RPM để chừa biên đồng hồ/retry.
    nvidia_rpm_limit: int = Field(default=30, ge=1, le=39)

    @property
    def nvidia_keys(self) -> list[str]:
        raw = self.nvidia_api_keys.strip() or self.nvidia_api_key.strip()
        return [k.strip() for k in raw.split(",") if k.strip()]

    # Crawler
    crawl_interval_min: int = 45
    http_proxy_url: str = ""
    # Discovery: quota truyện MỚI cho ranking và cho hàng đợi gộp của mỗi nguồn/chu kỳ.
    discover_new_per_cycle: int = 10
    # Lọc truyện mỏng: đang-ra dưới ngần này chương thì ẩn, không dịch metadata/chương mẫu
    # (truyện hoàn thành không bị lọc — ngắn mà trọn bộ vẫn đáng đọc).
    discover_min_chapters: int = 200
    # Faloo chỉ dùng phần đọc miễn phí. Chỉ nhận truyện có số chương free LỚN HƠN
    # ngưỡng này (500 nghĩa là từ 501 chương free trở lên).
    faloo_free_chapter_threshold: int = 500
    # Refresh: số truyện canonical soi mục lục (bắt chương mới) mỗi nguồn mỗi chu kỳ,
    # xoay vòng theo last_checked_at. Trần để không nặng nhất thời khi kho truyện lớn.
    refresh_per_cycle: int = 60
    # Sức khoẻ nguồn: số chu kỳ TOÀN fetch fail liên tiếp trước khi tự tắt nguồn.
    source_fail_limit: int = 5

    # Worker
    worker_id: str = "worker-1"
    # Nhiều job bay đồng thời hơn số key; limiter trong provider giữ đúng RPM từng key.
    translator_concurrency: int = 8
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
    crawl_fetch_batch: int = 20  # số chương tải nguồn tối đa cho một novel mỗi tick
    # Timeout 1 call LLM (giây). Hạ 150 → 40 (26/07): với engine Hachimi, LLM chỉ còn làm
    # việc phụ (trích tên, vá Hán sót) — không đáng để một call treo 2,5 phút. Đo trên VPS:
    # chương 2 call lỗi mất 324s trong khi dịch thật chỉ ~25s. LLM_PROVIDER giờ chỉ có
    # nvidia nên hết timeout là hết đường, chờ lâu không mua thêm cơ hội nào.
    llm_timeout_sec: int = 40

    # Engine dịch mặc định cho truyện CHƯA ghim provider (truyện mới). 'hachimi' = CT2
    # local (rẻ), đặt 'nvidia' nếu muốn truyện mới vẫn dùng LLM.
    default_engine: str = "hachimi"
    # Engine Hachimi (CT2 local) — dùng cho truyện có translation_provider == 'hachimi'.
    hachimi_model_dir: str = "models/hachimi-ct2"
    hachimi_compute_type: str = "int8"
    hachimi_cpu_threads: int = 0          # 0 = để CT2 tự chọn theo số core
    # Quét beam×n-best trên 60 cảnh khoá: 4→6 cho đại từ hiện đại 10→9, similarity 0,7220→
    # 0,7238, câu/cảnh 3,5→3,6 với +27% thời gian; beam 8 không hơn beam 6 mà tốn +62%.
    hachimi_beam_size: int = 6            # đo A/B: beam=1 chậm hơn (greedy lặp) + kém
    hachimi_max_len: int = 180            # output thật median 27/max 98 token → 180 dư trần
    # n-best: beam search đã tính sẵn 4 giả thuyết; lấy hết ra rồi chọn bằng cổng chất
    # lượng của dự án. Đo 12 chương thật: đại từ hiện đại 81→64, quote lệch 3→2, câu/chương
    # 97→100, thời gian +1,6% (nhiễu). 1 = giữ hành vi cũ (chỉ lấy giả thuyết đầu).
    hachimi_nbest: int = 6
    # Chỉ trích tên (LLM liệt kê) để đắp glossary ở CHƯƠNG ĐẦU — chặn cost mass-requeue.
    hachimi_extract_max_chapter: int = 20


settings = Settings()
