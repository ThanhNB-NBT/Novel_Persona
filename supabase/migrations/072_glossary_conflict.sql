alter table glossary_terms
  add column first_chapter int,
  add column hit_count int not null default 0,
  add column conflict_vi text;

alter table novels add column synopsis_vi text;

alter table chapters add column lint_score int;

create or replace function increment_glossary_hits(p_novel_id bigint, p_terms text[])
returns void language sql security definer set search_path = public as $$
  update glossary_terms set hit_count = hit_count + 1
  where novel_id = p_novel_id and term_zh = any(p_terms);
$$;

create or replace function lint_trend(p_novel_id bigint)
returns table(bucket int, avg_lint numeric, n int)
language sql stable security definer set search_path = public as $$
  select ((chapter_index - 1) / 10)::int, avg(lint_score)::numeric, count(*)::int
  from chapters
  where novel_id = p_novel_id and translation_status = 'done' and lint_score is not null
  group by 1 order by 1;
$$;

create or replace function lint_drift_novels(p_ratio numeric default 1.2, p_min_chapters int default 5)
returns table(novel_id bigint, first_avg numeric, last_avg numeric)
language sql stable security definer set search_path = public as $$
  with buckets as (
    select novel_id, ((chapter_index - 1) / 10)::int as bucket,
           avg(lint_score)::numeric as avg_lint, count(*)::int as n
    from chapters
    where translation_status = 'done' and lint_score is not null
    group by novel_id, bucket
  ), ranked as (
    select *, row_number() over (partition by novel_id order by bucket) as first_rank,
           row_number() over (partition by novel_id order by bucket desc) as last_rank
    from buckets
  )
  select first_bucket.novel_id, first_bucket.avg_lint, last_bucket.avg_lint
  from ranked first_bucket
  join ranked last_bucket using (novel_id)
  where first_bucket.first_rank = 1 and last_bucket.last_rank = 1
    and first_bucket.n >= p_min_chapters and last_bucket.n >= p_min_chapters
    and last_bucket.bucket > first_bucket.bucket
    and last_bucket.avg_lint > first_bucket.avg_lint * p_ratio;
$$;
