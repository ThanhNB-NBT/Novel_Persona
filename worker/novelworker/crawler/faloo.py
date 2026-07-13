"""Adapter Faloo mobile: chỉ lấy metadata và các chương đọc miễn phí."""
from __future__ import annotations

import re
from html import unescape

from .base import ChapterRef, NovelMeta, SourceAdapter


def _text(fragment: str) -> str:
    fragment = re.sub(r"<script\b.*?</script>|<style\b.*?</style>", "", fragment,
                      flags=re.I | re.S)
    fragment = re.sub(r"</p\s*>|<br\s*/?>", "\n", fragment, flags=re.I)
    return unescape(re.sub(r"<[^>]+>", "", fragment)).strip()


class FalooAdapter(SourceAdapter):
    def _novel_path(self, book_id: str) -> str:
        return f"/new_{book_id}.html"

    def _catalog_paths(self, book_id: str) -> tuple[str, str]:
        return f"/booklist/{book_id}.html", f"/booklist_{book_id}.html"

    def _chapter_path(self, book_id: str, chapter_id: str) -> str:
        return f"/{book_id}_{chapter_id}.html"

    def fetch_latest(self, limit: int = 30) -> list[NovelMeta]:
        html = self._get(self.config.get("latest_path", "/category_2_1.html"))
        pattern = re.compile(
            r'<a[^>]+href=["\'](?:(?:https?:)?//wap\.faloo\.com)?/(?:new_)?(\d+)\.html["\'][^>]*>(.*?)</a>',
            re.I | re.S,
        )
        out: list[NovelMeta] = []
        seen: set[str] = set()
        for match in pattern.finditer(html):
            book_id = match.group(1)
            title = _text(match.group(2))
            if book_id in seen or not title:
                continue
            seen.add(book_id)
            out.append(NovelMeta(
                source_novel_id=book_id,
                source_url=f"{self.base_url}{self._novel_path(book_id)}",
                title_zh=title,
            ))
            if len(out) >= limit:
                break
        return out

    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        html = self._get(self._novel_path(source_novel_id))
        title_match = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.I | re.S)
        if not title_match:
            raise ValueError(f"Không parse được truyện Faloo {source_novel_id}")

        def labeled(label: str) -> str | None:
            match = re.search(
                rf"<h2[^>]*>\s*{label}\s*</h2>\s*[：:]?\s*<a[^>]*>(.*?)</a>",
                html, re.I | re.S)
            return _text(match.group(1)) if match else None

        description = None
        desc_match = re.search(r"id=[\"']info2[\"'][^>]*>(.*?)</div>", html, re.I | re.S)
        if desc_match:
            description = _text(desc_match.group(1)) or None
        if not description:
            desc_match = re.search(r'<meta[^>]+name=["\']description["\'][^>]+content=["\'](.*?)["\']',
                                   html, re.I | re.S)
            description = unescape(desc_match.group(1)).strip() if desc_match else None

        cover_match = re.search(
            r'class=["\'][^"\']*book_info[^"\']*["\'].*?<img[^>]+src=["\']([^"\']+)',
            html, re.I | re.S)
        cover = cover_match.group(1) if cover_match else None
        if cover and cover.startswith("//"):
            cover = f"https:{cover}"

        # Faloo có cả chương VIP nên con số "đã viết" trên trang truyện không phải
        # số chương project có thể đọc. chapter_count của adapter này luôn là số
        # chương free thật lấy từ catalog; discovery dùng nó để lọc trước khi upsert.
        free_count = len(self.fetch_chapter_list(source_novel_id))
        genres = [value for value in (labeled("大类"), labeled("小类")) if value]
        return NovelMeta(
            source_novel_id=source_novel_id,
            source_url=f"{self.base_url}{self._novel_path(source_novel_id)}",
            title_zh=_text(title_match.group(1)),
            author_zh=labeled("作者"),
            cover_url=cover,
            description_zh=description,
            genres_zh=genres,
            status="completed" if re.search(r"状态[：:]\s*(?:完成|完结)", html) else "ongoing",
            chapter_count=free_count,
        )

    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        html = ""
        for path in self._catalog_paths(source_novel_id):
            try:
                html = self._get(path)
            except Exception:
                continue
            if re.search(rf"/{re.escape(source_novel_id)}_\d+\.html", html):
                break

        pattern = re.compile(
            rf'<li[^>]*>\s*<a[^>]+href=["\'][^"\']*/{re.escape(source_novel_id)}_(\d+)\.html["\'][^>]*>(.*?)</a>\s*</li>',
            re.I | re.S,
        )
        free: list[tuple[str, str]] = []
        seen: set[str] = set()
        for match in pattern.finditer(html):
            chapter_id, inner = match.group(1), match.group(2)
            if chapter_id in seen or re.search(r'class=["\'][^"\']*\bv_0\b', inner, re.I):
                continue
            title = _text(inner)
            if title:
                seen.add(chapter_id)
                free.append((chapter_id, title))
        if not free:
            raise ValueError(f"Faloo không có chương miễn phí cho {source_novel_id}")
        return [
            ChapterRef(index=index, source_chapter_id=f"{source_novel_id}/{chapter_id}", title_zh=title)
            for index, (chapter_id, title) in enumerate(free, 1)
        ]

    def fetch_chapter(self, source_chapter_id: str) -> str:
        book_id, _, chapter_id = source_chapter_id.rpartition("/")
        html = self._get(self._chapter_path(book_id, chapter_id))
        match = re.search(
            r'class=["\'][^"\']*\bnodeContent\b[^"\']*["\'][^>]*>(.*?)'
            r'<div[^>]*class=["\'][^"\']*\bnodeEnd\b',
            html, re.I | re.S)
        text = _text(match.group(1)) if match else ""
        lines = [line.strip() for line in text.splitlines()]
        lines = [line for line in lines if line and not line.startswith(
            ("飞卢小说网提醒", "飞卢小说，飞要你好看", "手机用户请浏览"))]
        text = "\n".join(lines).strip()
        if len(text) < 50:
            raise ValueError(f"Chương Faloo {source_chapter_id} không công khai hoặc là VIP")
        return text
