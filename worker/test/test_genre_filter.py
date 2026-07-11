"""Lọc thể loại lúc discovery: chặn đô thị/lịch sử/ngôn tình, miễn trừ khi có
yếu tố kỳ ảo — nhưng KHÔNG ăn từ khoá trong đuôi truyện-đề-cử của mô tả."""
import os
from types import SimpleNamespace

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "x")

from novelworker.crawler.sync import genre_blocked  # noqa: E402


def meta(cats, desc=""):
    return SimpleNamespace(genres_zh=cats, description_zh=desc)


# đô thị thuần → chặn
assert genre_blocked(meta(["都市"], "官场沉浮，步步高升。")) == "都市"
# đô thị + hệ thống trong mô tả thật → cho qua
assert genre_blocked(meta(["都市"], "获得神级系统，开局无敌。")) is None
# đô thị + 系统 chỉ xuất hiện trong đuôi đề cử → VẪN chặn (lỗ đã vá 2026-07-11)
assert genre_blocked(meta(["都市"], "官场沉浮。小说推荐：神级系统、修仙高手")) == "都市"
# category có từ miễn trừ (言情+游戏) → cho qua
assert genre_blocked(meta(["言情", "游戏"])) is None
# không dính category chặn → cho qua
assert genre_blocked(meta(["玄幻"])) is None

print("test_genre_filter: OK")
