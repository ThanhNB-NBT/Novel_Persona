-- Dọn knob "crawl_prefetch_content" thêm nhầm: yêu cầu thật là kế hoạch crawl
-- KHÔNG bị chặn bởi dịch (đã bỏ các gate reader_fetch_waiting trong code) —
-- không phải prefetch toàn bộ nội dung truyện.
delete from worker_settings where key = 'crawl_prefetch_content';
