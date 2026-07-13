import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler import sync
from novelworker.crawler.base import NovelMeta
from novelworker.crawler.sync import _chapter_sync_fields
from novelworker.main import _ordered_novel_ids


def main() -> None:
    # Crawler phải tải theo priority/created_at của job, không theo thứ tự row chapters.
    jobs = [
        {"novel_id": 20, "chapter_id": 2},
        {"novel_id": 10, "chapter_id": 1},
        {"novel_id": 20, "chapter_id": 3},
        {"novel_id": 30, "chapter_id": 4},
    ]
    assert _ordered_novel_ids(jobs, {1, 2, 3}) == [20, 10]

    fields = _chapter_sync_fields(
        old_count=10, old_status="ongoing", source_status="completed",
        total=11, full_toc=False, now="now",
    )
    assert fields == {
        "status": "completed",
        "chapter_count_source": 11,
        "last_chapter_at": "now",
        "updated_at": "now",
    }
    assert _chapter_sync_fields(10, "ongoing", "ongoing", 10, False, "now") == {}
    assert _chapter_sync_fields(10, "ongoing", None, 10, True, "now") == {
        "toc_synced_at": "now",
    }

    # Quota discovery chỉ được tính khi truyện thực sự qua lọc và đã xếp việc.
    original_sync = sync.sync_chapter_list
    original_enqueue = sync.db.enqueue
    original_sample = sync.queue_sample_chapters
    original_min = sync.settings.discover_min_chapters
    queued = []
    sync.sync_chapter_list = lambda *args, **kwargs: (20, 0)
    sync.db.enqueue = lambda *args, **kwargs: queued.append(args)
    sync.queue_sample_chapters = lambda *args, **kwargs: queued.append(args)
    sync.settings.discover_min_chapters = 10
    try:
        meta = NovelMeta(source_novel_id="1", source_url="u", title_zh="Đạt",
                         status="ongoing")
        assert sync._queue_canonical_work(
            object(), {"id": 1, "is_canonical": True, "meta_translated": False},
            meta, 10) is True
        assert sync._queue_canonical_work(
            object(), {"id": 2, "is_canonical": False, "meta_translated": False},
            meta, 10) is False
        assert len(queued) == 2
    finally:
        sync.sync_chapter_list = original_sync
        sync.db.enqueue = original_enqueue
        sync.queue_sample_chapters = original_sample
        sync.settings.discover_min_chapters = original_min


if __name__ == "__main__":
    main()
    print("OK — crawl sync self-check pass")
