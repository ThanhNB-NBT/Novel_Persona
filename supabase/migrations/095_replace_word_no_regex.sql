-- 091/094 escape regex trong chuỗi SQL đo trên DB thật vẫn sai: 'a'→'x&y' ra "xay" (& thành
-- toàn-match) và '3.5' không khớp nổi chính nó. Bỏ regex hẳn: cắt chuỗi theo p_wrong rồi chỉ
-- ráp p_correct vào những chỗ HAI BÊN không phải chữ/số. Không escape gì nữa nên không sai được.
create or replace function _replace_word(p_text text, p_wrong text, p_correct text)
returns text
language plpgsql
immutable
as $fn$
declare
  parts text[];
  out_text text;
  i int;
  prev_char text;
  next_char text;
begin
  if p_wrong is null or p_wrong = '' then return coalesce(p_text, ''); end if;
  parts := string_to_array(coalesce(p_text, ''), p_wrong);
  out_text := parts[1];
  for i in 2 .. coalesce(array_length(parts, 1), 1) loop
    -- biên tính trên văn bản GỐC (parts), không tính trên bản đã ghép — hai lần khớp dính
    -- nhau ("aa" với wrong 'a') thì ký tự kề là chính p_wrong, tức vẫn là giữa từ.
    prev_char := case
      when parts[i - 1] <> '' then right(parts[i - 1], 1)
      when i > 2 then right(p_wrong, 1)
      else '' end;
    next_char := left(parts[i], 1);
    if prev_char ~ '[[:alnum:]]' or next_char ~ '[[:alnum:]]' then
      out_text := out_text || p_wrong || parts[i];   -- dính vào từ khác → không đụng
    else
      out_text := out_text || p_correct || parts[i];
    end if;
  end loop;
  return out_text;
end
$fn$;
