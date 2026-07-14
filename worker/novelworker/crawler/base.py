"""Interface chung cho mọi nguồn crawl."""
from __future__ import annotations

import random
import threading
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from curl_cffi import requests as cffi_requests

from ..config import settings

# (connect, read): host TQ chết hay treo connect → fail nhanh 8s thay vì 20s cứng,
# đỡ đóng băng crawler 1 luồng; read rộng hơn cho trang mục lục 4000 chương tải chậm.
_TIMEOUT = (8, 25)

# P2b-0: đo latency fetch thật để quyết có nên song song trong-1-nguồn (P2b) + đặt interval.
# Gom theo nguồn, ghi 1 dòng vào bảng crawl_latency mỗi _STATS_EVERY fetch (đọc từ Supabase,
# KHÔNG lẫn vào log crawl). Tự chứa, gỡ dễ khi đã có số.
_STATS_EVERY = 200
_stats_lock = threading.Lock()
_fetch_stats: dict[str, dict] = {}


def _record_fetch(source: str, dt: float | None, *, timeout: bool = False,
                  http429: bool = False) -> None:
    with _stats_lock:
        s = _fetch_stats.setdefault(source, {"lat": [], "n": 0, "to": 0, "r429": 0})
        s["n"] += 1
        if dt is not None:
            s["lat"].append(dt)
        s["to"] += timeout
        s["r429"] += http429
        if s["n"] < _STATS_EVERY:
            return
        _fetch_stats[source] = {"lat": [], "n": 0, "to": 0, "r429": 0}
    lat = sorted(s["lat"])
    p50 = lat[len(lat) // 2] if lat else 0.0
    p95 = lat[min(len(lat) - 1, int(len(lat) * 0.95))] if lat else 0.0
    from .. import db  # lazy: tránh vòng import lúc nạp adapter
    db.record_crawl_latency(source, s["n"], len(lat), p50, p95,
                            lat[-1] if lat else 0.0, s["to"], s["r429"])


def _retry_after_seconds(resp: Any) -> float:
    """Header Retry-After (429/503) dạng GIÂY → float; bỏ qua dạng HTTP-date (hiếm ở
    nguồn này). Nguồn bảo chờ mà mình chờ đúng → ít bị nâng mức chặn."""
    if resp is None:
        return 0.0
    try:
        val = resp.headers.get("Retry-After") or resp.headers.get("retry-after")
        return max(0.0, float(val)) if val else 0.0
    except (TypeError, ValueError, AttributeError):
        return 0.0


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
        # timeout đặt PER-REQUEST (_TIMEOUT tuple) thay vì cứng ở Session để tách connect/read
        self._session = cffi_requests.Session(impersonate="chrome", proxies=proxies)

    def reset_health_counters(self) -> None:
        self.fetch_ok = self.fetch_err = 0

    def fetch_bytes(self, url: str) -> tuple[bytes, str]:
        """Tải nhị phân (bìa…) qua session impersonate → (data, content_type). KHÔNG
        đụng bộ đếm sức khoẻ: bìa thường khác domain nguồn, fail không = nguồn chết."""
        r = self._session.get(url, timeout=_TIMEOUT)
        r.raise_for_status()
        return r.content, (r.headers.get("content-type") or "")

    def _get(self, path: str) -> str:
        """GET path tương đối (hoặc URL tuyệt đối) → text đã decode theo encoding nguồn.

        Nguồn TQ hay chập chờn (curl 28 timeout, connection closed abruptly) —
        thử lại 3 lần với backoff trước khi bỏ cuộc, đỡ đánh failed oan chương."""
        url = path if path.startswith("http") else f"{self.base_url}/{path.lstrip('/')}"
        last: Exception | None = None
        retry_after = 0.0
        for attempt in range(3):
            if attempt:
                # Nguồn báo Retry-After (429/503) thì chờ đúng (trần 30s để 1 host chậm
                # không đóng băng crawler 1 luồng); còn lại backoff + jitter tránh retry
                # đồng loạt cùng nhịp.
                time.sleep(min(retry_after, 30.0) or (2 * attempt + random.random()))
            status = None
            t0 = time.monotonic()
            try:
                r = self._session.get(url, timeout=_TIMEOUT)
                status = getattr(r, "status_code", None)
                r.raise_for_status()
                self.fetch_ok += 1
                _record_fetch(self.name, time.monotonic() - t0)  # P2b-0: đo request OK
                return r.content.decode(self.encoding, "ignore")
            except Exception as e:
                last = e
                resp = getattr(e, "response", None)
                status = getattr(resp, "status_code", None) or status
                _record_fetch(self.name, None,
                              timeout="timeout" in type(e).__name__.lower(),
                              http429=status == 429)
                if status in {400, 401, 403, 404, 410}:
                    break  # lỗi cứng (URL sai / bị cấm) — retry vô ích
                retry_after = _retry_after_seconds(resp)  # 429/503: nguồn báo chờ bao lâu
        self.fetch_err += 1
        raise last  # type: ignore[misc]

    def search(self, keyword: str) -> list[tuple[str, str]]:
        """Tìm truyện theo tên trên nguồn → [(source_novel_id, title_zh)].
        Mặc định []: nguồn không có search dùng được (ddxs render kết quả bằng JS)."""
        return []

    @abstractmethod
    def fetch_latest(
        self, limit: int = 30, page: int | None = None,
    ) -> list[NovelMeta]:
        """Danh sách mới; `page` dùng bởi frontier, None giữ chế độ quét tương thích cũ."""

    @abstractmethod
    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        """Metadata đầy đủ của 1 truyện."""

    @abstractmethod
    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        """Toàn bộ mục lục."""

    @abstractmethod
    def fetch_chapter(self, source_chapter_id: str) -> str:
        """Nội dung tiếng Trung của 1 chương (plain text)."""
