-- Xoá hẳn 3 nguồn đã đo chết ngày 2026-07-25, khỏi lởn vởn trong bảng gây nhiễu:
--   biqulao  site sống nhưng lệch khuôn (ID hai tầng /{a}/{bid}/, nội dung ở class
--            thay vì id) VÀ là mirror gần trùng shuhaige → giá trị thêm ~0
--   uuxs     SSL connection reset ở tầng mạng
--   xsbique  DNS/TCP không nối được (fail_count=5, ok lần cuối 2026-07-10)
--
-- An toàn: chỉ xoá khi CHƯA có truyện nào trỏ vào — nếu lỡ có dữ liệu thật thì
-- giữ nguyên và chỉ tắt, để không kéo theo novels/chapters qua khoá ngoại.
update sources set enabled = false
  where name in ('biqulao', 'uuxs', 'xsbique');

delete from sources s
  where s.name in ('biqulao', 'uuxs', 'xsbique')
    and not exists (select 1 from novels n where n.source_id = s.id);

-- fanqie/qidian/jjwxc GIỮ LẠI ở trạng thái tắt: chúng là seed lịch sử từ 001, xoá đi
-- thì lần chạy migration cũ nào đó có thể seed lại và tưởng là nguồn mới chưa test.
