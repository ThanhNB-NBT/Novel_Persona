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
        base_path = self.config.get("latest_path", "/category_2_1.html")
        # CHỈ bắt link tiêu đề trong khối truyện (show_title2) — trang category còn vô số
        # href /{id}.html footer/nav (id ngắn) không phải truyện, trước đây bị vơ nhầm
        # thành ứng viên → 185/200 lỗi "thiếu metadata".
        pattern = re.compile(
            r'class=["\']show_title2["\'][^>]*>\s*<a[^>]+href=["\']'
            r'(?:(?:https?:)?//wap\.faloo\.com)?/(?:new_)?(\d+)\.html["\'][^>]*>(.*?)</a>',
            re.I | re.S,
        )
        out: list[NovelMeta] = []
        seen: set[str] = set()
        for page in range(1, 51):
            path = base_path if page == 1 else re.sub(
                r"\d+(?=\.html$)", str(page), base_path)
            if page > 1 and path == base_path:
                break
            try:
                html = self._get(path)
            except Exception:
                if page == 1:
                    raise
                break
            fresh = 0
            for match in pattern.finditer(html):
                book_id = match.group(1)
                title = _text(match.group(2))
                if book_id in seen or not title:
                    continue
                seen.add(book_id)
                fresh += 1
                out.append(NovelMeta(
                    source_novel_id=book_id,
                    source_url=f"{self.base_url}{self._novel_path(book_id)}",
                    title_zh=title,
                ))
                if len(out) >= limit:
                    break
            if len(out) >= limit:
                break
            if not fresh:
                break
        return out

    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        html = self._get(self._novel_path(source_novel_id))
        title_match = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.I | re.S)
        if not title_match:
            # WAP đôi lúc trả trang chống bot HTTP 200 cho IP VPS. Domain desktop
            # vẫn công khai cùng dữ liệu nên chỉ dùng làm fallback khi thiếu h1.
            html = self._get(f"https://b.faloo.com/{source_novel_id}.html")
            title_match = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.I | re.S)
        if not title_match:
            raise ValueError(f"Faloo WAP và desktop đều thiếu metadata {source_novel_id}")

        def meta_value(name: str) -> str | None:
            match = re.search(
                rf'<meta[^>]+(?:name|property)=["\']{re.escape(name)}["\'][^>]+'
                r'content=["\'](.*?)["\']', html, re.I | re.S)
            return unescape(match.group(1)).strip() if match else None

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
            description = meta_value("description")

        cover_match = re.search(
            r'class=["\'][^"\']*book_info[^"\']*["\'].*?<img[^>]+src=["\']([^"\']+)',
            html, re.I | re.S)
        cover = cover_match.group(1) if cover_match else None
        cover = cover or meta_value("og:image")
        if cover and cover.startswith("//"):
            cover = f"https:{cover}"
        elif cover and cover.startswith("http://"):
            cover = f"https://{cover.removeprefix('http://')}"

        # Faloo có cả chương VIP nên con số "đã viết" trên trang truyện không phải
        # số chương project có thể đọc. chapter_count của adapter này luôn là số
        # chương free thật lấy từ catalog; discovery dùng nó để lọc trước khi upsert.
        free_count = len(self.fetch_chapter_list(source_novel_id))
        genres = [value for value in (labeled("大类"), labeled("小类")) if value]
        if not genres and (category := meta_value("og:novel:category")):
            genres = [category]
        return NovelMeta(
            source_novel_id=source_novel_id,
            source_url=f"{self.base_url}{self._novel_path(source_novel_id)}",
            title_zh=_text(title_match.group(1)),
            author_zh=labeled("作者") or meta_value("og:novel:author"),
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
