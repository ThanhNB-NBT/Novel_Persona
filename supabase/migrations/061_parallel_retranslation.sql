-- Chương dịch mới vẫn tuần tự để nhận glossary/ngữ cảnh chương trước.
-- Chương dịch lại đã giữ content_vi cũ làm ngữ cảnh, nên cho phép các worker xử lý song song.
create or replace function claim_next_job(worker_id text)
returns setof translation_jobs
language sql
security definer
as $$
  update translation_jobs
  set status = 'running', locked_by = worker_id, locked_at = now(),
      started_at = coalesce(started_at, now()), attempts = attempts + 1
  where id = (
    select j.id
    from translation_jobs j
    where j.status = 'pending'
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
    for update skip locked
  )
  returning *;
$$;
