-- Chế độ "crawl cho xong luôn rồi dịch dần": sau khi sync mục lục, worker tự tải
-- nội dung TOÀN BỘ chương (không chờ ai bấm đọc) theo lô nhỏ mỗi tick. Dịch vẫn
-- theo hàng đợi ưu tiên như cũ. 0 = tắt, chỉ tải khi người đọc bấm.
insert into worker_settings (key, value, note) values
  ('crawl_prefetch_content', '1', 'Tự tải nội dung toàn bộ chương sau khi có mục lục (0 = chỉ tải khi có người đọc)')
on conflict (key) do nothing;
