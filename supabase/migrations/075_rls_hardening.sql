-- FIX [LOW] các điểm RLS/spam từ đợt review.

-- 1) novels.hidden (thêm ở 011) nhưng read_novels (001) vẫn using(true) → truyện ẩn vẫn
--    hiện cho mọi người. Ẩn với khách/user thường, admin vẫn thấy.
drop policy if exists read_novels on novels;
create policy read_novels on novels for select using (not hidden or is_admin());

-- 2) crawl_latency (071) chưa bật RLS → bảng mở toang cho authenticated. Bật RLS: worker
--    (service_role) bỏ qua RLS nên vẫn ghi được; app chỉ admin đọc.
alter table crawl_latency enable row level security;
drop policy if exists admin_read_crawl_latency on crawl_latency;
create policy admin_read_crawl_latency on crawl_latency for select to authenticated
  using (is_admin());

-- 3) request_toc (033) không đăng nhập + không giới hạn tần suất → spam re-stamp. App chỉ
--    còn đăng nhập (bỏ đăng ký) nên bắt buộc authenticated không phá luồng nào, + DEBOUNCE
--    5' mỗi truyện: chỉ đặt lại toc_requested_at khi chưa xin hoặc lần trước đã quá 5 phút.
--    ponytail: debounce mức-hàng là đủ chặn spam; rate-limit theo user thêm sau nếu cần.
create or replace function request_toc(p_novel_id bigint)
returns void
language sql
security definer
set search_path = public
as $$
  update novels set toc_requested_at = now()
  where id = p_novel_id and toc_synced_at is null
    and (toc_requested_at is null or toc_requested_at < now() - interval '5 min');
$$;
revoke execute on function request_toc(bigint) from anon;
grant execute on function request_toc(bigint) to authenticated;
