-- P2b-0 (TẠM): đo latency fetch crawl để quyết có nên song song trong-1-nguồn (P2b) +
-- đặt interval limiter. Worker service_role ghi 1 dòng mỗi ~200 fetch/nguồn; đọc thẳng
-- từ Supabase (khỏi SSH đọc log Docker). Bảng tạm — xong việc thì `drop table crawl_latency;`.
create table if not exists crawl_latency (
  id bigint generated always as identity primary key,
  source text not null,          -- sources.name (shuhaige/ddxs/…)
  n int not null,                -- số fetch trong cửa sổ
  ok int not null,               -- số fetch thành công (có latency)
  p50_s real,
  p95_s real,
  max_s real,
  timeouts int not null default 0,
  http_429 int not null default 0,
  at timestamptz not null default now()
);
create index if not exists crawl_latency_at_idx on crawl_latency (at desc);

-- Query đọc nhanh (Supabase SQL editor):
--   select source, count(*) windows, round(avg(p50_s),1) p50, round(max(p95_s),1) p95_max,
--          sum(timeouts) timeouts, sum(http_429) http_429
--   from crawl_latency where at > now() - interval '1 day' group by source;
