-- Trạng thái 2-pass thích ứng theo truyện: pass phân tích (chốt tên riêng) chạy ở arc
-- mở đầu, tự tắt khi một chương gần như không ra tên mới nữa (đỡ tốn ở chương sau).
alter table novels add column if not exists twopass_active boolean not null default true;
alter table novels add column if not exists twopass_low_streak int not null default 0;
