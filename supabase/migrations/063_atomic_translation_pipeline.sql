-- Làm cứng pipeline dịch nhiều lane:
-- 1) claim theo novel có recheck sau advisory lock (không dùng snapshot CTE cũ);
-- 2) lưu chapter + đóng job + tăng bộ đếm trong một transaction;
-- 3) defer lỗi tạm thời trả lại attempt;
-- 4) dọn và chặn glossary trùng theo truyện.

create or replace function claim_next_job(worker_id text)
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

  -- Bắt buộc recheck SAU khi giữ advisory lock. Đây là chỗ migration 062 còn race:
  -- CTE cũ có thể nhìn snapshot trước khi lane kia commit rồi vẫn update job thứ hai.
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


create or replace function finalize_chapter_job(
  p_job_id bigint,
  p_worker_id text,
  p_chapter_id bigint,
  p_title_vi text,
  p_summary_vi text,
  p_content_vi text,
  p_model text,
  p_prompt_tokens integer,
  p_completion_tokens integer,
  p_glossary_version integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job translation_jobs%rowtype;
  v_chapter chapters%rowtype;
  v_first_translation boolean;
begin
  select * into v_job
  from translation_jobs
  where id = p_job_id
  for update;

  if not found or v_job.status <> 'running'
      or v_job.locked_by is distinct from p_worker_id
      or v_job.chapter_id is distinct from p_chapter_id then
    raise exception 'job % không còn thuộc worker % hoặc không khớp chapter %',
      p_job_id, p_worker_id, p_chapter_id using errcode = '55000';
  end if;

  select * into v_chapter
  from chapters
  where id = p_chapter_id
  for update;
  if not found then
    raise exception 'chapter % không tồn tại', p_chapter_id using errcode = 'P0002';
  end if;

  v_first_translation := v_chapter.content_vi is null;

  update chapters
  set title_vi = p_title_vi,
      summary_vi = p_summary_vi,
      content_vi = p_content_vi,
      translation_status = 'done',
      translated_at = now(),
      model_used = p_model,
      prompt_tokens = p_prompt_tokens,
      completion_tokens = p_completion_tokens,
      glossary_version = p_glossary_version
      -- Cố ý KHÔNG xóa content_zh: dịch lại không phải crawl lại bản gốc.
  where id = p_chapter_id;

  update translation_jobs
  set status = 'done', done_at = now(), error = null,
      locked_by = null, locked_at = null
  where id = p_job_id;

  if v_first_translation then
    update novels
    set chapter_count_translated = chapter_count_translated + 1
    where id = v_chapter.novel_id;
  end if;

  return true;
end;
$$;


create or replace function defer_translation_job(
  p_job_id bigint,
  p_worker_id text,
  p_error text default null,
  p_restore_attempt boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chapter_id bigint;
begin
  update translation_jobs
  set status = 'pending',
      attempts = case when p_restore_attempt then greatest(attempts - 1, 0) else attempts end,
      error = left(coalesce(p_error, ''), 2000),
      locked_by = null,
      locked_at = null
  where id = p_job_id
    and status = 'running'
    and locked_by = p_worker_id
  returning chapter_id into v_chapter_id;

  if not found then
    return false;
  end if;

  if v_chapter_id is not null then
    update chapters set translation_status = 'queued' where id = v_chapter_id;
  end if;
  return true;
end;
$$;


-- Giữ bản được duyệt trước; cùng trạng thái thì giữ bản xuất hiện đầu tiên, đúng với
-- quy tắc glossary hiện tại của worker.
with ranked as (
  select id,
         row_number() over (
           partition by novel_id, term_zh
           order by approved desc, created_at asc, id asc
         ) as rn
  from glossary_terms
  where novel_id is not null and term_zh is not null
)
delete from glossary_terms g
using ranked r
where g.id = r.id and r.rn > 1;

alter table glossary_terms
  add constraint uq_glossary_novel_term unique (novel_id, term_zh);

revoke execute on function claim_next_job(text)
  from public, anon, authenticated;
revoke execute on function finalize_chapter_job(
  bigint, text, bigint, text, text, text, text, integer, integer, integer
) from public, anon, authenticated;
revoke execute on function defer_translation_job(bigint, text, text, boolean)
  from public, anon, authenticated;
