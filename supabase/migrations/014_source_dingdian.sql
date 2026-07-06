-- Nguồn 顶点小说 (ddxs, dingdian-xiaoshuo.com): khuôn RIÊNG 'dingdian' (không phải biquge).
-- Probe thật 2026-07-04: mục lục đầy đủ 1→N ở /n/{slug}/xiaoshuo.html, nội dung sạch
-- (div.articlebody, không phân trang). book_id = SLUG chữ (vd 'niwen_2').
-- 4 nguồn còn lại nhóm "Có" (biqulao/quanben5/uuxs/xsbique) vẫn tắt: lệch khuôn nặng
-- (mục lục bị cắt / phân trang chương / hạ tầng chập chờn) — xem docs-crawl-multisource.md.
update sources
  set template = 'dingdian', base_url = 'https://www.dingdian-xiaoshuo.com', enabled = true
  where name = 'ddxs';

-- phòng khi 013 chưa chạy (idempotent)
insert into sources (name, base_url, template, meta_priority, enabled, config)
values ('ddxs', 'https://www.dingdian-xiaoshuo.com', 'dingdian', 20, true, '{}'::jsonb)
on conflict (name) do update
  set template = 'dingdian', base_url = excluded.base_url, enabled = true;
