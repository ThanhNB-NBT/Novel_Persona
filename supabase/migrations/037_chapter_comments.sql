-- Bình luận chương: nhóm bạn đọc chung thả cảm nghĩ ở cuối chương, người đọc sau
-- tới chương đó thì thấy. (Bảng `comments` cũ là chỗ chứa bình luận CÀO TỪ NGUỒN —
-- không dùng cho user thật.)

create table chapter_comments (
  id bigint generated always as identity primary key,
  novel_id bigint not null references novels(id) on delete cascade,
  chapter_index int not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  -- snapshot tên lúc đăng: profiles chỉ cho đọc hàng của chính mình (RLS own_profile)
  -- nên không join lấy tên người khác được; tên đổi sau đó thì comment giữ tên cũ, chấp nhận.
  display_name text,
  content text not null check (char_length(content) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index idx_chapter_comments on chapter_comments (novel_id, chapter_index, created_at);

alter table chapter_comments enable row level security;
-- đọc mở cho tất cả (đọc truyện không cần đăng nhập thì đọc bình luận cũng vậy)
create policy read_chapter_comments on chapter_comments for select using (true);
create policy insert_own_comment on chapter_comments for insert to authenticated
  with check (user_id = auth.uid());
-- xoá: chủ comment hoặc admin
create policy delete_own_comment on chapter_comments for delete to authenticated
  using (user_id = auth.uid() or is_admin());
