"""Interface chung cho mọi nguồn crawl."""
from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from curl_cffi import requests as cffi_requests

from ..config import settings


class ChapterNotReady(Exception):
    """Nguồn đã liệt kê chương trong mục lục nhưng trang chương CHƯA tồn tại
    (redirect về trang truyện) — lỗi tạm, giữ hàng đợi thử lại, đừng đánh failed."""


@dataclass
class NovelMeta:
    source_novel_id: str
    source_url: str
    title_zh: str
    author_zh: str | None = None
    cover_url: str | None = None
    description_zh: str | None = None
    genres_zh: list[str] = field(default_factory=list)
    status: str = "ongoing"          # ongoing | completed | hiatus
    chapter_count: int = 0
    last_chapter_at: datetime | None = None


@dataclass
class ChapterRef:
    index: int                       # 1-based
    source_chapter_id: str
    title_zh: str | None = None


class SourceAdapter(ABC):
    """Mỗi nguồn (shuhaige/…) implement class này.

    Dựng động từ 1 dòng bảng `sources`: template quyết định class, base_url +
    config (jsonb) quyết định URL/selector. Session curl_cffi (impersonate
    chrome + proxy) dùng chung ở đây, adapter con chỉ lo parse HTML.
    """

    name: str  # = sources.name, gán lúc __init__ từ source_row

    # Trạng thái truyện parse "ké" từ HTML mục lục ở lần fetch_chapter_list gần nhất
    # (None = nguồn không lộ trạng thái trên trang đó). sync_chapter_list đọc để flip
    # ongoing↔completed mà không tốn thêm fetch nào.
    last_toc_status: str | None = None

    def __init__(
        self,
        base_url: str,
        config: dict[str, Any] | None = None,
        source_row: dict[str, Any] | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.config = config or {}
        self.source_row = source_row or {}
        self.name = self.source_row.get("name") or getattr(self, "name", "")
        self.encoding = self.config.get("encoding", "utf-8")
        # Đếm fetch của chu kỳ hiện tại → main.py đo sức khoẻ nguồn (toàn fail = chết).
        self.fetch_ok = 0
        self.fetch_err = 0
        proxy = (settings.http_proxy_url or "").strip()
        proxies = {"http": proxy, "https": proxy} if proxy.startswith(
            ("http://", "https://", "socks5://")) else None
        self._session = cffi_requests.Session(impersonate="chrome", proxies=proxies, timeout=20)

    def reset_health_counters(self) -> None:
        self.fetch_ok = self.fetch_err = 0

    def fetch_bytes(self, url: str) -> tuple[bytes, str]:
        """Tải nhị phân (bìa…) qua session impersonate → (data, content_type). KHÔNG
        đụng bộ đếm sức khoẻ: bìa thường khác domain nguồn, fail không = nguồn chết."""
        r = self._session.get(url)
        r.raise_for_status()
        return r.content, (r.headers.get("content-type") or "")

    def _get(self, path: str) -> str:
        """GET path tương đối (hoặc URL tuyệt đối) → text đã decode theo encoding nguồn.

        Nguồn TQ hay chập chờn (curl 28 timeout, connection closed abruptly) —
        thử lại 3 lần với backoff trước khi bỏ cuộc, đỡ đánh failed oan chương."""
        url = path if path.startswith("http") else f"{self.base_url}/{path.lstrip('/')}"
        last: Exception | None = None
        for attempt in range(3):
            if attempt:
                time.sleep(2 * attempt)  # 2s, 4s
            status = None
            try:
                r = self._session.get(url)
                status = getattr(r, "status_code", None)
                if status in {400, 401, 403, 404, 410}:
                    r.raise_for_status()
                r.raise_for_status()
                self.fetch_ok += 1
                return r.content.decode(self.encoding, "ignore")
            except Exception as e:
                last = e
                status = getattr(getattr(e, "response", None), "status_code", None) or status
                if status in {400, 401, 403, 404, 410}:
                    break
        self.fetch_err += 1
        raise last  # type: ignore[misc]

    def search(self, keyword: str) -> list[tuple[str, str]]:
        """Tìm truyện theo tên trên nguồn → [(source_novel_id, title_zh)].
        Mặc định []: nguồn không có search dùng được (ddxs render kết quả bằng JS)."""
        return []

    @abstractmethod
    def fetch_latest(self, limit: int = 30) -> list[NovelMeta]:
        """Danh sách truyện mới đăng / mới cập nhật (metadata tiếng Trung)."""

    @abstractmethod
    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        """Metadata đầy đủ của 1 truyện."""

    @abstractmethod
    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        """Toàn bộ mục lục."""

    @abstractmethod
    def fetch_chapter(self, source_chapter_id: str) -> str:
        """Nội dung tiếng Trung của 1 chương (plain text)."""
