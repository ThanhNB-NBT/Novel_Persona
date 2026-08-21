-- 095 sót 2 biên (đo trên DB thật): text rỗng → trả NULL (string_to_array('' , x) ra mảng rỗng),
-- và "aa" với wrong='a' bị thành "xa" vì chỗ trống GIỮA hai lần khớp chưa tính ký tự kề.
create or replace function _replace_word(p_text text, p_wrong text, p_correct text)
returns text
language plpgsql
immutable
as $fn$
declare
  parts text[];
  n int;
  out_text text;
  i int;
  prev_char text;
  next_char text;
begin
  if p_text is null or p_text = '' or p_wrong is null or p_wrong = '' then
    return coalesce(p_text, '');
  end if;
  parts := string_to_array(p_text, p_wrong);
  n := coalesce(array_length(parts, 1), 0);
  if n < 2 then return p_text; end if;
  out_text := parts[1];
  for i in 2 .. n loop
    -- biên tính trên văn bản GỐC; mảnh rỗng = hai lần khớp dính nhau nên ký tự kề chính là
    -- p_wrong ("aa" với wrong='a' vẫn là giữa từ, không được thay).
    prev_char := case
      when parts[i - 1] <> '' then right(parts[i - 1], 1)
      when i > 2 then right(p_wrong, 1)
      else '' end;
    next_char := case
      when parts[i] <> '' then left(parts[i], 1)
      when i < n then left(p_wrong, 1)
      else '' end;
    if prev_char ~ '[[:alnum:]]' or next_char ~ '[[:alnum:]]' then
      out_text := out_text || p_wrong || parts[i];
    else
      out_text := out_text || p_correct || parts[i];
    end if;
  end loop;
  return out_text;
end
$fn$;
