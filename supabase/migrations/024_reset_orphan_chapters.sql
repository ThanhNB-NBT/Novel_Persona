-- Dọn chương mồ côi bằng 1 câu SQL thay vì worker kéo 2 bảng về so trong Python
-- (bản Python không phân trang → jobs active > 1000 dòng là reset OAN chương có job thật).
create or replace function reset_orphan_chapters()
returns int
language sql
security definer
as $$
  with fixed as (
    update chapters c
    set translation_status = 'none'
    where c.translation_status in ('queued', 'translating')
      and not exists (
        select 1 from translation_jobs j
        where j.chapter_id = c.id and j.status in ('pending', 'running')
      )
    returning c.id
  )
  select count(*)::int from fixed;
$$;
