-- Đồng bộ claim_next_job với bản trong 001 (DB đang chạy bản cũ không có filter content_zh
-- → job chapter chưa crawl bị claim/defer xoay vòng vô hạn)
create or replace function claim_next_job(worker_id text)
returns setof translation_jobs
language sql
security definer
as $$
  update translation_jobs
  set status = 'running', locked_by = worker_id, locked_at = now(),
      started_at = coalesce(started_at, now()), attempts = attempts + 1
  where id = (
    select id from translation_jobs
    where status = 'pending'
      and (
        type <> 'chapter'
        or exists (
          select 1 from chapters c
          where c.id = translation_jobs.chapter_id
            and c.content_zh is not null
        )
      )
    order by priority, created_at
    limit 1
    for update skip locked
  )
  returning *;
$$;
