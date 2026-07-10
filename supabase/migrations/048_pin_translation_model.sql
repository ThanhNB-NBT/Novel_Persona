-- Mỗi truyện chốt một provider + model ở chương đầu để không đổi giọng/xưng hô
-- giữa các chương khi FallbackChain phải dùng model dự phòng.
alter table novels
  add column if not exists translation_provider text,
  add column if not exists translation_model text;
