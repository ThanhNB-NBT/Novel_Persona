-- Chương 1..hachimi_extract_max_chapter bị dịch khi glossary còn RỖNG (trích tên chạy nền,
-- chậm hơn dịch) → cùng một nhân vật ra hai tên trong một truyện. Worker xếp dịch lại các
-- chương đó MỘT LẦN khi vùng trích đi qua; cột này là dấu "đã xếp rồi", để null = chưa.
alter table novels add column if not exists early_retranslated_at timestamptz;
