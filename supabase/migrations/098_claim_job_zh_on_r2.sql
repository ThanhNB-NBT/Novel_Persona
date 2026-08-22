-- FIX [HIGH] claim_next_job (089) đòi `c.content_zh is not null`, nhưng bản gốc của chương
-- đã dịch xong được dời sang R2 rồi NULL cột từ 2026-07-08. Hệ quả: job dịch LẠI một chương
-- done chỉ chạy được khi crawler tình cờ tải lại bản gốc — truyện có nguồn đã tắt thì job nằm
-- pending vĩnh viễn, mà chương lại đang mang trạng thái 'queued' nên người đọc thấy "đang
-- dịch…" mãi mãi (đo thật: nv1223 ch21, job #49596 nằm im dù hàng đợi trống).
-- Worker tự lấy bản gốc từ R2 (blob.get_zh) và ném MissingContentError nếu R2 cũng không có,
-- nên chương từng dịch xong (content_vi not null) là đủ điều kiện nhận job.

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
      or (
        exists (
          select 1 from novels n
          where n.id = j.novel_id
            and n.meta_translated
        )
        and exists (
          select 1
          from chapters c
          where c.id = j.chapter_id
            -- bản gốc: còn trong DB, HOẶC chương đã dịch xong ⇒ gốc đang nằm trên R2
            and (c.content_zh is not null or c.content_vi is not null)
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
