-- FIX 091: escape regex viết bằng chuỗi thường bị nuốt dấu \ (kết quả đo trên DB thật:
-- thay 'a'→'x&y' ra "xay" vì \& không còn là & literal, và '3.5' không khớp nổi chính nó).
-- Dùng chuỗi dollar-quote: nó KHÔNG diễn giải backslash nên escape luôn đúng, không phụ
-- thuộc standard_conforming_strings.
create or replace function _replace_word(p_text text, p_wrong text, p_correct text)
returns text
language sql
immutable
as $fn$
  select regexp_replace(
    coalesce(p_text, ''),
    '(^|[^[:alnum:]])'
      || regexp_replace(p_wrong, $re$([\^$.|?*+()\[\]{}])$re$, $re$\\1$re$, 'g')
      || '(?![[:alnum:]])',
    $re$\1$re$ || replace(replace(p_correct, $q$\$q$, $q$\$q$), $q$&$q$, $q$\&$q$),
    'g')
$fn$;
