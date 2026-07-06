-- Glossary UI + nút dịch lại (P2.3)
-- App cá nhân, mọi user đăng nhập đều tin cậy → cho sửa/duyệt/xóa term trực tiếp.

drop policy if exists read_glossary on glossary_terms;
create policy read_glossary on glossary_terms for select
  using (approved or auth.uid() is not null);  -- user login thấy cả term gợi ý chờ duyệt

create policy edit_glossary on glossary_terms for update to authenticated
  using (true) with check (true);
create policy delete_glossary on glossary_terms for delete to authenticated
  using (true);

-- Xếp job 'patch': vá chương đã dịch bằng term mới (string-replace, không tốn LLM)
create or replace function request_patch(p_novel_id bigint)
returns void
language plpgsql
security definer
as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  insert into translation_jobs (type, novel_id, priority)
  select 'patch', p_novel_id, 40
  where not exists (
    select 1 from translation_jobs
    where novel_id = p_novel_id and type = 'patch' and status in ('pending', 'running')
  );
end $$;

-- Dịch lại 1 chương (kể cả chương đã done — khác request_translation)
create or replace function retranslate_chapter(p_novel_id bigint, p_index int)
returns void
language plpgsql
security definer
as $$
declare
  v_chapter_id bigint;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  select id into v_chapter_id from chapters
  where novel_id = p_novel_id and chapter_index = p_index;
  if v_chapter_id is null then raise exception 'chapter not found'; end if;

  update chapters set translation_status = 'queued' where id = v_chapter_id;
  insert into translation_jobs (type, novel_id, chapter_id, priority)
  values ('chapter', p_novel_id, v_chapter_id, 30)
  on conflict do nothing;
end $$;
