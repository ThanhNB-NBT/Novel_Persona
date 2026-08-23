-- Hàng đợi lệnh quản lí VPS từ app: admin chèn lệnh → worker trên host tương ứng
-- nhận thực thi (qua Docker API, socket đã mount). Chỉ các lệnh trong whitelist
-- của worker có hiệu lực; mọi giá trị khác bị đánh lỗi và bỏ qua.
create table if not exists host_commands (
  id bigint generated always as identity primary key,
  host text not null,               -- khớp host_metrics.host (machine-id ổn định)
  command text not null,            -- restart | restart_crawler | restart_translator
  status text not null default 'pending', -- pending | running | done | error
  output text,
  created_by uuid,                  -- admin ra lệnh (null = worker nội bộ)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_host_commands_pending on host_commands (host, created_at)
  where status = 'pending';

alter table host_commands enable row level security;
create policy admin_all_host_commands on host_commands for all to authenticated
  using (is_admin()) with check (is_admin());

-- Ghi chú vận hành: lệnh RESTART khiến worker tự chết đi sống lại nên nó tự đánh
-- dấu 'done' TRƯỚC khi thực thi (best-effort — restart là thao tác đáng tin).
