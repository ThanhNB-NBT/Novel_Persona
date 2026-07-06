-- Chống job failed/done chồng chất cho 1 chương.
-- Unique index chỉ chặn job trùng đang (pending,running); job 'failed'/'done' KHÔNG bị chặn
-- → mỗi lần request/retranslate 1 chương đã từng fail lại tạo thêm 1 dòng failed
-- (màn Quản trị thấy "mỗi lỗi 1 dòng" cho cùng 1 chương). Trước khi tạo job mới, XOÁ job
-- cũ (failed/done) của chương → tối đa 1 job/chương.

create or replace function request_translation(
  p_novel_id bigint, p_up_to int default 10, p_priority int default 50)
returns int
language plpgsql
security definer
as $$
declare
  v_count int := 0;
  r record;
begin
  if auth.uid() is null then
    raise exception 'login required';
  end if;

  for r in
    select c.id from chapters c
    where c.novel_id = p_novel_id
      and c.chapter_index <= p_up_to
      and c.translation_status in ('none', 'failed')
    order by c.chapter_index
  loop
    update chapters set translation_status = 'queued' where id = r.id;
    delete from translation_jobs
      where chapter_id = r.id and status in ('failed', 'done');  -- dọn job cũ, tránh chồng
    insert into translation_jobs (type, novel_id, chapter_id, priority)
    values ('chapter', p_novel_id, r.id, p_priority)
    on conflict do nothing;
    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;

create or replace function retranslate_chapter(p_novel_id bigint, p_index int)
returns void
language plpgsql
security definer
as $$
declare
  v_chapter_id bigint;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select id into v_chapter_id from chapters
  where novel_id = p_novel_id and chapter_index = p_index;
  if v_chapter_id is null then raise exception 'chapter not found'; end if;

  update chapters set translation_status = 'queued' where id = v_chapter_id;
  delete from translation_jobs
    where chapter_id = v_chapter_id and status in ('failed', 'done');  -- dọn job cũ
  insert into translation_jobs (type, novel_id, chapter_id, priority)
  values ('chapter', p_novel_id, v_chapter_id, 30)
  on conflict do nothing;
end $$;
