"""Adapter Faloo mobile: chỉ lấy metadata và các chương đọc miễn phí."""
from __future__ import annotations

import re
from html import unescape
from itertools import zip_longest

from .base import ChapterRef, NovelMeta, SourceAdapter


# Nhóm lớn đúng bộ lọc chung: 玄幻奇幻, 武侠仙侠, 科幻网游, 恐怖灵异.
_DEFAULT_DISCOVER_PATHS = tuple(f"/category_{i}_1.html" for i in (1, 6, 2, 5))


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

    def _fetch_listing(
        self, paths: list[str] | tuple[str, ...], limit: int, status: str = "ongoing",
        page: int | None = None,
    ) -> list[NovelMeta]:
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
        active = set(paths)
        start_page = page or 1
        stop_page = start_page + 1 if page else 51
        for current_page in range(start_page, stop_page):
            if not active or len(out) >= limit:
                break
            batches: list[list[NovelMeta]] = []
            for base_path in paths:
                if base_path not in active:
                    continue
                path = base_path if current_page == 1 else re.sub(
                    r"\d+(?=\.html$)", str(current_page), base_path)
                if current_page > 1 and path == base_path:
                    active.discard(base_path)
                    continue
                try:
                    html = self._get(path)
                except Exception:
                    active.discard(base_path)
                    continue
                matches = list(pattern.finditer(html))
                if not matches:
                    active.discard(base_path)
                    continue
                batch: list[NovelMeta] = []
                for match in matches:
                    book_id = match.group(1)
                    title = _text(match.group(2))
                    if book_id in seen or not title:
                        continue
                    seen.add(book_id)
                    batch.append(NovelMeta(
                        source_novel_id=book_id,
                        source_url=f"{self.base_url}{self._novel_path(book_id)}",
                        title_zh=title,
                        status=status,
                    ))
                batches.append(batch)
            for group in zip_longest(*batches):
                out.extend(item for item in group if item is not None)
                if len(out) >= limit:
                    return out[:limit]
        return out[:limit]

    def fetch_latest(self, limit: int = 30, page: int | None = None) -> list[NovelMeta]:
        paths = self.config.get("discover_paths")
        if not paths:
            # Config production cũ chỉ có path mặc định category 2; mở rộng nó sang
            # toàn bộ nhóm được phép. Path custom khác vẫn giữ nguyên để tương thích clone.
            legacy = self.config.get("latest_path")
            paths = ([legacy] if legacy and legacy != "/category_2_1.html"
                     else _DEFAULT_DISCOVER_PATHS)
        return self._fetch_listing(paths, limit, page=page)

    def fetch_completed(self, limit: int = 30, page: int | None = None) -> list[NovelMeta]:
        paths = self.config.get("completed_paths") or ["/finish_0_0_0_1.html"]
        return self._fetch_listing(paths, limit, status="completed", page=page)

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
