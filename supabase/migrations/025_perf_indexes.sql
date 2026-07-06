-- Index cho các query nóng đang quét tuần tự:
-- 1. chapters lọc done + translated_at: feed "Mới dịch" (app), count_chapters_translated_today
--    (cầu chì ngày, chạy mỗi 60s), audit watermark (translated_at >= since).
create index if not exists idx_chapters_done_translated_at
  on chapters (translated_at desc) where translation_status = 'done';

-- 2. Khám phá mục "Nổi bật" order by chapter_count_translated desc.
create index if not exists idx_novels_featured
  on novels (chapter_count_translated desc);
