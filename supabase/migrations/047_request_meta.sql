-- Nút "Dịch lại tên" trong Quản trị (trang 1 truyện) gọi request_meta(novel_id) →
-- xếp 1 job 'metadata', worker.handle_metadata dịch lại tên/mô tả/thể loại theo prompt
-- hiện tại, đè lên bản cũ. Dùng sau khi sửa prompt tên (vd cấm nửa nghĩa nửa phiên âm).
--
-- Không có nút này thì tên đã lưu không bao giờ dịch lại: crawler chỉ enqueue metadata
-- khi meta_translated=false, mà handle_metadata xong set =true.
--
-- Chống trùng: uq_job_meta_active (partial index pending/running) đã chặn 2 job cùng lúc;
-- guard "not exists" ở đây để bấm nhiều lần không lỗi. Job metadata cũ đã done/failed
-- KHÔNG chặn (partial index) nên khỏi cần xoá.

create or replace function request_meta(p_novel_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  insert into translation_jobs (type, novel_id, priority)
  select 'metadata', p_novel_id, 5
  where not exists (
    select 1 from translation_jobs
    where novel_id = p_novel_id and type = 'metadata'
      and status in ('pending', 'running')
  );
end $$;

revoke execute on function request_meta(bigint) from anon;
