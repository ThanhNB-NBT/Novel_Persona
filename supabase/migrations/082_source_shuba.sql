-- Nguồn 69书吧 (69shuba.com): khuôn RIÊNG 'shuba' (GBK, og:novel:* đầy đủ, mục lục
-- xếp giảm dần theo data-num). Probe thật 2026-07-25: trang truyện /book/{id}.htm,
-- mục lục /book/{id}/ (1 trang, đủ 569 chương), chương /txt/{id}/{cid} (div.txtnav).
-- Bật THỬ: enabled=false — user tự bật sau khi chạy live 1 chu kỳ thấy ổn.
-- config.encoding=gbk để base._get decode đúng.
insert into sources (name, base_url, template, meta_priority, enabled, config)
values ('69shuba', 'https://www.69shuba.com', 'shuba', 20, false, '{"encoding": "gbk"}'::jsonb)
on conflict (name) do update
  set template = excluded.template,
      base_url = excluded.base_url,
      config = excluded.config;
