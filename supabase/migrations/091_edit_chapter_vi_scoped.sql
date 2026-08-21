-- FIX [HIGH] edit_chapter_vi (021/076) dùng replace() THÔ: không ranh giới từ + áp cả chương.
-- Đã ra lỗi thật trong chapter_edit_vi_history: 'em'→'muội' biến "xem" thành "xmuội";
-- 'Chu'→'Trúc Cơ Hậu Kỳ Cao Thủ' nổ mọi chữ "Chu" trong chương. Hai thay đổi:
--   1. thay theo RANH GIỚI TỪ — không ăn vào giữa từ khác;
--   2. p_para: app gửi nguyên văn đoạn đang chạm → chỉ sửa TRONG đoạn đó, chỗ khác yên.
-- p_para null = app bản cũ → vẫn cả chương, nhưng đã có ranh giới từ nên không phá từ khác.

-- Ranh giới từ theo [[:alnum:]] (chữ Việt có dấu là alnum ở collation UTF-8 của Supabase).
-- Biên TRÁI bắt bằng nhóm (^|[^[:alnum:]]) rồi trả lại qua \1 — không dùng lookbehind.
create or replace function _replace_word(p_text text, p_wrong text, p_correct text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    coalesce(p_text, ''),
    '(^|[^[:alnum:]])'
      || regexp_replace(p_wrong, '([\^$.|?*+()\[\]{}])', '\\1', 'g')
      || '(?![[:alnum:]])',
    -- \ và & là ký tự đặc biệt trong chuỗi THAY của regexp_replace → phải escape
    '\1' || replace(replace(p_correct, '\', '\'), '&', '\&'),
    'g')
$$;

-- Bỏ bản 4 tham số (021/076): để lại sẽ thành overload nhập nhằng với bản có default.
drop function if exists edit_chapter_vi(bigint, int, text, text);

create or replace function edit_chapter_vi(
  p_novel_id bigint, p_index int, p_wrong text, p_correct text, p_para text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_content text; v_title text;
  v_new_content text; v_new_title text; v_at int;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if p_wrong is null or p_wrong = '' then return; end if;

  select coalesce(content_vi, ''), coalesce(title_vi, '') into v_content, v_title
    from chapters where novel_id = p_novel_id and chapter_index = p_index;
  if not found then return; end if;

  v_at := case when p_para is null or p_para = '' then 0
               else position(p_para in v_content) end;
  if v_at > 0 then
    -- chỉ đoạn đang chạm: sửa trong đoạn rồi ghép lại đúng chỗ cũ
    v_new_content := overlay(v_content placing _replace_word(p_para, p_wrong, p_correct)
                             from v_at for length(p_para));
    v_new_title := v_title;
  else
    v_new_content := _replace_word(v_content, p_wrong, p_correct);
    v_new_title := _replace_word(v_title, p_wrong, p_correct);
  end if;

  if (v_new_content, v_new_title) = (v_content, v_title) then return; end if;

  update chapters set content_vi = v_new_content, title_vi = nullif(v_new_title, '')
   where novel_id = p_novel_id and chapter_index = p_index;
  insert into chapter_edit_vi_history (novel_id, chapter_index, wrong, correct, edited_by)
  values (p_novel_id, p_index, p_wrong, p_correct, auth.uid());
end $$;

grant execute on function edit_chapter_vi(bigint, int, text, text, text) to authenticated;
