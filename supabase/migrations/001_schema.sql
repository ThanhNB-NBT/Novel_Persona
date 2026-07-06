-- =============================================================
-- Novel Reader — Schema P0
-- Chạy trong Supabase SQL Editor hoặc `supabase db push`
-- =============================================================

-- ---------- ENUMS ----------
create type novel_status as enum ('ongoing', 'completed', 'hiatus');
create type translation_status as enum ('none', 'queued', 'translating', 'done', 'failed');
create type job_type as enum ('metadata', 'chapter', 'comment_batch');
create type job_status as enum ('pending', 'running', 'done', 'failed');
create type term_type as enum ('person', 'place', 'sect', 'item', 'skill', 'other');
create type term_scope as enum ('user', 'novel', 'global');

-- ---------- SOURCES ----------
create table sources (
  id smallserial primary key,
  name text not null unique,          -- 'fanqie' | 'qidian' | 'jjwxc'
  base_url text not null,
  crawl_interval_min int not null default 60,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

insert into sources (name, base_url) values
  ('fanqie', 'https://fanqienovel.com'),
  ('qidian', 'https://www.qidian.com'),
  ('jjwxc',  'https://www.jjwxc.net');

-- ---------- NOVELS ----------
create table novels (
  id bigint generated always as identity primary key,
  source_id smallint not null references sources(id),
  source_novel_id text not null,
  source_url text not null,
  title_zh text not null,
  title_vi text,
  author_zh text,
  author_vi text,
  cover_url text,
  description_zh text,
  description_vi text,
  genres text[] not null default '{}',
  tags text[] not null default '{}',
  status novel_status not null default 'ongoing',
  chapter_count_source int not null default 0,
  chapter_count_translated int not null default 0,
  rating_source numeric(3,1),
  rating_count int,
  word_count bigint,
  last_chapter_at timestamptz,
  meta_translated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_id, source_novel_id)
);

create index idx_novels_latest on novels (last_chapter_at desc nulls last) where meta_translated;
create index idx_novels_genres on novels using gin (genres);
create index idx_novels_status on novels (status);

-- ---------- CHAPTERS ----------
create table chapters (
  id bigint generated always as identity primary key,
  novel_id bigint not null references novels(id) on delete cascade,
  chapter_index int not null,           -- 1-based, thứ tự đọc
  source_chapter_id text,
  title_zh text,
  title_vi text,
  content_zh text,
  content_vi text,
  translation_status translation_status not null default 'none',
  translated_at timestamptz,
  model_used text,
  prompt_tokens int,
  completion_tokens int,
  glossary_version int not null default 0,   -- version glossary lúc dịch (để biết chương nào cần vá)
  created_at timestamptz not null default now(),
  unique (novel_id, chapter_index)
);

create index idx_chapters_novel on chapters (novel_id, chapter_index);
create index idx_chapters_status on chapters (novel_id, translation_status);

-- ---------- COMMENTS (crawl từ nguồn) ----------
create table comments (
  id bigint generated always as identity primary key,
  novel_id bigint not null references novels(id) on delete cascade,
  source_comment_id text,
  username text,
  content_zh text not null,
  content_vi text,
  likes int not null default 0,
  posted_at timestamptz,
  translation_status translation_status not null default 'none',
  unique (novel_id, source_comment_id)
);

create index idx_comments_novel on comments (novel_id, likes desc);

-- ---------- TRANSLATION JOBS (queue trong Postgres) ----------
create table translation_jobs (
  id bigint generated always as identity primary key,
  type job_type not null,
  novel_id bigint not null references novels(id) on delete cascade,
  chapter_id bigint references chapters(id) on delete cascade,
  priority int not null default 100,     -- nhỏ hơn = ưu tiên hơn
  status job_status not null default 'pending',
  attempts int not null default 0,
  max_attempts int not null default 3,
  error text,
  locked_by text,                        -- id worker đang giữ job
  locked_at timestamptz,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  done_at timestamptz
);

-- chống job trùng cho cùng chương / cùng metadata khi chưa xong
create unique index uq_job_chapter_active on translation_jobs (chapter_id)
  where status in ('pending', 'running') and chapter_id is not null;
create unique index uq_job_meta_active on translation_jobs (novel_id, type)
  where status in ('pending', 'running') and type in ('metadata', 'comment_batch');
create index idx_jobs_pick on translation_jobs (status, priority, created_at) where status = 'pending';

-- Worker lấy job an toàn (nhiều worker không giành nhau)
create or replace function claim_next_job(worker_id text)
returns setof translation_jobs
language sql
security definer
as $$
  update translation_jobs
  set status = 'running', locked_by = worker_id, locked_at = now(),
      started_at = coalesce(started_at, now()), attempts = attempts + 1
  where id = (
    select id from translation_jobs
    where status = 'pending'
      and (
        type <> 'chapter'
        or exists (
          select 1 from chapters c
          where c.id = translation_jobs.chapter_id
            and c.content_zh is not null
        )
      )
    order by priority, created_at
    limit 1
    for update skip locked
  )
  returning *;
