-- Config crawler chỉnh được từ app (tab Quản trị → Crawl) — worker đọc lại mỗi
-- chu kỳ discovery, không cần restart. Key lạ worker bỏ qua.
create table if not exists worker_settings (
  key text primary key,
  value text not null,
  note text, -- chú thích hiện trong app
  updated_at timestamptz not null default now()
);

insert into worker_settings (key, value, note) values
  ('crawl_interval_min', '45', 'Chu kỳ discovery + refresh (phút)'),
  ('discover_new_per_cycle', '10', 'Số truyện MỚI thêm tối đa mỗi chu kỳ / nguồn'),
  ('refresh_per_cycle', '60', 'Số truyện cũ soi chương mới mỗi chu kỳ / nguồn')
on conflict (key) do nothing;

alter table worker_settings enable row level security;
create policy admin_all_worker_settings on worker_settings for all to authenticated
  using (is_admin()) with check (is_admin());

-- Admin bật/tắt nguồn crawl ngay trong app (đọc vốn đã mở qua read_sources).
create policy admin_write_sources on sources for all to authenticated
  using (is_admin()) with check (is_admin());
