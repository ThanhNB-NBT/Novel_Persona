-- Nguồn 飘天文学 (ptwxz, piaotia.com): khuôn RIÊNG 'piaotia' (trang GBK cũ, ID cặp {a}/{bid}).
-- Adapter còn thô (mục lục 1 trang, content cắt sau </h1>) nên BẬT THỬ: enabled=false,
-- user tự bật khi kiểm chứng live. config.encoding=gbk để base._get decode đúng.
insert into sources (name, base_url, template, meta_priority, enabled, config)
values ('ptwxz', 'https://www.piaotia.com', 'piaotia', 20, false, '{"encoding": "gbk"}'::jsonb)
on conflict (name) do update
  set template = excluded.template,
      base_url = excluded.base_url,
      config = excluded.config;
