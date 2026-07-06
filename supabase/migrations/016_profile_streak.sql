-- Streak đọc: số ngày liên tiếp user có đọc (tính theo giờ VN). Cập nhật qua RPC
-- security definer khi user mở chương → atomic, không cần bảng lịch sử ngày.
alter table profiles add column if not exists streak int not null default 0;
alter table profiles add column if not exists last_read_date date;

create or replace function touch_reading_streak() returns int
language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  last date;
  s int;
begin
  if auth.uid() is null then return 0; end if;
  select last_read_date, streak into last, s from profiles where id = auth.uid();
  if last = today then
    return s;                       -- đã tính hôm nay → giữ nguyên
  elsif last = today - 1 then
    s := coalesce(s, 0) + 1;        -- đọc nối ngày → +1
  else
    s := 1;                         -- đứt chuỗi (hoặc lần đầu) → về 1
  end if;
  update profiles set streak = s, last_read_date = today where id = auth.uid();
  return s;
end $$;

grant execute on function touch_reading_streak() to authenticated;
