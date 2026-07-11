-- App cá nhân: chỉ kẹp input vô lý để bug/client lỗi không tạo hàng đợi khổng lồ.
-- Vẫn cho truyện rất dài và giữ hai mức ưu tiên app đang dùng (đọc=5, thường=50).
create or replace function request_translation(
  p_novel_id bigint, p_up_to int default 10, p_priority int default 50)
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_count int := 0;
  v_cap int;
  v_up_to int := greatest(1, least(coalesce(p_up_to, 10), 10000));
  v_priority int := case when p_priority <= 10 then 5 else 50 end;
  r record;
begin
  if auth.uid() is null then
    raise exception 'login required';
  end if;

  select coalesce(nullif(chapter_count_source, 0), v_up_to) into v_cap
  from novels where id = p_novel_id;

  insert into chapters (novel_id, chapter_index)
  select p_novel_id, gs
  from generate_series(1, least(v_up_to, coalesce(v_cap, 0))) gs
  on conflict (novel_id, chapter_index) do nothing;

  for r in
    select c.id from chapters c
    where c.novel_id = p_novel_id
      and c.chapter_index <= v_up_to
      and c.translation_status in ('none', 'failed')
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

  return v_count;
end $$;
