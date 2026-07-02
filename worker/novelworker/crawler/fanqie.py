"""Adapter Fanqie (fanqienovel.com).

LƯU Ý QUAN TRỌNG — cần kiểm chứng lại khi chạy thật:
- Fanqie đổi endpoint/chống bot thường xuyên. Các endpoint dưới đây là loại
  phổ biến được các tool bên thứ 3 dùng (2024-2025), có thể phải cập nhật.
- Nội dung chương trả về có thể bị "mã hóa font" (một số chữ Hán bị tráo
  bằng private-use codepoint). Nếu gặp, cần bảng map giải mã —
  xem hook `decode_obfuscated()` bên dưới.
- Nếu bị 403: điền FANQIE_COOKIE trong .env (lấy từ trình duyệt) và/hoặc
  HTTP_PROXY_URL.
"""
from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timezone

from curl_cffi import requests as cffi_requests

from ..config import settings
from .base import ChapterRef, CommentItem, NovelMeta, SourceAdapter

log = logging.getLogger(__name__)

BASE = "https://fanqienovel.com"


class FanqieAdapter(SourceAdapter):
    name = "fanqie"

    def __init__(self) -> None:
        self._session = cffi_requests.Session(
            impersonate="chrome",  # giả TLS fingerprint Chrome
            proxies={"http": settings.http_proxy_url, "https": settings.http_proxy_url}
            if settings.http_proxy_url else None,
            timeout=20,
        )
        if settings.fanqie_cookie:
            self._session.headers["Cookie"] = settings.fanqie_cookie
        self._session.headers["Referer"] = BASE

    # ---------- helpers ----------

    def _get(self, url: str, **kw):
        r = self._session.get(url, **kw)
        r.raise_for_status()
        return r

    @staticmethod
    def _initial_state(html: str) -> dict:
        """Fanqie nhúng dữ liệu trong window.__INITIAL_STATE__ = {...};"""
        m = re.search(r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\});?\s*</script>", html, re.S)
        if not m:
            raise ValueError("Không tìm thấy __INITIAL_STATE__ — Fanqie có thể đã đổi cấu trúc trang")
        return json.loads(m.group(1))

    @staticmethod
    def decode_obfuscated(text: str) -> str:
        """Hook giải mã font-obfuscation của Fanqie.

        TODO: nếu content chứa ký tự vùng private-use (U+E000–U+F8FF),
        cần nạp bảng map (charset của font Fanqie) để thay ngược về chữ Hán
        chuẩn. Tạm thời trả nguyên văn + cảnh báo.
        """
        if any(0xE000 <= ord(c) <= 0xF8FF for c in text[:2000]):
            log.warning("Chương chứa ký tự bị mã hóa font — cần bổ sung bảng giải mã!")
        return text

    # ---------- SourceAdapter ----------

    def fetch_latest(self, limit: int = 30) -> list[NovelMeta]:
        # Trang bảng xếp hạng "mới" — TODO xác nhận URL thực tế khi chạy
        r = self._get(f"{BASE}/api/author/library/book_list/v0/", params={
            "page_count": limit, "page_index": 0, "gender": -1,
            "category_id": -1, "creation_status": -1, "word_count": -1, "sort": 1,  # sort=1: mới nhất
        })
        data = r.json()
        books = (data.get("data") or {}).get("book_list") or []
        out: list[NovelMeta] = []
        for b in books[:limit]:
            out.append(NovelMeta(
                source_novel_id=str(b.get("book_id")),
                source_url=f"{BASE}/page/{b.get('book_id')}",
                title_zh=b.get("book_name", ""),
                author_zh=b.get("author"),
                cover_url=b.get("thumb_url"),
                description_zh=b.get("abstract"),
                genres_zh=[c for c in (b.get("category") or "").split(",") if c],
                status="completed" if str(b.get("creation_status")) == "0" else "ongoing",
                chapter_count=int(b.get("serial_count") or 0),
                rating=float(b["score"]) if b.get("score") else None,
                word_count=int(b.get("word_number") or 0) or None,
                last_chapter_at=datetime.fromtimestamp(int(b["last_publish_time"]), tz=timezone.utc)
                if b.get("last_publish_time") else None,
            ))
        return out

    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        r = self._get(f"{BASE}/page/{source_novel_id}")
        state = self._initial_state(r.text)
        info = (state.get("page") or {}).get("bookInfo") or {}
        return NovelMeta(
            source_novel_id=source_novel_id,
            source_url=f"{BASE}/page/{source_novel_id}",
            title_zh=info.get("bookName", ""),
            author_zh=info.get("authorName"),
            cover_url=info.get("thumbUri"),
            description_zh=info.get("abstract"),
            genres_zh=[c for c in (info.get("category") or "").split(",") if c],
            status="completed" if str(info.get("creationStatus")) == "0" else "ongoing",
            chapter_count=int(info.get("serialCount") or 0),
            rating=float(info["score"]) if info.get("score") else None,
            word_count=int(info.get("wordNumber") or 0) or None,
        )

    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        r = self._get(f"{BASE}/api/reader/directory/detail", params={"bookId": source_novel_id})
        data = r.json().get("data") or {}
        item_ids: list[str] = data.get("allItemIds") or []
        # chapterListWithVolume chứa cả tiêu đề nếu có
        titles: dict[str, str] = {}
        for vol in data.get("chapterListWithVolume") or []:
            for ch in vol:
                titles[str(ch.get("itemId"))] = ch.get("title", "")
        return [
            ChapterRef(index=i + 1, source_chapter_id=str(cid), title_zh=titles.get(str(cid)))
            for i, cid in enumerate(item_ids)
        ]

    def fetch_chapter(self, source_chapter_id: str) -> str:
        r = self._get(f"{BASE}/api/reader/full", params={"itemId": source_chapter_id})
        data = r.json().get("data") or {}
        chapter = (data.get("chapterData") or {})
        raw = chapter.get("content") or ""
        # content là HTML: bóc <p>
        text = re.sub(r"</p>\s*<p[^>]*>", "\n", raw)
        text = re.sub(r"<[^>]+>", "", text).strip()
        if not text:
            raise ValueError(f"Chương {source_chapter_id} rỗng — có thể cần cookie/VIP hoặc endpoint đã đổi")
        return self.decode_obfuscated(text)

    def fetch_comments(self, source_novel_id: str, limit: int = 30) -> list[CommentItem]:
        # TODO: endpoint bình luận Fanqie nằm ở API app (cần thêm reverse-engineering).
        # Tạm thời trả rỗng để pipeline không vỡ; bổ sung ở P2.
        log.info("fetch_comments(fanqie) chưa triển khai — trả rỗng")
        return []
