-- Quét lỗi theo truyện từ màn Thuật ngữ: không phải đọc cả kho khi chỉ cần rà một truyện.
create or replace function request_novel_audit(p_novel_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;

  insert into translation_jobs (type, novel_id, priority)
  select 'audit', p_novel_id, 20
  where not exists (
    select 1 from translation_jobs
    where type = 'audit'
      and status in ('pending', 'running')
      and (novel_id is null or novel_id = p_novel_id)
  );
end $$;

revoke execute on function request_novel_audit(bigint) from anon;
