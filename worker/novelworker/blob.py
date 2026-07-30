"""Cloudflare R2 (S3-compatible) lưu content_zh NGOÀI Supabase để nhẹ DB free tier.

Bật khi .env có đủ credential R2; thiếu bất kỳ trường nào → mọi hàm no-op (content_zh
nằm lại trong DB đúng như hành vi cũ). Nhờ vậy chạy local/test không cần R2 vẫn dịch được.

Bản gốc luôn cào lại được nên R2 KHÔNG cần là "source of truth" tuyệt đối: put_zh chỉ
báo True khi chắc đã lưu (lúc đó mới được NULL cột DB); get_zh trả None khi thiếu/hỏng để
caller tự defer cho crawler backfill.
"""
from __future__ import annotations

import logging
import threading

from .config import settings

log = logging.getLogger(__name__)

_lock = threading.Lock()
_client = None


def enabled() -> bool:
    return bool(settings.r2_account_id and settings.r2_access_key
               and settings.r2_secret_key and settings.r2_bucket)


def _c():
    global _client
    if _client is None:
        with _lock:
            if _client is None:
                import boto3
                from botocore.config import Config
                _client = boto3.client(
                    "s3",
                    endpoint_url=f"https://{settings.r2_account_id}.r2.cloudflarestorage.com",
                    aws_access_key_id=settings.r2_access_key,
                    aws_secret_access_key=settings.r2_secret_key,
                    region_name="auto",
                    config=Config(retries={"max_attempts": 3, "mode": "standard"},
                                  connect_timeout=10, read_timeout=30),
                )
    return _client


def _key(chapter_id: int) -> str:
    return f"zh/{chapter_id}"


def put_zh(chapter_id: int, text: str) -> bool:
    """Đẩy content_zh lên R2. True = chắc chắn đã lưu (caller được phép NULL cột DB).
    Tắt/rỗng/lỗi → False (giữ content_zh trong DB, không mất dữ liệu)."""
    if not enabled() or not text:
        return False
    try:
        _c().put_object(Bucket=settings.r2_bucket, Key=_key(chapter_id),
                        Body=text.encode("utf-8"),
                        ContentType="text/plain; charset=utf-8")
        return True
    except Exception:
        log.exception("R2 put_zh chương %s lỗi — giữ content_zh trong DB", chapter_id)
        return False


def get_zh(chapter_id: int) -> str | None:
    """Lấy content_zh từ R2. None nếu tắt/không có/lỗi (caller tự defer crawl backfill)."""
    if not enabled():
        return None
    try:
        obj = _c().get_object(Bucket=settings.r2_bucket, Key=_key(chapter_id))
        return obj["Body"].read().decode("utf-8")
    except Exception as e:
        # NoSuchKey = bình thường (chương chưa offload) → im lặng; còn lại mới cảnh báo.
        code = getattr(e, "response", {}).get("Error", {}).get("Code")
        if code not in ("NoSuchKey", "404"):
            log.warning("R2 get_zh chương %s lỗi: %s", chapter_id, e)
        return None


if __name__ == "__main__":
    # Self-check: tắt R2 thì put/get phải no-op; bật thì round-trip đúng chuỗi Hán.
    if not enabled():
        assert put_zh(1, "试") is False
        assert get_zh(1) is None
        print("R2 CHƯA cấu hình → no-op OK")
    else:
        s = "测试中文内容\n第二行"
        assert put_zh(999999, s) is True
        assert get_zh(999999) == s
        assert get_zh(888888) is None  # key không tồn tại
        print("R2 round-trip OK")
