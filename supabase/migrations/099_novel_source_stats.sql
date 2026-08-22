-- Nguồn công bố nhiều hơn những gì crawler đang lấy. Khảo sát 5 nguồn đang bật:
--   faloo    : 字数 417万 · 已有 25.930.710 人阅读 · 鲜花 32685
--   ptwxz    : 全文长度 1741012字 · 最后更新 2023-09-02 · 收藏数 215 · 总推荐数 534
--   69shuba  : 363.1万字 · 更新 2014-10-07 · 1254 章节数
--   ddxs     : chỉ có thể loại (breadcrumb) — trang truyện vỏn vẹn 3KB
--   quanben5 : chỉ có thể loại + trạng thái
-- word_count đứng riêng vì còn dùng để lọc/sắp xếp; phần còn lại mỗi nguồn một kiểu nên
-- gom vào một túi JSON, thêm nguồn mới không phải đẻ cột.
alter table novels add column if not exists word_count integer;
alter table novels add column if not exists source_stats jsonb;

-- Lọc/sắp theo độ dài: chỉ index truyện thật sự có số liệu (đa số nguồn không công bố).
create index if not exists idx_novels_word_count
  on novels (word_count) where word_count is not null;

comment on column novels.word_count is
  'Số chữ Trung nguồn công bố (không phải số chữ bản dịch). NULL = nguồn không cho biết.';
comment on column novels.source_stats is
  'Chỉ số thô nguồn công bố, khoá tuỳ nguồn: reads/flowers (faloo), favorites/recommends/
   updated_at/first_release (ptwxz), updated_at/chapter_count_site (69shuba).';
