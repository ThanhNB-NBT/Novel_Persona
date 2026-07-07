-- Nguồn thứ 3: khuôn 新笔趣阁 (adapter XinBiqugeAdapter, template 'xinbiquge').
-- Probe + test live 2026-07-07: mục lục phân trang index_{p}.html (block 最新章节 lặp
-- mọi trang → chỉ parse sau div.book_list2), content <article class="font_max">,
-- junk 第(1/N)页, og:title dính đuôi 最新章节, book_id 2 tầng "107/107771".
-- Ranking /top/ (30 hot) + /full/ (30 hoàn thành) — ít mà chất.

update sources set
  template = 'xinbiquge',
  base_url = 'https://www.xbiquge.com.cn',
  config = '{"novel_path": "/book/{book_id}/", "chapter_path": "/book/{book_id}/{chapter_id}.html"}'::jsonb,
  enabled = true
where name = 'xsbique';

-- uuxs.org cùng khuôn y hệt (đã probe) — cấu hình sẵn nhưng TẮT: nội dung trùng
-- xsbique là chính, bật chỉ khi xsbique chết (đổi enabled rồi restart worker).
update sources set
  template = 'xinbiquge',
  base_url = 'https://www.uuxs.org',
  config = '{"novel_path": "/book/{book_id}/", "chapter_path": "/book/{book_id}/{chapter_id}.html"}'::jsonb,
  enabled = false
where name = 'uuxs';
