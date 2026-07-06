-- Nhịp tim worker: crawler/translator upsert mốc thời gian định kỳ → tab Worker
-- hiện chấm sống/chết thật thay vì đoán qua trạng thái job.
create table worker_heartbeat (
  name text primary key,          -- 'crawler' | 'translator'
  at timestamptz not null default now(),
  note text                       -- việc đang làm (tuỳ chọn)
);
alter table worker_heartbeat enable row level security;
create policy admin_read_heartbeat on worker_heartbeat for select to authenticated
  using (is_admin());
-- worker ghi bằng service_role (bypass RLS)
