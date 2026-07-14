-- Discovery phân trang có trí nhớ: đào sâu dần nhưng định kỳ quay lại trang 1.
-- Worker service_role ghi; admin chỉ cần đọc để chẩn đoán.
create table if not exists crawl_discovery_frontier (
  source_id bigint not null references sources(id) on delete cascade,
  pool text not null,
  next_page int not null default 1 check (next_page >= 1),
  cycle_count bigint not null default 0 check (cycle_count >= 0),
  wrapped_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (source_id, pool)
);

create table if not exists crawl_candidates (
  id bigint generated always as identity primary key,
  source_id bigint not null references sources(id) on delete cascade,
  source_novel_id text not null,
  pool text not null,
  title_zh text,
  status_hint text not null default 'ongoing',
  discovered_page int not null default 1,
  priority int not null default 50,
  status text not null default 'pending',
  free_chapter_count int,
  attempts int not null default 0,
  retry_after timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_id, pool, source_novel_id)
);

create index if not exists idx_crawl_candidates_queue
  on crawl_candidates (source_id, status, retry_after, created_at);

alter table crawl_discovery_frontier enable row level security;
alter table crawl_candidates enable row level security;

drop policy if exists admin_read_discovery_frontier on crawl_discovery_frontier;
create policy admin_read_discovery_frontier on crawl_discovery_frontier
  for select to authenticated using (is_admin());
drop policy if exists admin_read_crawl_candidates on crawl_candidates;
create policy admin_read_crawl_candidates on crawl_candidates
  for select to authenticated using (is_admin());
