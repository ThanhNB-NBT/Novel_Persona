-- BUG: user sửa/thêm glossary_terms từ app → trigger bump_glossary_version ghi bảng
-- novel_glossary_version, nhưng trigger chạy bằng quyền USER và bảng đó bật RLS không có
-- policy INSERT/UPDATE cho user → lỗi 42501 "violates row-level security". Kết quả: nút
-- "Sửa bản dịch" trong reader (và mọi thao tác glossary của user) fail im lặng.
-- Fix: cho trigger chạy SECURITY DEFINER (bỏ qua RLS khi bump version). set search_path
-- cố định theo khuyến nghị bảo mật.
create or replace function bump_glossary_version()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.novel_id is not null then
    insert into novel_glossary_version (novel_id, version) values (new.novel_id, 1)
    on conflict (novel_id) do update set version = novel_glossary_version.version + 1;
  end if;
  return new;
end $$;
