-- Job 'audit': quét chương done hỏng (còn tiếng Trung / cụt / mất đoạn) → xếp lại dịch.
-- Nút "Quét lỗi" trong Quản trị gọi request_audit(); worker.handle_audit xử lý (heuristic,
-- không tốn LLM). Cũng chạy tự động định kỳ trong worker (audit_interval_min).

alter type job_type add value if not exists 'audit';

-- audit là job TOÀN CỤC (không thuộc truyện nào) → novel_id được phép null.
alter table translation_jobs alter column novel_id drop not null;

-- Admin bấm "Quét lỗi" → xếp 1 job audit (chống trùng: chỉ 1 audit pending/running).
create or replace function request_audit()
returns void
language plpgsql
security definer
as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  insert into translation_jobs (type, novel_id, priority)
  select 'audit', null, 20
  where not exists (
    select 1 from translation_jobs
    where type = 'audit' and status in ('pending', 'running')
  );
end $$;
