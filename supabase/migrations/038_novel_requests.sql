-- Yêu cầu truyện: user nhập tên tiếng Trung trong Tủ truyện → worker tìm trên các
-- nguồn có search (shuhaige, xsbique; ddxs render JS nên chịu) → crawl như thêm tay,
-- tự bỏ vào tủ sách người xin. Truyện hiển thị chung ở Khám phá như mọi truyện.

create table novel_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  query text not null check (char_length(query) between 1 and 100),
  status text not null default 'pending',  -- pending | done | notfound | failed
  novel_id bigint references novels(id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);
create index idx_novel_requests_pending on novel_requests (created_at) where status = 'pending';

alter table novel_requests enable row level security;
create policy own_requests on novel_requests for select to authenticated
  using (user_id = auth.uid());
create policy insert_own_request on novel_requests for insert to authenticated
  with check (user_id = auth.uid());
create policy delete_own_request on novel_requests for delete to authenticated
  using (user_id = auth.uid());
