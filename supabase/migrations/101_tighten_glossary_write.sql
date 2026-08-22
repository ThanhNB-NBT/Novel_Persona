-- Siết glossary_terms UPDATE/DELETE: trước đây mọi authenticated sửa/xoá được
-- MỌI term (using (true)) — kể cả term global approved mà worker dùng dịch toàn
-- kho. Giờ chỉ người tạo term hoặc admin được sửa/xoá; SELECT vẫn mở cho mọi user.
-- App chỉ có 2 tài khoản đều là admin nên không đổi luồng sử dụng.
-- Idempotent: drop if exists trước khi tạo.

drop policy if exists edit_glossary on glossary_terms;
create policy edit_glossary on glossary_terms for update to authenticated
  using (created_by = auth.uid() or is_admin())
  with check (created_by = auth.uid() or is_admin());

drop policy if exists delete_glossary on glossary_terms;
create policy delete_glossary on glossary_terms for delete to authenticated
  using (created_by = auth.uid() or is_admin());
