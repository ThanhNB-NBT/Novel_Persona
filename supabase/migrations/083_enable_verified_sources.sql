-- Bật các nguồn ĐÃ chạy thật end-to-end ngày 2026-07-25 (latest → meta → TOC → chương
-- đầu/giữa/cuối, text sạch không lẫn tag/quảng cáo). Trước đó 081/082 seed ở trạng thái
-- tắt để chờ kiểm chứng; giờ đã có số liệu nên bật.
--
--   ptwxz    2694 chương/truyện mẫu — cần vá bóc nội dung (</H1> HOA + khối điều hướng)
--   69shuba   569 chương/truyện mẫu — cần header Referer, nếu không /txt/ trả 403
--   quanben5 1302 chương/truyện mẫu — KHÔNG cần khuôn mới: dùng lại template dingdian,
--            chỉ khác content_class + discover_paths (đổi từ khuôn 'biquge' đang sai)
--
-- KHÔNG bật (đo 2026-07-25, đừng thử lại nếu chưa có gì đổi):
--   biqulao  site sống nhưng ID hai tầng /{a}/{bid}/ + nội dung ở class thay vì id →
--            lệch khuôn biquge; và nó là mirror gần trùng shuhaige nên giá trị thêm thấp
--   uuxs     SSL: connection reset ở tầng mạng
--   xsbique  DNS/TCP không kết nối được (fail_count đã 5, ok lần cuối 2026-07-10)
--   fanqie / qidian / jjwxc — VIP + chống bot, đã chốt loại từ trước

update sources
  set enabled = true
  where name in ('ptwxz', '69shuba');

-- quanben5: chuyển sang khuôn dingdian (/n/{slug}/ + mục lục xiaoshuo.html) rồi bật.
update sources
  set template = 'dingdian',
      enabled  = true,
      -- category: 1 玄幻, 3 仙侠, 4 武侠, 6 穿越, 7 网游, 8 奇幻, 9 科幻, 10 悬疑.
      -- Bỏ 2 都市 / 5 言情 / 11 青春 / 12 校园 / 13 军事 / 14 历史 / 15 同人 — genre_blocked()
      -- chặn sẵn nên cào vào chỉ tốn request rồi bị loại.
      config   = '{"content_class": "content",
                   "discover_paths": ["/category/1.html", "/category/3.html",
                                      "/category/4.html", "/category/6.html",
                                      "/category/7.html", "/category/8.html",
                                      "/category/9.html", "/category/10.html"]}'::jsonb
  where name = 'quanben5';
