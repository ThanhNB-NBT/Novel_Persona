"""Đồng bộ nguồn → DB: discovery truyện mới + cập nhật mục lục truyện đang theo dõi."""
from __future__ import annotations

import logging
import time

from .. import db
from .base import SourceAdapter

log = logging.getLogger(__name__)


def _source_id(adapter: SourceAdapter) -> int:
    rows = db.sb().table("sources").select("id").eq("name", adapter.name).execute().data
    if not rows:
        raise RuntimeError(f"Nguồn '{adapter.name}' chưa có trong bảng sources")
    return rows[0]["id"]


def discover_latest(adapter: SourceAdapter, limit: int = 30) -> None:
    """Quét truyện mới cập nhật → upsert novels → enqueue dịch metadata."""
    sid = _source_id(adapter)
    for meta in adapter.fetch_latest(limit=limit):
        novel = db.upsert_novel({
            "source_id": sid,
            "source_novel_id": meta.source_novel_id,
            "source_url": meta.source_url,
            "title_zh": meta.title_zh,
            "author_zh": meta.author_zh,
            "cover_url": meta.cover_url,
            "description_zh": meta.description_zh,
            "genres": meta.genres_zh,      # tạm giữ tiếng Trung, job metadata sẽ dịch
            "tags": meta.tags_zh,
            "status": meta.status,
            "chapter_count_source": meta.chapter_count,
            "rating_source": meta.rating,
            "rating_count": meta.rating_count,
            "word_count": meta.word_count,
            "last_chapter_at": meta.last_chapter_at.isoformat() if meta.last_chapter_at else None,
            "updated_at": "now()",
        })
        if not novel.get("meta_translated"):
            # truyện mới → dịch metadata ưu tiên cao để hiện lên tab "Mới đăng"
            db.enqueue("metadata", novel["id"], priority=10)
        time.sleep(1.0)  # lịch sự với nguồn


def sync_chapter_list(adapter: SourceAdapter, novel_id: int, source_novel_id: str) -> int:
    """Cập nhật mục lục 1 truyện; trả về số chương mới phát hiện."""
    refs = adapter.fetch_chapter_list(source_novel_id)
    existing = (
        db.sb().table("chapters").select("chapter_index").eq("novel_id", novel_id).execute()
    ).data
    have = {r["chapter_index"] for r in existing}
    new_count = 0
    for ref in refs:
        if ref.index not in have:
            db.upsert_chapter_stub(novel_id, ref.index, ref.source_chapter_id, ref.title_zh)
            new_count += 1
    if refs:
        db.sb().table("novels").update(
            {"chapter_count_source": len(refs), "updated_at": "now()"}
        ).eq("id", novel_id).execute()
    return new_count


def sync_followed_novels(adapter: SourceAdapter) -> None:
    """Với truyện có trong ít nhất 1 tủ sách: kiểm tra chương mới."""
    sid = _source_id(adapter)
    followed = db.sb().rpc if False else None  # noqa — giữ chỗ, dùng query thẳng bên dưới
    rows = (
        db.sb().table("library").select("novel_id, novels!inner(id, source_id, source_novel_id)")
        .eq("novels.source_id", sid)
        .execute()
    ).data or []
    seen: set[int] = set()
    for row in rows:
        nv = row["novels"]
        if nv["id"] in seen:
            continue
        seen.add(nv["id"])
        try:
            n = sync_chapter_list(adapter, nv["id"], nv["source_novel_id"])
            if n:
                log.info("Truyện %s có %d chương mới", nv["id"], n)
        except Exception:
            log.exception("Lỗi sync truyện %s", nv["id"])
        time.sleep(2.0)


def ensure_chapters_fetched(adapter: SourceAdapter, novel_id: int) -> None:
    """Tải content_zh cho các chương đã queued dịch mà chưa có nội dung gốc."""
    rows = (
        db.sb().table("chapters")
        .select("id, source_chapter_id, chapter_index")
        .eq("novel_id", novel_id)
        .eq("translation_status", "queued")
        .is_("content_zh", "null")
        .order("chapter_index")
        .execute()
    ).data or []
    for ch in rows:
        if not ch["source_chapter_id"]:
            continue
        try:
            content = adapter.fetch_chapter(ch["source_chapter_id"])
            db.save_chapter_raw(ch["id"], content)
            log.info("Đã tải chương %s (novel %s)", ch["chapter_index"], novel_id)
        except Exception:
            log.exception("Lỗi tải chương %s", ch["id"])
        time.sleep(1.5)
