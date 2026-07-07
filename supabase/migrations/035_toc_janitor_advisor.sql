-- 1) JANITOR MỤC LỤC LƯỜI: truyện đã tải mục lục đầy đủ nhưng bị bỏ đọc lâu ngày
--    → trả về dạng lười như lúc mới crawl (xoá stub trống, giữ mọi chương có nội dung
--    nên tiến độ đọc cũ vẫn trỏ đúng; quay lại đọc thì request_toc tải lại).
-- 2) Vá warning Supabase Advisor: pin search_path + thu hồi EXECUTE các hàm nội bộ.

-- ---------- 1) Janitor ----------
create or replace function janitor_lazy_toc() returns int
language plpgsql security definer set search_path = public as $$
declare n_reset int;
begin
  with idle as (
    -- "bỏ đọc": không ai lưu tủ sách + không xin mục lục + không đọc trong 7 ngày
    -- (toc_synced_at bị worker bump mỗi lần refresh nên KHÔNG dùng làm mốc)
    select n.id from novels n
    where n.toc_synced_at is not null
      and not exists (select 1 from library l where l.novel_id = n.id)
      and coalesce(n.toc_requested_at, '-infinity') < now() - interval '7 days'
      and coalesce((select max(rp.updated_at) from reading_progress rp
                    where rp.novel_id = n.id), '-infinity') < now() - interval '7 days'
  ), del as (
    delete from chapters c using idle
    where c.novel_id = idle.id
      and c.content_zh is null and c.translation_status = 'none'
  )
  update novels set toc_synced_at = null, toc_requested_at = null
  where id in (select id from idle);
  get diagnostics n_reset = row_count;
  return n_reset;
end $$;
revoke execute on function janitor_lazy_toc() from public, anon, authenticated;

-- chạy đêm 2:30 giờ VN (19:30 UTC), pg_cron sẵn trên Supabase
create extension if not exists pg_cron;
select cron.schedule('janitor-lazy-toc', '30 19 * * *', 'select janitor_lazy_toc()');

-- ---------- 2a) Pin search_path (lint 0011) ----------
alter function claim_next_job(text)                          set search_path = public;
alter function request_translation(bigint, integer)          set search_path = public;
alter function request_translation(bigint, integer, integer) set search_path = public;
alter function request_patch(bigint)                         set search_path = public;
alter function retranslate_chapter(bigint, integer)          set search_path = public;
alter function retranslate_all(bigint)                       set search_path = public;
alter function request_audit()                               set search_path = public;
alter function reset_orphan_chapters()                       set search_path = public;
alter function admin_retry_all_failed()                      set search_path = public;
alter function request_toc(bigint)                           set search_path = public;

-- ---------- 2b) Thu hồi EXECUTE (lint 0028/0029) ----------
-- Hàm chỉ worker (service_role) gọi — client không có việc gì ở đây.
revoke execute on function claim_next_job(text) from public, anon, authenticated;
revoke execute on function bump_model_health(text, integer, boolean, text)
  from public, anon, authenticated;
revoke execute on function reset_orphan_chapters() from public, anon, authenticated;
-- Hàm trigger — chạy qua trigger, không ai cần gọi thẳng qua REST.
revoke execute on function handle_new_user()          from public, anon, authenticated;
revoke execute on function guard_is_admin()           from public, anon, authenticated;
revoke execute on function bump_glossary_version()    from public, anon, authenticated;
revoke execute on function novels_delete_blacklist()  from public, anon, authenticated;
-- rls_auto_enable tạo tay ngoài migration — thu hồi nếu có, không có thì thôi
do $$ begin
  execute 'revoke execute on function rls_auto_enable() from public, anon, authenticated';
exception when undefined_function then null; end $$;
-- Hàm admin (đã tự chặn is_admin() bên trong) — chặn thêm anon cho sạch advisor.
revoke execute on function admin_retry_all_failed() from anon;
revoke execute on function admin_retry_job(bigint)  from anon;
revoke execute on function admin_token_usage()      from anon;
revoke execute on function request_audit()          from anon;

-- Còn lại KHÔNG đụng (chủ đích của app, advisor kêu vẫn kệ):
-- - request_translation / request_patch / retranslate_* / request_toc / edit_chapter_vi:
--   đọc + góp sửa không cần đăng nhập là thiết kế của app.
-- - RLS glossary_terms USING(true) cho authenticated: cộng đồng cùng sửa glossary.
-- - Leaked password protection: bật tay trong Dashboard → Auth → Passwords (không phải SQL).
