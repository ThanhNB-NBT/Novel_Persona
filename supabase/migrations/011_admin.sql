-- Quản trị trong app: cờ admin + chặn tự cấp quyền + RLS cho màn Quản trị.
-- Góp ý bản dịch vẫn auto-duyệt (approved mặc định true); admin chỉ soi khi có BÁO CÁO.

-- ---------- Cờ admin ----------
alter table profiles add column if not exists is_admin boolean not null default false;
alter table novels   add column if not exists hidden   boolean not null default false;

-- Chặn client tự bật is_admin cho chính mình (own_profile cho sửa cả hàng của mình).
-- Chỉ SQL console (auth.uid() null) hoặc service_role mới đổi được cờ.
create or replace function guard_is_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.is_admin is distinct from old.is_admin
     and auth.uid() is not null
     and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    new.is_admin := old.is_admin; -- nuốt thay đổi trái phép
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_is_admin on profiles;
create trigger trg_guard_is_admin before update on profiles
  for each row execute function guard_is_admin();

-- User hiện tại có phải admin. security definer → đọc profiles bỏ qua RLS (không đệ quy policy).
create or replace function is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;

-- ---------- RLS admin ----------
-- Admin toàn quyền trên hàng đợi / truyện / chương / glossary (đọc vốn đã mở cho mọi người).
create policy admin_all_jobs on translation_jobs for all to authenticated
  using (is_admin()) with check (is_admin());
create policy admin_write_novels on novels for all to authenticated
  using (is_admin()) with check (is_admin());
create policy admin_write_chapters on chapters for all to authenticated
  using (is_admin()) with check (is_admin());
create policy admin_all_glossary on glossary_terms for all to authenticated
  using (is_admin()) with check (is_admin());

-- ---------- Báo cáo term dịch sai ----------
create table glossary_reports (
  id bigint generated always as identity primary key,
  term_id bigint references glossary_terms(id) on delete cascade,
  novel_id bigint references novels(id) on delete set null,
  reason text,
  reported_by uuid references auth.users(id) on delete set null,
  resolved boolean not null default false,
  created_at timestamptz not null default now()
);
create index idx_reports_open on glossary_reports (created_at desc) where not resolved;
alter table glossary_reports enable row level security;
create policy insert_report on glossary_reports for insert to authenticated
  with check (reported_by = auth.uid());
create policy admin_reports on glossary_reports for all to authenticated
  using (is_admin()) with check (is_admin());

-- ---------- RPC cho màn quản trị ----------
-- Thống kê token theo model (soi chi phí LLM). Gộp ở DB cho nhẹ client.
create or replace function admin_token_usage() returns table (
  model_used text, chapters bigint, prompt_tokens bigint, completion_tokens bigint
) language plpgsql security definer stable set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  return query
    select c.model_used, count(*)::bigint,
           coalesce(sum(c.prompt_tokens), 0)::bigint,
           coalesce(sum(c.completion_tokens), 0)::bigint
    from chapters c
    where c.model_used is not null
    group by c.model_used
    order by 4 desc;
end $$;

-- Cho 1 job lỗi chạy lại (reset về pending).
create or replace function admin_retry_job(p_job_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update translation_jobs
     set status = 'pending', attempts = 0, error = null,
         locked_by = null, locked_at = null
   where id = p_job_id;
end $$;
