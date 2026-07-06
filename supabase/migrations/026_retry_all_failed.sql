-- Nút "Chạy lại job lỗi" (admin, tab Worker): reset MỌI job failed về pending trong 1 RPC.
-- Kèm fix chương kẹt: chương crawl lỗi bị đánh 'failed' nhưng job vẫn pending → crawler
-- không tải lại (chỉ tải chương 'queued') → job treo vĩnh viễn. Trả các chương đó về
-- 'queued' để crawler thử lại.
create or replace function admin_retry_all_failed()
returns int
language plpgsql
security definer
as $$
declare n int;
begin
  if not is_admin() then
    raise exception 'admin only';
  end if;
  update translation_jobs
  set status = 'pending', attempts = 0, error = null, locked_by = null, locked_at = null
  where status = 'failed';
  get diagnostics n = row_count;
  update chapters c
  set translation_status = 'queued'
  where c.translation_status = 'failed'
    and exists (
      select 1 from translation_jobs j
      where j.chapter_id = c.id and j.status in ('pending', 'running')
    );
  return n;
end;
$$;
