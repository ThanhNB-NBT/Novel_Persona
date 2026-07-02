"""Interface chung cho mọi nguồn crawl."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class NovelMeta:
    source_novel_id: str
    source_url: str
    title_zh: str
    author_zh: str | None = None
    cover_url: str | None = None
    description_zh: str | None = None
    genres_zh: list[str] = field(default_factory=list)
    tags_zh: list[str] = field(default_factory=list)
    status: str = "ongoing"          # ongoing | completed | hiatus
    chapter_count: int = 0
    rating: float | None = None
    rating_count: int | None = None
    word_count: int | None = None
    last_chapter_at: datetime | None = None


@dataclass
class ChapterRef:
    index: int                       # 1-based
    source_chapter_id: str
    title_zh: str | None = None


@dataclass
class CommentItem:
    source_comment_id: str
    username: str | None
    content_zh: str
    likes: int = 0
    posted_at: datetime | None = None


class SourceAdapter(ABC):
    """Mỗi nguồn (fanqie/qidian/jjwxc) implement class này."""

    name: str  # phải khớp sources.name trong DB

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

    @abstractmethod
    def fetch_comments(self, source_novel_id: str, limit: int = 30) -> list[CommentItem]:
        """Bình luận nổi bật của truyện."""
