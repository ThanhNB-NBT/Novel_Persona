-- Nguồn FANQIE (fanqienovel.com, 番茄小说): adapter riêng decode font mã hóa.
-- Khác mọi nguồn HTML tĩnh: metadata/mục lục nằm trong window.__INITIAL_STATE__,
-- nội dung chương chứa ký tự PUA (0xE000–0xF8FF) do font woff2 độc quyền render.
-- Decode bằng bảng tĩnh worker/novelworker/crawler/fanqie_charset.json (362 glyph,
-- so-khớp bitmap với Noto Sans SC; đã sửa tay theo ngữ cảnh: 一/国).
-- Font là TOÀN CỤC dùng chung mọi sách (2 sách khác nhau cùng 1 URL woff2,
-- kiểm chứng 2026-08-22) → bảng tĩnh đủ dùng; ByteDance đổi font thì adapter
-- log cảnh báo (so hash tên file woff2) → cần build lại bảng.
-- Không có search/discovery (trang chủ JS-render) → thêm truyện tay:
--   add --source fanqie --book-id <id từ URL /page/{id}>.
-- Chỉ chương free công khai; live probe hàng chục request không bị chặn.
insert into sources (name, base_url, template, meta_priority, enabled, config)
values ('fanqie', 'https://fanqienovel.com', 'fanqie', 30, true, '{}'::jsonb)
on conflict (name) do update
  set template = excluded.template,
      base_url = excluded.base_url,
      config = excluded.config,
      enabled = true;
