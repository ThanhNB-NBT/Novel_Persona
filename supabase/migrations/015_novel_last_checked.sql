-- Theo dõi cập nhật chương: last_checked_at = lần cuối worker soi mục lục truyện này.
-- Khác last_chapter_at (thời điểm CÓ chương mới): last_checked_at bump MỖI lần soi (kể cả
-- không có chương mới) → dùng để xoay vòng refresh có trần, tránh soi lại 1 truyện mãi.
-- NULL = chưa soi lần nào → ưu tiên soi trước.
alter table novels add column if not exists last_checked_at timestamptz;
create index if not exists idx_novels_checked
  on novels (last_checked_at asc nulls first) where is_canonical;
