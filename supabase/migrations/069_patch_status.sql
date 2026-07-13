-- Theo dõi việc "vá chương" từ trang Thuật ngữ: nút vá xếp 1 job patch chạy <1s rồi
-- biến mất, không để lại dấu vết nào để người dùng biết đã vá xong chưa / vá mấy chương.
-- Thêm cột result (worker ghi "N/M chương") + RPC đọc trạng thái job patch mới nhất của
-- 1 truyện, SECURITY DEFINER để user thường (né RLS admin-only trên translation_jobs)
-- vẫn xem được — nút vá mở cho mọi user, nên theo dõi cũng phải cho mọi user.

alter table translation_jobs add column if not exists result text;

create or replace function latest_patch_status(p_novel_id bigint)
returns table(status job_status, result text, done_at timestamptz, created_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select status, result, done_at, created_at
  from translation_jobs
  where novel_id = p_novel_id and type = 'patch'
  order by id desc
  limit 1;
$$;

grant execute on function latest_patch_status(bigint) to authenticated;
