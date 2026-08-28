-- Vá lệch schema: production đã trôi khỏi repo, dựng lại từ migration sẽ thiếu 3 thứ dưới
-- (đo bằng cách áp 108 migration vào DB nháp rồi so với bản restore từ dump 2026-08-27).
-- Không có chúng thì bản khôi phục thiếu cột novels.engine → worker chọn engine dịch sẽ vỡ.

alter table novels add column if not exists engine text not null default 'hachimi';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'novels_engine_check') then
    alter table novels add constraint novels_engine_check
      check (engine = any (array['hachimi'::text, 'mistral'::text]));
  end if;
end $$;

-- Bật RLS tự động cho bảng mới tạo trong public — khỏi quên, tránh phơi dữ liệu.
-- Event trigger gọi hàm này KHÔNG nằm trong dump (pg_dump --schema=public bỏ qua event
-- trigger), nên phải tự tạo lại sau khi khôi phục.
create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  cmd record;
begin
  for cmd in
    select *
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table', 'partitioned table')
  loop
    if cmd.schema_name = 'public' then
      begin
        execute format('alter table if exists %s enable row level security', cmd.object_identity);
        raise log 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      exception
        when others then
          raise log 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      end;
    else
      raise log 'rls_auto_enable: skip %', cmd.object_identity;
    end if;
  end loop;
end;
$function$;
