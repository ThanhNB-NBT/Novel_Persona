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
    # 2026-07-27: NVIDIA gỡ toàn bộ dòng qwen (410 end-of-life), thay tạm glm-5.2.
    # 2026-08-08: mistral-medium-3.5 EOL (410) + mistral-small-4/large-2/nemotron đều
    # 404/500/timeout; glm-5.2 chuẩn nhưng 200s/chương (reasoning). Đo lại 3 chương truyện 32:
    # deepseek-v4-flash 4/5 & 37s, gemma-4-31b 4/5 & 41s (nhưng sót hẳn 1 tên, deepseek chỉ
    # lệch dấu được reconcile nắn lại) → chọn deepseek-v4-flash. LLM ở đây CHỈ trích tên JSON
    # nên "deepseek lệch giọng dịch" (lý do gỡ 2026-07-10) không áp dụng.
    # 2026-08-10: deepseek-v4-flash timeout hẳn (94s) khi gọi TỪ VPS — quét cả 41 model
    # NIM ngay trong container thì chỉ 6 con còn trả lời, và NIM treo theo TỪNG model chứ
    # không bóp cả IP (llama-3.1-70b chỉ 2,6s cùng lúc gemma-4-31b timeout). Chấm bài
    # metadata thật (3 truyện, JSON + tên + mô tả):
    #   llama-3.1-70b-instruct      3/3 3/3 3/3  20,7s  ← chọn
    #   minimax-m3                  3/3 2/3 3/3  19,8s  (sót chữ Hán: "Thanh符Kiếp")
    #   nemotron-super-49b-v1       3/3 0/3 3/3   5,6s  (nhanh nhất, tên sai hết)
    #   mistral-nemotron            3/3 1/3 3/3  23,2s
    #   llama-3.1-8b-instruct       3/3 1/3 3/3   1,7s
    #   llama-3.2-3b-instruct       timeout
    # Nhiều model cách nhau dấu phẩy = chuỗi dự phòng, con đầu treo thì thử con kế NGAY
    # trong cùng job (xem build_chain). Model THẬT chỉnh ở app (worker_settings.llm_model,
    # worker đọc mỗi 60s) — hằng số dưới CHỈ là fallback khi không đọc được DB.
    nvidia_model: str = ("meta/llama-3.1-70b-instruct,minimaxai/minimax-m3,"
                         "nvidia/llama-3.3-nemotron-super-49b-v1")
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
    # Timeout 1 call LLM (giây). Hạ 150 → 90 (26/07). Trích tên giờ chạy nền nên timeout
    # KHÔNG còn ảnh hưởng tốc độ chương; nó chỉ định cỡ hàng đợi luồng nền (xem _NAME_POOL).
    # Cận dưới là độ trễ THẬT đo từ VPS: 38-79s/call, cùng key ấy từ máy nhà chỉ 2-3s.
    # Đừng hạ về 40 — sẽ giết phần lớn call đang chạy được, glossary hết được đắp.
    llm_timeout_sec: int = 90

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
    # Trần số câu CT2 gom vào một lượt giải mã. 0 = không giới hạn (mặc định của CT2) nghĩa
    # là cả chương 246 dòng nằm trong RAM cùng lúc — trên VPS 2GB là swap, chương dài từng
    # ngốn 2365s thay vì ~30s. Đo trên máy 8 lõi: batch 8 còn NHANH hơn không-giới-hạn 25%.
    hachimi_max_batch: int = 8
    # Chặn lặp máy móc lúc decode — audit 22/08 đo 8/48 chương bị nhân đôi câu
    # (zh sạch ⇒ lỗi decode). no_repeat_ngram cấm lặp lại đúng chuỗi 8 token liền
    # (đủ dài để không chạm lặp hợp pháp); repetition_penalty để 1.0 = tắt mặc định,
    # bật qua .env khi cần thí nghiệm.
    hachimi_no_repeat_ngram: int = 8
    hachimi_repetition_penalty: float = 1.0
    # Doc-level: ghép tối đa N dòng nguồn Trung phía trước làm ngữ cảnh (đúng định dạng train
    # `ctx ⟪ctx⟫ câu` của pipeline 17) để model hết bịa chủ ngữ. 0 = TẮT (hành vi cũ, an toàn) —
    # chỉ bật SAU khi deploy model đã train doc-level; model thường không hiểu ⟪ctx⟫ sẽ dịch loạn.
    hachimi_context_lines: int = 0
    hachimi_context_sep: str = "⟪ctx⟫"    # phải khớp HỆT SEP lúc train (pipeline 16/17)
    # Chỉ trích tên (LLM liệt kê) để đắp glossary ở CHƯƠNG ĐẦU — chặn cost mass-requeue.
    hachimi_extract_max_chapter: int = 20

    # Cloudflare R2 (S3-compatible) — lưu content_zh ngoài Supabase để nhẹ DB free tier.
    # Thiếu bất kỳ trường nào → tính năng TẮT, content_zh nằm lại trong DB như cũ.
    r2_account_id: str = ""
    r2_access_key: str = ""
    r2_secret_key: str = ""
    r2_bucket: str = ""


settings = Settings()
