-- Sức khỏe model dịch: latency + ok/fail mỗi model → tab Token (admin) hiện sống/chậm/chết.
create table if not exists model_health (
  model text primary key,
  ok_count int not null default 0,
  fail_count int not null default 0,
  total_latency_ms bigint not null default 0,  -- tổng latency các lần OK → chia ok_count = TB
  last_ok_at timestamptz,
  last_error text,
  last_error_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table model_health enable row level security;
-- worker ghi bằng service_role (bypass RLS); app chỉ admin đọc.
create policy admin_read_model_health on model_health for select to authenticated
  using (is_admin());

-- Tăng atomic (nhiều luồng dịch song song không mất update). Gọi từ worker (service_role).
create or replace function bump_model_health(
  p_model text, p_latency_ms int, p_ok boolean, p_error text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into model_health (model, ok_count, fail_count, total_latency_ms,
                            last_ok_at, last_error, last_error_at)
  values (p_model,
          case when p_ok then 1 else 0 end,
          case when p_ok then 0 else 1 end,
          case when p_ok then p_latency_ms else 0 end,
          case when p_ok then now() else null end,
          case when p_ok then null else p_error end,
          case when p_ok then null else now() end)
  on conflict (model) do update set
    ok_count         = model_health.ok_count + case when p_ok then 1 else 0 end,
    fail_count       = model_health.fail_count + case when p_ok then 0 else 1 end,
    total_latency_ms = model_health.total_latency_ms + case when p_ok then p_latency_ms else 0 end,
    last_ok_at       = case when p_ok then now() else model_health.last_ok_at end,
    last_error       = case when p_ok then model_health.last_error else p_error end,
    last_error_at    = case when p_ok then model_health.last_error_at else now() end,
    updated_at       = now();
end $$;
