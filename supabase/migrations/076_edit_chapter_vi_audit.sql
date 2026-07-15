-- FIX [HIGH] edit_chapter_vi (021) cho MỌI user đã đăng nhập string-replace nội dung dịch
-- bất kỳ, KHÔNG lưu vết → phá hoại không truy được, không đảo ngược được. Giữ thiết kế
-- "cộng đồng cùng sửa" (035) nhưng THÊM AUDIT LOG: mỗi lần sửa ghi ai/gì/khi nào, admin
-- soi và đảo ngược được (đảo = replace correct→wrong). Chỉ ghi khi thật sự có thay đổi.

create table if not exists chapter_edit_vi_history (
  id bigint generated always as identity primary key,
  novel_id bigint references novels(id) on delete cascade,
  chapter_index int not null,
  wrong text not null,
  correct text not null,
  edited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_chapter_edit_hist
  on chapter_edit_vi_history (novel_id, chapter_index, created_at desc);

alter table chapter_edit_vi_history enable row level security;
-- Chỉ admin đọc lịch sử; chèn duy nhất qua hàm SECURITY DEFINER bên dưới (không policy insert).
drop policy if exists admin_read_chapter_edits on chapter_edit_vi_history;
create policy admin_read_chapter_edits on chapter_edit_vi_history for select to authenticated
  using (is_admin());

-- ponytail: audit-log để đảo ngược phá hoại là đủ; rate-limit theo user thêm sau nếu bị lạm.
create or replace function edit_chapter_vi(
  p_novel_id bigint, p_index int, p_wrong text, p_correct text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changed boolean;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if p_wrong is null or p_wrong = '' then return; end if;
  update chapters
    set content_vi = replace(coalesce(content_vi, ''), p_wrong, p_correct),
        title_vi   = replace(coalesce(title_vi, ''), p_wrong, p_correct)
  where novel_id = p_novel_id and chapter_index = p_index
    and (position(p_wrong in coalesce(content_vi, '')) > 0
      or position(p_wrong in coalesce(title_vi, '')) > 0)
  returning true into v_changed;
  if coalesce(v_changed, false) then
    insert into chapter_edit_vi_history (novel_id, chapter_index, wrong, correct, edited_by)
    values (p_novel_id, p_index, p_wrong, p_correct, auth.uid());
  end if;
end $$;
