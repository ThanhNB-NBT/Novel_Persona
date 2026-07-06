-- Ưu tiên dịch theo người đang đọc: request_translation nhận priority (đọc = cực cao),
-- và admin xem được reading_progress của mọi user (tab "Đang đọc").

-- Thêm tham số p_priority (mặc định 50 giữ tương thích). App bấm đọc truyền 5 (cực cao).
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
    insert into translation_jobs (type, novel_id, chapter_id, priority)
    values ('chapter', p_novel_id, r.id, p_priority)
    on conflict do nothing;
    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;

-- Admin đọc được tiến độ đọc của MỌI user (own_progress chỉ cho xem của mình).
create policy admin_read_progress on reading_progress for select to authenticated
  using (is_admin());
