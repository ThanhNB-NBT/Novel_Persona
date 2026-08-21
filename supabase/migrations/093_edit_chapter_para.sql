-- Sửa NGUYÊN ĐOẠN bản dịch: câu tối nghĩa phải viết lại cả câu, thay-một-từ không đủ.
-- Khác edit_chapter_vi ở chỗ không thay chuỗi mù: chỉ ghép đoạn mới vào đúng vị trí đoạn cũ,
-- và chỉ khi đoạn cũ CÒN NGUYÊN trong chương (người khác vừa sửa → báo lỗi, không đè mù).
create or replace function edit_chapter_para(
  p_novel_id bigint, p_index int, p_old text, p_new text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_content text; v_at int;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if p_old is null or p_old = '' or p_new is null then return; end if;
  if p_old = p_new then return; end if;

  select coalesce(content_vi, '') into v_content
    from chapters where novel_id = p_novel_id and chapter_index = p_index;
  if not found then return; end if;

  v_at := position(p_old in v_content);
  if v_at = 0 then
    raise exception 'đoạn này vừa đổi ở nơi khác — tải lại chương rồi sửa tiếp';
  end if;

  update chapters
     set content_vi = overlay(v_content placing p_new from v_at for length(p_old))
   where novel_id = p_novel_id and chapter_index = p_index;
  insert into chapter_edit_vi_history (novel_id, chapter_index, wrong, correct, edited_by)
  values (p_novel_id, p_index, p_old, p_new, auth.uid());
end $$;

grant execute on function edit_chapter_para(bigint, int, text, text) to authenticated;
