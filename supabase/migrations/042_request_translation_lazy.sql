-- FIX nút dịch báo "0 chương" trên truyện mục lục lười (033): stub chương đã bị
-- xoá nên request_translation cũ (chỉ loop dòng CÓ SẴN trong chapters) không tìm
-- thấy gì để xếp hàng; user phải chờ crawler tải mục lục xong (10-20s, và kẹt
-- vĩnh viễn nếu truyện lỡ bị đánh dấu toc_synced_at khi nguồn trả 0 chương).
--
-- Sửa: RPC TỰ TẠO stub trống cho khoảng cần dịch rồi mới xếp hàng. Chương queued
-- thiếu source_chapter_id sẽ được worker tự tải mục lục đầy đủ + nội dung
-- (main.py nhánh missing_stub) → truyện kẹt kiểu cũ cũng tự lành khi bấm dịch.

create or replace function request_translation(
  p_novel_id bigint, p_up_to int default 10, p_priority int default 50)
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_count int := 0;
  v_cap int;
  r record;
begin
  if auth.uid() is null then
    raise exception 'login required';
  end if;

  -- Mục lục lười chưa về → tạo stub trống 1..min(p_up_to, tổng chương trên nguồn).
  -- Chưa biết tổng (chapter_count_source 0/null) thì tin p_up_to; truyện không
  -- tồn tại thì v_cap null → generate_series rỗng, vô hại.
  select coalesce(nullif(chapter_count_source, 0), p_up_to) into v_cap
  from novels where id = p_novel_id;
  insert into chapters (novel_id, chapter_index)
  select p_novel_id, gs
  from generate_series(1, least(p_up_to, coalesce(v_cap, 0))) gs
  on conflict (novel_id, chapter_index) do nothing;

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
