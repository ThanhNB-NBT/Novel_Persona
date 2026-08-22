-- FIX [HIGH] Từ 2026-07-08 bản gốc của chương dịch xong được dời sang R2 rồi NULL cột
-- content_zh (backfill_zh_to_r2.py). Nhưng cụm hàm ở migration 065 vẫn đo "còn bản gốc"
-- bằng `content_zh is not null`, nên với truyện có nguồn ĐÃ TẮT, mọi chương done bị coi
-- như mất gốc:
--   · trigger guard hạ luôn chapters.translation_status = 'failed' — chương đang đọc được
--     biến thành hỏng chỉ vì có ai đó bấm dịch lại (đã xảy ra thật: nv2163 ch377);
--   · dịch lại / retry bị chặn dù worker lấy bản gốc từ R2 hoàn toàn được.
-- Chương đã có content_vi thì chắc chắn từng dịch xong ⇒ bản gốc đang nằm trên R2 (backfill
-- chỉ NULL cột SAU khi put R2 thành công). Dùng đúng dấu hiệu đó làm điều kiện.

create or replace function chapter_fetchable(p_chapter_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    (select c.content_zh is not null   -- bản gốc còn trong DB
         or c.content_vi is not null   -- đã dịch xong ⇒ bản gốc đang ở R2
         or s.enabled                  -- nguồn còn sống ⇒ tải lại được
     from chapters c
     join novels n on n.id = c.novel_id
     join sources s on s.id = n.source_id
     where c.id = p_chapter_id),
    false)
$fn$;

create or replace function guard_unfetchable_translation_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if new.type = 'chapter' and new.status = 'pending' and new.chapter_id is not null
     and not chapter_fetchable(new.chapter_id) then
    new.status := 'failed';
    new.error := 'crawl: nguồn truyện đã tắt hoặc không còn khả dụng';
    new.locked_by := null;
    new.locked_at := null;
    -- KHÔNG đụng chương đã dịch xong: job hỏng không phải lý do xoá bản dịch đang đọc
    update chapters set translation_status = 'failed'
     where id = new.chapter_id and translation_status <> 'done';
  end if;
  return new;
end;
$fn$;

create or replace function fail_unfetchable_jobs_for_source(p_source_id smallint)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
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
      and n.source_id = p_source_id
      and not chapter_fetchable(c.id)
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
      and c.translation_status <> 'done'
    returning c.id
  )
  select count(*) into v_count from failed_jobs;
  return v_count;
end;
$fn$;

create or replace function request_translation(
  p_novel_id bigint, p_up_to int default 10, p_priority int default 50)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
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
      and chapter_fetchable(c.id)
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
$fn$;

create or replace function retranslate_chapter(p_novel_id bigint, p_index int)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_chapter_id bigint;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select c.id into v_chapter_id
  from chapters c
  where c.novel_id = p_novel_id and c.chapter_index = p_index;
  if v_chapter_id is null then raise exception 'chapter not found'; end if;
  if not chapter_fetchable(v_chapter_id) then
    raise exception 'nguồn truyện hiện không khả dụng và chương không còn bản gốc';
  end if;

  update chapters set translation_status = 'queued' where id = v_chapter_id;
  delete from translation_jobs
    where chapter_id = v_chapter_id and status in ('failed', 'done');
  insert into translation_jobs (type, novel_id, chapter_id, priority)
  values ('chapter', p_novel_id, v_chapter_id, 30)
  on conflict do nothing;
end;
$fn$;

create or replace function retranslate_all(p_novel_id bigint)
returns int
language plpgsql
security definer
set search_path = public
as $fn$
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
      and chapter_fetchable(id)
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
$fn$;

create or replace function admin_retry_job(p_job_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_chapter_id bigint;
  v_type text;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select j.type, j.chapter_id into v_type, v_chapter_id
  from translation_jobs j where j.id = p_job_id;
  if not found then raise exception 'job not found'; end if;
  if v_type = 'chapter' and v_chapter_id is not null
     and not chapter_fetchable(v_chapter_id) then
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
$fn$;

create or replace function admin_retry_all_failed()
returns int
language plpgsql
security definer
set search_path = public
as $fn$
declare v_count int;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update translation_jobs j
  set status = 'pending', attempts = 0, error = null,
      locked_by = null, locked_at = null
  where j.status = 'failed'
    and (j.type <> 'chapter' or chapter_fetchable(j.chapter_id));
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
$fn$;

-- Trả lại chương bị hạ oan: còn bản dịch mà đang mang trạng thái 'failed'.
update chapters set translation_status = 'done'
 where translation_status = 'failed' and content_vi is not null;
