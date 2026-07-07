-- Dịch TUẦN TỰ trong một truyện, song song giữa các truyện.
-- Trước đây claim_next_job chỉ xếp theo priority/created_at → 2 luồng worker lấy 2 chương
-- LIỀN KỀ của cùng truyện dịch cùng lúc: chương sau không có summary/đuôi chương trước,
-- tên riêng chưa vào glossary → mất liền mạch + phiên âm đổi qua lại giữa các chương.
-- Fix: job chapter chỉ được claim khi chương liền trước cùng truyện KHÔNG còn đang
-- queued/translating (done/failed/none/không tồn tại đều cho qua → không starvation
-- khi user dịch nhảy cóc từ giữa truyện; chương queued mồ côi đã có reset_orphan_chapters dọn).
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
            and not exists (
              select 1 from chapters p
              where p.novel_id = c.novel_id
                and p.chapter_index = c.chapter_index - 1
                and p.translation_status in ('queued', 'translating')
            )
        )
      )
    order by priority, created_at
    limit 1
    for update skip locked
  )
  returning *;
$$;
