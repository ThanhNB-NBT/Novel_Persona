-- Sửa bản dịch TRỰC TIẾP 1 chương từ app (reader) → hiện ngay, KHÔNG qua hàng đợi worker,
-- KHÔNG gọi LLM. String-replace wrong→correct trong content_vi + title_vi của đúng chương đó.
-- RLS: chapters chỉ service_role ghi → cần RPC SECURITY DEFINER; bắt buộc đã đăng nhập.
create or replace function edit_chapter_vi(
  p_novel_id bigint, p_index int, p_wrong text, p_correct text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if p_wrong is null or p_wrong = '' then return; end if;
  update chapters
    set content_vi = replace(coalesce(content_vi, ''), p_wrong, p_correct),
        title_vi   = replace(coalesce(title_vi, ''), p_wrong, p_correct)
  where novel_id = p_novel_id and chapter_index = p_index;
end $$;
