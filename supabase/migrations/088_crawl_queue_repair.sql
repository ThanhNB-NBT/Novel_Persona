-- Vá migration 086 đã push: job_type là enum nên phải ép sang text trước khi so text[].
create or replace function claim_next_job(worker_id text, p_types text[] default null)
returns setof translation_jobs
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate translation_jobs%rowtype;
  got_novel_lock boolean;
begin
  select j.* into candidate
  from translation_jobs j
  where j.status = 'pending'
    and (p_types is null or j.type::text = any(p_types))
    and not exists (
      select 1
      from translation_jobs running
      where running.status = 'running'
        and running.novel_id = j.novel_id
    )
    and (
      j.type <> 'chapter'
      or exists (
        select 1
        from chapters c
        where c.id = j.chapter_id
          and c.content_zh is not null
          and (
            c.content_vi is not null
            or not exists (
              select 1
              from chapters p
              where p.novel_id = c.novel_id
                and p.chapter_index = c.chapter_index - 1
                and p.translation_status in ('queued', 'translating')
            )
          )
      )
    )
  order by j.priority, j.created_at
  limit 1
  for update skip locked;

  if not found then
    return;
  end if;

  select pg_try_advisory_xact_lock(62063, candidate.novel_id::integer)
    into got_novel_lock;
  if not got_novel_lock then
    return;
  end if;

  if exists (
    select 1 from translation_jobs running
    where running.status = 'running'
      and running.novel_id = candidate.novel_id
  ) then
    return;
  end if;

  return query
  update translation_jobs j
  set status = 'running', locked_by = worker_id, locked_at = now(),
      started_at = coalesce(j.started_at, now()), attempts = j.attempts + 1
  where j.id = candidate.id and j.status = 'pending'
  returning j.*;
end;
$$;

revoke execute on function claim_next_job(text, text[])
  from public, anon, authenticated;

-- Dọn chiều ngược của reset_orphan_chapters: job chapter pending nhưng chapter không
-- còn ở hàng đợi. Số pending từng bị phình 592 dù crawler/translator đều không thể nhận.
create or replace function cleanup_orphan_translation_jobs()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n_deleted int;
begin
  delete from translation_jobs j
  using chapters c
  where j.chapter_id = c.id
    and j.type = 'chapter'
    and j.status = 'pending'
    and c.translation_status not in ('queued', 'translating');
  get diagnostics n_deleted = row_count;
  return n_deleted;
end;
$$;

revoke execute on function cleanup_orphan_translation_jobs()
  from public, anon, authenticated;

-- Dọn nợ hiện có ngay lúc migration được áp dụng.
select cleanup_orphan_translation_jobs();
