-- claim_next_job nhận thêm bộ lọc LOẠI job, để dành riêng luồng cho chương.
--
-- Vấn đề: metadata ưu tiên 8-10, chương ưu tiên 75 (nhỏ = làm trước), nên hễ hàng đợi
-- còn metadata là mọi luồng đều bốc metadata. Metadata chờ LLM 70-150s qua mạng, trong
-- lúc đó CPU đứng im ở 0% dù 1969 chương đang xếp hàng — mà chương dịch bằng Hachimi
-- (CT2 local) vốn không đụng gì tới LLM. Hai việc này lẽ ra chạy chồng lên nhau được.
--
-- Cách chia (quy ước trong worker._consume_loop): luồng 0 nhận MỌI loại như cũ; luồng
-- 1 trở đi chỉ nhận 'chapter'. Vậy metadata không bao giờ chặn hết đường của Hachimi,
-- còn khi hết chương thì luồng chuyên chương nghỉ chứ không tranh việc LLM.
--
-- p_types null = mọi loại → gọi kiểu cũ giữ nguyên hành vi. Phải DROP bản một tham số
-- (không phải CREATE OR REPLACE) vì thêm tham số có default sẽ tạo overload, và khi đó
-- PostgREST gặp lời gọi chỉ có worker_id sẽ không biết chọn hàm nào.

drop function if exists claim_next_job(text);

create or replace function claim_next_job(worker_id text, p_types text[] default null)
returns setof translation_jobs
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate translation_jobs%rowtype;
  got_novel_lock boolean;
begin
  select j.* into candidate
  from translation_jobs j
  where j.status = 'pending'
    and (p_types is null or j.type = any(p_types))
    and not exists (
      select 1
      from translation_jobs running
      where running.status = 'running'
        and running.novel_id = j.novel_id
    )
    and (
      j.type <> 'chapter'
      or exists (
        select 1
        from chapters c
        where c.id = j.chapter_id
          and c.content_zh is not null
          and (
            c.content_vi is not null
            or not exists (
              select 1
              from chapters p
              where p.novel_id = c.novel_id
                and p.chapter_index = c.chapter_index - 1
                and p.translation_status in ('queued', 'translating')
            )
          )
      )
    )
  order by j.priority, j.created_at
  limit 1
  for update skip locked;

  if not found then
    return;
  end if;

  -- Đây là statement riêng: ở READ COMMITTED, recheck bên dưới nhận snapshot mới.
  -- Nếu lane khác đang claim cùng novel thì trả rỗng ngay, không giữ lane chờ lock.
  select pg_try_advisory_xact_lock(62063, candidate.novel_id::integer)
    into got_novel_lock;
  if not got_novel_lock then
    return;
  end if;

  -- Bắt buộc recheck SAU khi giữ advisory lock (migration 062 còn race ở chỗ này).
  if exists (
    select 1 from translation_jobs running
    where running.status = 'running'
      and running.novel_id = candidate.novel_id
  ) then
    return;
  end if;

  return query
  update translation_jobs j
  set status = 'running', locked_by = worker_id, locked_at = now(),
      started_at = coalesce(j.started_at, now()), attempts = j.attempts + 1
  where j.id = candidate.id and j.status = 'pending'
  returning j.*;
end;
$$;

revoke execute on function claim_next_job(text, text[])
  from public, anon, authenticated;
