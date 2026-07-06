-- Chạy lại 1 job: ngoài reset job phải trả CHƯƠNG failed về queued,
-- nếu không crawler bỏ qua (chỉ tải chương queued) → bấm "Chạy lại" không có gì xảy ra.
create or replace function admin_retry_job(p_job_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update translation_jobs
     set status = 'pending', attempts = 0, error = null,
         locked_by = null, locked_at = null
   where id = p_job_id;
  update chapters c
     set translation_status = 'queued'
    from translation_jobs j
   where j.id = p_job_id
     and j.chapter_id = c.id
     and c.translation_status = 'failed';
end $$;
