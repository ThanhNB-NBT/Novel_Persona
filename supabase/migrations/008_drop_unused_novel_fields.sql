-- Bỏ các trường không nguồn nào điền + app không đọc: word_count, rating, tags.
-- Fanqie & shuhaige đều không cung cấp; app chỉ dùng genres. Dọn cho gọn.
alter table novels
  drop column if exists tags,
  drop column if exists rating_source,
  drop column if exists rating_count,
  drop column if exists word_count;
