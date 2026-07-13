-- Nguồn đã tắt + chương không còn content_zh thì không thể dịch. Không để job pending
-- bị UI hiểu nhầm là "đang crawl" mãi mãi.

create or replace function fail_unfetchable_jobs_for_source(p_source_id smallint)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with blocked as (
    select j.id, j.chapter_id
    from translation_jobs j
    join chapters c on c.id = j.chapter_id
    join novels n on n.id = c.novel_id
    where j.type = 'chapter'
      and j.status = 'pending'
      and c.content_zh is null
      and n.source_id = p_source_id
  ), failed_jobs as (
    update translation_jobs j
    set status = 'failed',
        error = 'crawl: nguồn truyện đã tắt hoặc không còn khả dụng',
        locked_by = null,
        locked_at = null
    where j.id in (select id from blocked)
    returning j.chapter_id
  ), failed_chapters as (
    update chapters c
    set translation_status = 'failed'
    where c.id in (select chapter_id from failed_jobs)
    returning c.id
  )
  select count(*) into v_count from failed_jobs;
  return v_count;
end;
$$;


create or replace function fail_jobs_when_source_disabled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.enabled and not new.enabled then
    perform fail_unfetchable_jobs_for_source(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_fail_jobs_when_source_disabled on sources;
create trigger trg_fail_jobs_when_source_disabled
after update of enabled on sources
for each row execute function fail_jobs_when_source_disabled();


-- Chặn mọi đường tạo/retry job (app, admin lẫn worker) nếu nguồn đã tắt và DB
-- không còn bản gốc. Các RPC bên dưới vẫn lọc trước để trả số lượng chính xác.
create or replace function guard_unfetchable_translation_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_content boolean;
  v_source_enabled boolean;
begin
  if new.type = 'chapter' and new.status = 'pending' and new.chapter_id is not null then
    select c.content_zh is not null, s.enabled
      into v_has_content, v_source_enabled
    from chapters c
    join novels n on n.id = c.novel_id
    join sources s on s.id = n.source_id
    where c.id = new.chapter_id;

    if not coalesce(v_has_content, false) and not coalesce(v_source_enabled, false) then
      new.status := 'failed';
      new.error := 'crawl: nguồn truyện đã tắt hoặc không còn khả dụng';
      new.locked_by := null;
      new.locked_at := null;
      update chapters set translation_status = 'failed' where id = new.chapter_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_unfetchable_translation_job on translation_jobs;
create trigger trg_guard_unfetchable_translation_job
before insert or update of status on translation_jobs
for each row execute function guard_unfetchable_translation_job();


create or replace function request_translation(
  p_novel_id bigint, p_up_to int default 10, p_priority int default 50)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
  v_cap int;
  v_source_enabled boolean;
  v_up_to int := greatest(1, least(coalesce(p_up_to, 10), 10000));
  v_priority int := case when p_priority <= 10 then 5 else 50 end;
  r record;
begin
  if auth.uid() is null then raise exception 'login required'; end if;

  select coalesce(nullif(n.chapter_count_source, 0), v_up_to), s.enabled
    into v_cap, v_source_enabled
  from novels n join sources s on s.id = n.source_id
  where n.id = p_novel_id;
  if not found then raise exception 'novel not found'; end if;

  insert into chapters (novel_id, chapter_index)
  select p_novel_id, gs
  from generate_series(1, least(v_up_to, coalesce(v_cap, 0))) gs
  on conflict (novel_id, chapter_index) do nothing;

  for r in
    select c.id from chapters c
    where c.novel_id = p_novel_id
      and c.chapter_index <= v_up_to
      and c.translation_status in ('none', 'failed')
      and (c.content_zh is not null or v_source_enabled)
    order by c.chapter_index
  loop
    update chapters set translation_status = 'queued' where id = r.id;
    delete from translation_jobs
      where chapter_id = r.id and status in ('failed', 'done');
    insert into translation_jobs (type, novel_id, chapter_id, priority)
    values ('chapter', p_novel_id, r.id, v_priority)
    on conflict do nothing;
    v_count := v_count + 1;
  end loop;

  if v_count = 0 and not v_source_enabled then
    raise exception 'nguồn truyện hiện không khả dụng và không còn bản gốc để dịch';
  end if;
  return v_count;
end;
$$;


create or replace function retranslate_chapter(p_novel_id bigint, p_index int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chapter_id bigint;
  v_can_fetch boolean;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select c.id, (c.content_zh is not null or s.enabled)
    into v_chapter_id, v_can_fetch
  from chapters c
  join novels n on n.id = c.novel_id
  join sources s on s.id = n.source_id
  where c.novel_id = p_novel_id and c.chapter_index = p_index;
  if v_chapter_id is null then raise exception 'chapter not found'; end if;
  if not v_can_fetch then
    raise exception 'nguồn truyện hiện không khả dụng và chương không còn bản gốc';
  end if;

  update chapters set translation_status = 'queued' where id = v_chapter_id;
  delete from translation_jobs
    where chapter_id = v_chapter_id and status in ('failed', 'done');
  insert into translation_jobs (type, novel_id, chapter_id, priority)
  values ('chapter', p_novel_id, v_chapter_id, 30)
  on conflict do nothing;
end;
$$;


create or replace function retranslate_all(p_novel_id bigint)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
  v_source_enabled boolean;
  r record;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select s.enabled into v_source_enabled
  from novels n join sources s on s.id = n.source_id
  where n.id = p_novel_id;
  if not found then raise exception 'novel not found'; end if;

  for r in
    select id from chapters
    where novel_id = p_novel_id
      and translation_status in ('done', 'failed')
      and (content_zh is not null or v_source_enabled)
    order by chapter_index
  loop
    delete from translation_jobs
      where chapter_id = r.id and status in ('failed', 'done');
    update chapters set translation_status = 'queued' where id = r.id;
    insert into translation_jobs (type, novel_id, chapter_id, priority)
    values ('chapter', p_novel_id, r.id, 45)
    on conflict do nothing;
    v_count := v_count + 1;
  end loop;

  if v_count = 0 and not v_source_enabled then
    raise exception 'nguồn truyện hiện không khả dụng và không còn bản gốc để dịch lại';
  end if;
  return v_count;
end;
$$;


create or replace function admin_retry_job(p_job_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unfetchable boolean;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select j.type = 'chapter' and c.content_zh is null and not s.enabled
    into v_unfetchable
  from translation_jobs j
  left join chapters c on c.id = j.chapter_id
  left join novels n on n.id = c.novel_id
  left join sources s on s.id = n.source_id
  where j.id = p_job_id;
  if not found then raise exception 'job not found'; end if;
  if coalesce(v_unfetchable, false) then
    raise exception 'không thể chạy lại: nguồn truyện đang tắt và chương không còn bản gốc';
  end if;

  update translation_jobs
  set status = 'pending', attempts = 0, error = null,
      locked_by = null, locked_at = null
  where id = p_job_id;
  update chapters c
  set translation_status = 'queued'
  from translation_jobs j
  where j.id = p_job_id and j.chapter_id = c.id
    and c.translation_status = 'failed';
end;
$$;


create or replace function admin_retry_all_failed()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update translation_jobs j
  set status = 'pending', attempts = 0, error = null,
      locked_by = null, locked_at = null
  where j.status = 'failed'
    and (
      j.type <> 'chapter'
      or exists (
        select 1 from chapters c
        join novels n on n.id = c.novel_id
        join sources s on s.id = n.source_id
        where c.id = j.chapter_id
          and (c.content_zh is not null or s.enabled)
      )
    );
  get diagnostics v_count = row_count;
  update chapters c
  set translation_status = 'queued'
  where c.translation_status = 'failed'
    and exists (
      select 1 from translation_jobs j
      where j.chapter_id = c.id and j.status in ('pending', 'running')
    );
  return v_count;
end;
$$;


-- Dọn nợ hiện tại (xsbique và mọi nguồn đã tắt khác).
do $$
declare r record;
begin
  for r in select id from sources where not enabled loop
    perform fail_unfetchable_jobs_for_source(r.id);
  end loop;
end;
$$;

revoke execute on function fail_unfetchable_jobs_for_source(smallint)
  from public, anon, authenticated;
revoke execute on function fail_jobs_when_source_disabled()
  from public, anon, authenticated;
revoke execute on function guard_unfetchable_translation_job()
  from public, anon, authenticated;
