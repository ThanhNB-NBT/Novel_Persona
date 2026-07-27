-- Chọn truyện cần tải bản gốc bằng SQL, thay vì lọc trong Python sau một cửa sổ 200 job.
--
-- Bug đo được 2026-07-27: _novels_needing_fetch lấy 200 job chương pending đầu (theo
-- priority, created_at) rồi mới lọc "chương đang queued và chưa có content_zh". Nhưng
-- 587 job đầu hàng đợi trỏ tới chương ở trạng thái 'none' nên bị loại sạch — job cần
-- tải ĐẦU TIÊN nằm ở vị trí 588. Crawler vì thế thấy danh sách rỗng và không tải gì,
-- trong khi 1377 chương đang queued chờ nội dung. Hachimi không có việc, hàng đợi dịch
-- đứng im ở 1969 job.
--
-- Cửa sổ 200 còn cắt theo nguồn: 200 job đầu toàn shuhaige, nên 5 nguồn còn lại luôn
-- nhận rỗng dù truyện của chúng đang chờ.
--
-- Lọc và phân trang trong SQL thì cả hai vấn đề biến mất, và trả về ít dữ liệu hơn
-- nhiều (mỗi tick chỉ vài chục dòng thay vì 200 job + 200 chapter).

create or replace function novels_needing_fetch(p_source_id smallint, p_limit int default 50)
returns table (id bigint, source_id smallint, source_novel_id text)
language sql
stable
security definer
set search_path = public
as $$
  select n.id, n.source_id, n.source_novel_id
  from translation_jobs j
  join chapters c on c.id = j.chapter_id
  join novels n on n.id = j.novel_id
  where j.type = 'chapter'
    and j.status = 'pending'
    and c.translation_status = 'queued'
    and c.content_zh is null
    and n.source_id = p_source_id
  group by n.id, n.source_id, n.source_novel_id
  order by min(j.priority), min(j.created_at)   -- người đọc chờ vẫn được tải trước
  limit p_limit
$$;

revoke execute on function novels_needing_fetch(smallint, int)
  from public, anon, authenticated;
