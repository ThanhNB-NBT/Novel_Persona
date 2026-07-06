-- Đa nguồn: adapter theo KHUÔN (template) nạp động từ DB + chống trùng truyện (dedup).

-- ---------- sources: khuôn + cấu hình + độ ưu tiên + sức khoẻ (health để dành Pha 5) ----------
alter table sources add column if not exists template text not null default 'biquge';
alter table sources add column if not exists config jsonb not null default '{}';
alter table sources add column if not exists meta_priority int not null default 100; -- nhỏ = metadata ưu tiên khi trùng
alter table sources add column if not exists fallback_domains text[] not null default '{}';
alter table sources add column if not exists last_ok_at timestamptz;
alter table sources add column if not exists fail_count int not null default 0;

-- ---------- novels: chống trùng ----------
alter table novels add column if not exists dedup_key text;
alter table novels add column if not exists is_canonical boolean not null default true;
create index if not exists idx_novels_dedup on novels (dedup_key);
create index if not exists idx_novels_canonical on novels (is_canonical) where is_canonical;

-- ---------- seed nguồn ----------
-- shuhaige (đang dùng) chuyển sang khuôn biquge, ưu tiên metadata cao.
insert into sources (name, base_url, template, meta_priority, config) values
  ('shuhaige', 'https://www.shuhaige.net', 'biquge', 10, '{}'::jsonb)
on conflict (name) do update
  set template = 'biquge', meta_priority = 10;

-- Nhóm "Có" từ khảo sát — seed SẴN nhưng TẮT (enabled=false). Bật + tinh chỉnh config
-- sau khi test crawl thật từng nguồn (selector/latest_path có thể lệch nhẹ giữa các clone).
insert into sources (name, base_url, template, meta_priority, enabled, config) values
  ('biqulao',  'https://www.biqulo.com',            'biquge', 20, false, '{}'::jsonb),
  ('xsbique',  'https://www.xbiquge.com.cn',        'biquge', 20, false, '{}'::jsonb),
  ('ddxs',     'https://www.dingdian-xiaoshuo.com', 'biquge', 20, false, '{}'::jsonb),
  ('uuxs',     'https://uuxs.org',                  'biquge', 20, false, '{}'::jsonb),
  ('quanben5', 'https://quanben5.com',              'biquge', 20, false, '{}'::jsonb)
on conflict (name) do nothing;

-- fanqie/qidian/jjwxc (seed cũ ở 001) không có adapter khuôn biquge → tắt để build_adapters bỏ qua.
update sources set enabled = false where name in ('fanqie', 'qidian', 'jjwxc');
