-- MỤC LỤC LƯỜI: 490 truyện discovery kéo theo 860k dòng stub chương (202MB = 92% DB)
-- trong khi mới đọc thật ~560 chương. Từ nay truyện chưa ai đụng chỉ giữ 3 chương mẫu
-- + chapter_count_source; mở trang truyện thì app gọi request_toc → crawler tải đủ.
--
-- toc_synced_at NOT NULL  = truyện giữ mục lục ĐẦY ĐỦ (worker refresh như cũ)
-- toc_requested_at        = app xin tải mục lục, crawler xử lý rồi set toc_synced_at

alter table novels
  add column if not exists toc_requested_at timestamptz,
  add column if not exists toc_synced_at timestamptz;

-- Truyện đã "động tới" → giữ mục lục đầy đủ: trong tủ sách / có tiến độ đọc /
-- có chương ngoài nhóm mẫu từng được tải-dịch (chương mẫu 1-3 dịch sẵn lúc discovery
-- không tính là đọc thật → mốc >10 cho chắc).
update novels n set toc_synced_at = now()
where exists (select 1 from library l where l.novel_id = n.id)
   or exists (select 1 from reading_progress rp where rp.novel_id = n.id)
   or exists (select 1 from chapters c where c.novel_id = n.id
              and c.chapter_index > 10
              and (c.content_zh is not null or c.translation_status <> 'none'));

-- App bấm vào truyện lười → xin mục lục. Không cần auth (đồng bộ với request_translation).
create or replace function request_toc(p_novel_id bigint)
returns void
language sql
security definer
as $$
  update novels set toc_requested_at = now()
  where id = p_novel_id and toc_synced_at is null;
$$;

-- DỌN: xoá stub trống của truyện lười (giữ mọi dòng có nội dung hoặc đã vào hàng đợi).
-- 850k dòng một phát → vượt statement_timeout mặc định; nới trong transaction này.
set local statement_timeout = '30min';

delete from chapters c
using novels n
where n.id = c.novel_id
  and n.toc_synced_at is null
  and c.content_zh is null
  and c.translation_status = 'none';

-- Lưu ý: chạy `vacuum full chapters;` trong SQL Editor sau migration này để trả đĩa
-- về hệ thống (VACUUM không chạy được trong transaction của migration).
