-- Tìm kiếm KHÔNG DẤU: gõ "Toan Dan" phải ra "Toàn Dân Chuyển Dịch".
--
-- Trước đây client bắn thẳng `title_vi ilike '%<gõ>%'`, nên người gõ không dấu
-- (rất phổ biến trên điện thoại) nhận 0 kết quả dù truyện nằm sẵn trong kho.
-- Đã đo trên máy: gõ "Toan Dan" ra 0/21.605 truyện.
--
-- Cách chữa: cột sinh sẵn `search_norm` gom tên + tác giả (cả Việt lẫn Trung) đã
-- bỏ dấu và hạ chữ thường, kèm index trigram để `ilike '%…%'` không quét bảng.
-- Client cũng bỏ dấu chuỗi người dùng gõ trước khi hỏi (hàm boDau() bên Dart).

create extension if not exists unaccent;
create extension if not exists pg_trgm;

-- unaccent() một-tham-số là STABLE nên không dùng được trong cột sinh/index.
-- Bản hai-tham-số với regdictionary thì IMMUTABLE — đây là cách chính tắc.
create or replace function public.vn_norm(txt text)
returns text
language sql
immutable
parallel safe
as $$
  select lower(unaccent('unaccent'::regdictionary, coalesce(txt, '')))
$$;

alter table novels
  add column if not exists search_norm text
  generated always as (
    public.vn_norm(
      coalesce(title_vi, '')  || ' ' || coalesce(title_zh, '')  || ' ' ||
      coalesce(author_vi, '') || ' ' || coalesce(author_zh, '')
    )
  ) stored;

create index if not exists idx_novels_search_norm_trgm
  on novels using gin (search_norm gin_trgm_ops);
