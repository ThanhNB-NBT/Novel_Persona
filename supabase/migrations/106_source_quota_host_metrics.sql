-- Quota discovery THEO TỪNG nguồn + bảng số liệu máy chủ cho màn "Theo dõi VPS".

-- Số truyện MỚI tối đa mỗi chu kỳ discovery của riêng nguồn này.
-- NULL = dùng giá trị chung worker_settings.discover_new_per_cycle.
-- Admin chỉnh ngay trong app (tab Crawl → Nguồn), worker tự nhận ở chu kỳ kế.
alter table sources add column if not exists discover_quota int;

-- Số liệu máy chủ chạy worker (crawler đẩy mỗi phút; best-effort, lỗi bỏ qua).
-- App admin đọc để xem CPU/RAM/disk — đổi VPS chỉ cần worker mới đẩy dòng host mới,
-- không phải sửa gì trong app (label/address là nhãn hiển thị, chỉnh được từ app).
create table if not exists host_metrics (
  host text primary key,            -- hostname của máy chạy worker
  label text not null default '',   -- nhãn hiển thị (chỉnh từ app)
  address text not null default '', -- IP/địa chỉ hiển thị (chỉnh từ app)
  cpu_count int,
  load1 numeric,
  cpu_pct numeric,                  -- % CPU trung bình giữa 2 lần đẩy
  mem_used_mb int,
  mem_total_mb int,
  disk_used_gb int,
  disk_total_gb int,
  uptime_h numeric,
  updated_at timestamptz not null default now()
);

alter table host_metrics enable row level security;
create policy admin_all_host_metrics on host_metrics for all to authenticated
  using (is_admin()) with check (is_admin());

-- Nhãn/địa chỉ hiển thị của host (key vps_label_<host>, vps_address_<host>) nằm trong
-- worker_settings sẵn có — không cần cột riêng, app upsert như các knob khác.
