-- "Xoá vĩnh viễn" phải VĨNH VIỄN: trước đây xoá novels là hết dấu vết, chu kỳ discovery
-- sau thấy truyện vẫn trong top nguồn → crawl lại + đốt token dịch metadata lần nữa.
-- Trigger ghi lại truyện đã xoá vào crawl_blacklist; worker bỏ qua khi discovery
-- (khớp theo source_novel_id LẪN dedup_key — bản clone ở nguồn khác cũng không lọt lại).
-- Muốn crawl lại truyện đã xoá: lệnh `add` của worker tự gỡ khỏi blacklist.
create table crawl_blacklist (
  id bigint generated always as identity primary key,
  source_id bigint references sources(id) on delete cascade,
  source_novel_id text,
  dedup_key text,
  title_zh text,          -- để admin còn biết dòng blacklist là truyện nào
  created_at timestamptz not null default now()
);
create index idx_blacklist_source on crawl_blacklist (source_id, source_novel_id);

alter table crawl_blacklist enable row level security;
create policy read_blacklist on crawl_blacklist for select
  using (auth.uid() is not null);
create policy admin_all_blacklist on crawl_blacklist for all to authenticated
  using (is_admin()) with check (is_admin());

-- security definer: user thường xoá truyện qua RLS admin → trigger vẫn ghi được blacklist
create or replace function novels_delete_blacklist()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into crawl_blacklist (source_id, source_novel_id, dedup_key, title_zh)
  values (old.source_id, old.source_novel_id, old.dedup_key, old.title_zh);
  return old;
end $$;

create trigger trg_novels_blacklist after delete on novels
  for each row execute function novels_delete_blacklist();
