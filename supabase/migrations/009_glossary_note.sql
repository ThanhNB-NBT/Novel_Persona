-- Ghi chú cho thuật ngữ: giới tính + vai vế nhân vật (vd "nam, sư huynh").
-- Dịch giả dùng để chọn đúng xưng hô (hắn/nàng, huynh/đệ) và giữ nhất quán giữa các chương.
-- Học từ GalTransl: gắn giới tính vào từ điển → model tự chọn đại từ đúng.
alter table glossary_terms add column if not exists note text;