$$;

-- ---------- GLOSSARY ----------
create table glossary_terms (
  id bigint generated always as identity primary key,
  novel_id bigint references novels(id) on delete cascade,  -- null = global
  term_zh text,
  wrong_vi text,
  correct_vi text not null,
  term_type term_type not null default 'other',
  scope term_scope not null default 'novel',
  approved boolean not null default true,   -- global đặt false chờ duyệt
  created_by uuid references auth.users(id) on delete set null,
  usage_count int not null default 0,
  created_at timestamptz not null default now()
);

create index idx_glossary_novel on glossary_terms (novel_id) where approved;

-- tăng version glossary của truyện mỗi khi có term mới → biết chương nào dịch bằng glossary cũ
create table novel_glossary_version (
  novel_id bigint primary key references novels(id) on delete cascade,
  version int not null default 0
);

create or replace function bump_glossary_version()
returns trigger language plpgsql as $$
begin
  if new.novel_id is not null then
    insert into novel_glossary_version (novel_id, version) values (new.novel_id, 1)
    on conflict (novel_id) do update set version = novel_glossary_version.version + 1;
  end if;
  return new;
end $$;

create trigger trg_glossary_version after insert or update on glossary_terms
  for each row execute function bump_glossary_version();

create table term_edit_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  chapter_id bigint references chapters(id) on delete set null,
  glossary_term_id bigint references glossary_terms(id) on delete set null,
  before_text text,
  after_text text,
  created_at timestamptz not null default now()
);

-- ---------- USERS ----------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  settings jsonb not null default '{}',
  created_at timestamptz not null default now()
);

-- set search_path bắt buộc: Auth service gọi trigger này với search_path riêng,
-- thiếu nó là "Database error creating new user" khi đăng ký
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, avatar_url)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'full_name', new.email),
          new.raw_user_meta_data->>'avatar_url');
  return new;
end $$;

create trigger trg_on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

create table library (
  user_id uuid not null references auth.users(id) on delete cascade,
  novel_id bigint not null references novels(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (user_id, novel_id)
);

create table reading_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  novel_id bigint not null references novels(id) on delete cascade,
  chapter_index int not null default 1,
  scroll_offset real not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, novel_id)
);

-- ---------- RPC: user kích hoạt / mở rộng dịch ----------
-- App gọi hàm này khi bấm "Đọc" hoặc khi prefetch (đọc gần hết chương đã dịch)
create or replace function request_translation(p_novel_id bigint, p_up_to int default 10)
returns int
language plpgsql
security definer
as $$
declare
  v_count int := 0;
  r record;
begin
  if auth.uid() is null then
    raise exception 'login required';
  end if;

  for r in
    select c.id from chapters c
    where c.novel_id = p_novel_id
      and c.chapter_index <= p_up_to
      and c.translation_status in ('none', 'failed')
    order by c.chapter_index
  loop
    update chapters set translation_status = 'queued' where id = r.id;
    insert into translation_jobs (type, novel_id, chapter_id, priority)
    values ('chapter', p_novel_id, r.id, 50)
    on conflict do nothing;
    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;

-- ---------- RLS ----------
alter table sources enable row level security;
alter table novels enable row level security;
alter table chapters enable row level security;
alter table comments enable row level security;
alter table translation_jobs enable row level security;
alter table glossary_terms enable row level security;
alter table novel_glossary_version enable row level security;
alter table term_edit_history enable row level security;
alter table profiles enable row level security;
alter table library enable row level security;
alter table reading_progress enable row level security;

-- nội dung: ai cũng đọc được (kể cả anon để duyệt trước khi đăng nhập)
create policy read_sources on sources for select using (true);
create policy read_novels on novels for select using (true);
create policy read_chapters on chapters for select using (true);
create policy read_comments on comments for select using (true);
create policy read_glossary on glossary_terms for select using (approved);
create policy read_glossary_ver on novel_glossary_version for select using (true);

-- user đề xuất term (novel-scope tự áp dụng, global chờ duyệt)
create policy insert_glossary on glossary_terms for insert to authenticated
  with check (created_by = auth.uid() and (scope <> 'global' or approved = false));

create policy own_history on term_edit_history for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy own_profile on profiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy own_library on library for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy own_progress on reading_progress for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- translation_jobs: user không thao tác trực tiếp (chỉ qua RPC / worker service-role)
-- không tạo policy nào → chỉ service role truy cập được

-- ---------- Realtime ----------
-- Bật realtime cho chapters để app thấy chương dịch xong ngay
alter publication supabase_realtime add table chapters;
alter publication supabase_realtime add table novels;
