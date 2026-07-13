-- Song song theo TRUYỆN, không theo chương: mỗi novel chỉ có tối đa một job running
-- để chương sau luôn đọc được glossary/summary/bản dịch mới nhất của chương trước.
create or replace function claim_next_job(worker_id text)
returns setof translation_jobs
language sql
security definer
as $$
  with candidate as (
    select j.id, j.novel_id
    from translation_jobs j
    where j.status = 'pending'
      and (
        j.novel_id is null
        or not exists (
          select 1
          from translation_jobs running
          where running.status = 'running'
            and running.novel_id = j.novel_id
        )
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
    for update skip locked
  ), locked as (
    -- Chỉ lock đúng novel đã chọn. Nếu worker khác vừa chọn cùng novel, lượt này
    -- trả rỗng và vòng worker claim lại ngay, không nhận chồng chương.
    select id
    from candidate
    where novel_id is null or pg_try_advisory_xact_lock(62062, novel_id::integer)
  )
  update translation_jobs
  set status = 'running', locked_by = worker_id, locked_at = now(),
      started_at = coalesce(started_at, now()), attempts = attempts + 1
  where id = (select id from locked)
  returning *;
$$;
