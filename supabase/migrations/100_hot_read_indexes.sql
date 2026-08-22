-- Index nóng cho truy vấn đọc nhiều:
--   1. term_edit_history: policy own_history lọc user_id = auth.uid() mỗi lần mở
--      lịch sử; bảng tăng 1 row/lần sửa chương nên cần index theo user.
--   2. novels.updated_at: màn Quản trị sort updated_at desc (admin.dart) nhưng
--      bảng chỉ có index last_chapter_at/source_rank/... — novels lớn dần sẽ chậm.
-- Idempotent: IF NOT EXISTS.

create index if not exists idx_term_edit_history_user
  on term_edit_history (user_id, created_at desc);

create index if not exists idx_novels_updated_at
  on novels (updated_at desc);
