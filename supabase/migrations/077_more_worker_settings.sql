-- Gom mọi knob chỉnh được lúc chạy vào worker_settings (tab Quản trị → Crawl):
-- thêm trần dịch/ngày + chu kỳ audit (translator) và 3 knob crawler còn thiếu.
-- Worker đọc lại định kỳ, đổi trong app là ăn, không cần restart.
insert into worker_settings (key, value, note) values
  ('max_chapters_per_day', '1000', 'DỊCH · Trần số chương dịch mỗi ngày (chạm là nghỉ tới 00:00 UTC)'),
  ('audit_interval_min', '120', 'DỊCH · Chu kỳ tự quét chương dịch hỏng (phút)'),
  ('discover_min_chapters', '200', 'CRAWL · Truyện đang ra dưới ngưỡng chương này thì bỏ qua khi discovery'),
  ('sample_chapters', '1', 'CRAWL · Số chương dịch sẵn "đọc thử" khi nhận truyện mới (0 = tắt)'),
  ('crawl_fetch_batch', '20', 'CRAWL · Số chương tải nguồn tối đa cho một truyện mỗi tick')
on conflict (key) do nothing;
