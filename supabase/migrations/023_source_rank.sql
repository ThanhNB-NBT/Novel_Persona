-- Thứ hạng truyện trên bảng xếp hạng nguồn (shuhaige /top.html = 总点击 tổng lượt xem).
-- Nhỏ = hot hơn; null = không nằm bảng xếp hạng. Dùng cho "Đề cử" + ưu tiên crawl.
alter table novels add column if not exists source_rank int;
create index if not exists idx_novels_rank on novels (source_rank) where source_rank is not null;
