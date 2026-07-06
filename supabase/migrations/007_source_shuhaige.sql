-- Nguồn 2: 书海阁 (shuhaige.net) — web đọc free mở toàn bộ chương, không Cloudflare.
-- Dùng cho truyện Fanqie khóa VIP (Fanqie web chỉ mở 10 chương/truyện).
insert into sources (name, base_url) values
  ('shuhaige', 'https://www.shuhaige.net')
on conflict (name) do nothing;
