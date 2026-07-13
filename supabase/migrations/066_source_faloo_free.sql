-- Faloo mobile: metadata + mục lục đầy đủ, nhưng chỉ crawl chương KHÔNG có marker VIP.
-- Probe thật 2026-07-13: catalog /booklist/{id}.html, nội dung free .nodeContent;
-- chương VIP có <span class="v_0">V</span> và chỉ trả placeholder nên bị loại từ mục lục.
insert into sources (name, base_url, template, meta_priority, enabled, config)
values (
  'faloo',
  'https://wap.faloo.com',
  'faloo',
  30,
  true,
  '{"encoding": "gb18030", "latest_path": "/category_2_1.html"}'::jsonb
)
on conflict (name) do update set
  base_url = excluded.base_url,
  template = excluded.template,
  meta_priority = excluded.meta_priority,
  enabled = true,
  config = excluded.config;

-- Hiện tự động trong Quản trị → Crawl; worker đọc lại mỗi chu kỳ discovery.
-- Điều kiện là "lớn hơn", nên giá trị 500 chỉ nhận truyện từ 501 chương free.
insert into worker_settings (key, value, note)
values (
  'faloo_free_chapter_threshold',
  '500',
  'Faloo: chỉ crawl khi số chương miễn phí lớn hơn ngưỡng này'
)
on conflict (key) do nothing;
