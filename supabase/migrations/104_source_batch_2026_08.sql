-- Mở rộng nguồn 2026-08-22: bật 2 nguồn đã kiểm chứng live + thêm 2 nguồn mới.
-- Probe thật 2026-08-22 bằng chính adapter của repo (curl_cffi impersonate chrome):
--   ptwxz      piaotia.com  : meta 傲世九重天 + TOC 2694 chương + nội dung chương OK
--   69shuba    69shuba.com  : og:novel:* đầy đủ + TOC 1431 chương + nội dung OK
--   xslou      xslou.net    : khuôn xinbiquge chuẩn — book /{a}/{bid}/ 2 tầng, mục lục
--                             phân trang index_{p}.html, content article.font_max,
--                             ranking /top/ + /full/. Probe meta+TOC+chương OK.
--   qiushubang xqiushubang.com: biquge biến thể — book /index/{id}/, mục lục phân trang
--                             /index/{id}/{p}/ (khối section-box CUỐI = danh sách đầy đủ
--                             tăng dần, khối đầu lặp "mới nhất" → toc_split cắt),
--                             chương /read/{id}/{cid}.html div#content; watermark tên
--                             site xáo trộn ký tự lạ nhồi giữa văn → junk_re xoá.
-- Discovery qiushubang: không có route ranking/mới-cập nhật dùng được (/top/, /allvisit/,
-- /lastupdate/ đều 404) → không khai latest_path/ranking_path để các pool đó TẮT sạch,
-- nguồn dùng qua search/add tay. xslou discovery qua fetch_ranking (/top/, /full/) sẵn có.

update sources set enabled = true where name in ('ptwxz', '69shuba');

-- Conditional GET cho soi mục lục (probe thật + live 2 lần liên tiếp 2026-08-22):
--   69shuba (ETag tĩnh) + ptwxz (Last-Modified tĩnh từ 2024) đều 304 đúng, nhanh hơn
--   10-13x với 0 byte body. qiushubang trả Last-Modified ĐỘNG theo từng request
--   (If-Modified-Since không bao giờ khớp) → KHÔNG bật. ddxs/xslou không có header.
alter table novels add column if not exists toc_etag text;
alter table novels add column if not exists toc_last_modified text;

update sources set config = coalesce(config, '{}'::jsonb) || '{"conditional_toc": true}'::jsonb
  where name in ('ptwxz', '69shuba');

insert into sources (name, base_url, template, meta_priority, enabled, config) values
  ('xslou', 'https://www.xslou.net', 'xinbiquge', 30, true,
   '{"novel_path": "/{book_id}/", "chapter_path": "/{book_id}/{chapter_id}.html", "ranking_link_re": "href=\"/(\\d+/\\d+)/\""}'::jsonb)
on conflict (name) do update
  set template = excluded.template,
      base_url = excluded.base_url,
      config = excluded.config;

insert into sources (name, base_url, template, meta_priority, enabled, config) values
  ('qiushubang', 'https://www.xqiushubang.com', 'biquge', 30, true,
   '{"novel_path": "/index/{book_id}/", "chapter_path": "/read/{book_id}/{chapter_id}.html", "toc_page_path": "/index/{book_id}/{page}/", "toc_split": "<div class=\"section-box\">", "toc_max_pages": 60, "junk_re": ["[一-龥](?:[^\\s一-龥，。！？…、；：“”‘’（）《》—]{1,4}[一-龥]){3,}", "[^\\s一-龥，。！？…、；：“”‘’（）《》—0-9a-zA-Z]{2,}", "(?:[^\\w\\s一-龥，。！？…、；：“”‘’（）《》—]\\w{1,3}){4,}[^\\w\\s一-龥，。！？…、；：“”‘’（）《》—]?", "[^\\s一-龥，。！？…、；：“”‘’（）《》—]{1,4}首[^\\s一-龥，。！？…、；：“”‘’（）《》—]{1,4}发[^\\s一-龥，。！？…、；：“”‘’（）《》—]{0,4}"]}'::jsonb)
on conflict (name) do update
  set template = excluded.template,
      base_url = excluded.base_url,
      config = excluded.config;
