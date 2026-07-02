"""Entry point.

Chạy 2 tiến trình (2 terminal hoặc 2 service riêng):
    python -m novelworker.main crawl        # crawler: discovery + sync + tải chương
    python -m novelworker.main translate    # translator: consumer hàng đợi dịch
"""
from __future__ import annotations

import argparse
import logging
import time

from . import db
from .config import settings
from .crawler.fanqie import FanqieAdapter
from .crawler import sync
from .translator import worker as translator_worker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("main")

ADAPTERS = [FanqieAdapter()]  # thêm QidianAdapter(), JjwxcAdapter() ở P3


def _novels_needing_fetch() -> list[int]:
    """Novel có chương queued nhưng chưa tải content_zh."""
    rows = (
        db.sb().table("chapters").select("novel_id")
        .eq("translation_status", "queued").is_("content_zh", "null")
        .limit(200).execute()
    ).data or []
    return list({r["novel_id"] for r in rows})


def run_crawler() -> None:
    log.info("Crawler bắt đầu, chu kỳ discovery %d phút", settings.crawl_interval_min)
    last_discovery = 0.0
    while True:
        now = time.time()
        for adapter in ADAPTERS:
            try:
                # 1) discovery + sync truyện được theo dõi — theo chu kỳ dài
                if now - last_discovery > settings.crawl_interval_min * 60:
                    sync.discover_latest(adapter, limit=30)
                    sync.sync_followed_novels(adapter)
                # 2) tải nội dung chương đang chờ dịch — chạy sát (vòng ngắn)
                for novel_id in _novels_needing_fetch():
                    # đảm bảo mục lục đã có (lần đầu user bấm Đọc, chapters có thể chưa đầy đủ)
                    nv = (
                        db.sb().table("novels").select("source_novel_id, source_id")
                        .eq("id", novel_id).single().execute()
                    ).data
                    src_name = (
                        db.sb().table("sources").select("name").eq("id", nv["source_id"]).single().execute()
                    ).data["name"]
                    if src_name != adapter.name:
                        continue
                    sync.sync_chapter_list(adapter, novel_id, nv["source_novel_id"])
                    sync.ensure_chapters_fetched(adapter, novel_id)
            except Exception:
                log.exception("Lỗi vòng crawl (%s)", adapter.name)
        if now - last_discovery > settings.crawl_interval_min * 60:
            last_discovery = now
        time.sleep(10)


def main() -> None:
    parser = argparse.ArgumentParser(prog="novelworker")
    parser.add_argument("mode", choices=["crawl", "translate"])
    args = parser.parse_args()
    if args.mode == "crawl":
        run_crawler()
    else:
        translator_worker.run_forever()


if __name__ == "__main__":
    main()
