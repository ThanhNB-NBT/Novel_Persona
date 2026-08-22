-- Cột updated_at cho chapters: mốc "bản dịch đổi lần cuối" để app phát hiện bản
-- offline đã stale (trước đây chương tải về máy không bao giờ nhận bản sửa/dịch lại).
-- Mọi UPDATE (worker finalize, edit_chapter_vi, patch glossary, retry...) đều đụng mốc.
-- Idempotent: add column if not exists + drop trigger/function trước khi tạo.

alter table chapters add column if not exists updated_at timestamptz not null default now();

-- Backfill theo translated_at (chính xác hơn created_at với chương đã dịch);
-- chương chưa dịch thì giữ default now() — không ai đọc nội dung nó đâu.
update chapters set updated_at = coalesce(translated_at, created_at)
where updated_at = now();

create or replace function touch_chapter_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_touch_chapter on chapters;
create trigger trg_touch_chapter before update on chapters
  for each row execute function touch_chapter_updated_at();
