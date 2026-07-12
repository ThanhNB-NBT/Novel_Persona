import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.sync import _chapter_sync_fields


def main() -> None:
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


if __name__ == "__main__":
    main()
    print("OK — crawl sync self-check pass")
