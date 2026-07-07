-- Nút "Dịch lại tất cả" ở Danh sách chương: xếp lại MỌI chương đã dịch xong của truyện
-- để dịch lại bằng prompt/glossary hiện tại. Giữ nguyên content_vi cũ cho tới khi bản
-- mới đè lên → người đang đọc không bị trắng chương. Trả về số chương đã xếp.
-- Chương đang queued/translating bỏ qua (đã trong hàng đợi rồi).
create or replace function retranslate_all(p_novel_id bigint)
returns int
language plpgsql
security definer
as $$
declare
  v_count int := 0;
  r record;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  for r in
    select id from chapters
    where novel_id = p_novel_id and translation_status in ('done', 'failed')
    order by chapter_index
  loop
    delete from translation_jobs
      where chapter_id = r.id and status in ('failed', 'done');  -- dọn job cũ (018)
    update chapters set translation_status = 'queued' where id = r.id;
    insert into translation_jobs (type, novel_id, chapter_id, priority)
    values ('chapter', p_novel_id, r.id, 45)
    on conflict do nothing;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
