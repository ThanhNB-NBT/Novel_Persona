-- 049: "Thiên Đạo sủng nhi" — cơ duyên dày hơn và rơi đồ thuần ngẫu nhiên.
-- 1) Chương có quà: 30% → 50% (client Dart mirror trong cultivation.dart giftAt).
-- 2) cult_claim_gift: BỎ khoá phẩm theo cảnh giới (gmax) + BỎ trọng số weight —
--    mọi vật phẩm trong catalog rơi với xác suất NGANG NHAU, Luyện Khí cũng có
--    thể nhặt được Tiên phẩm nếu trời thương.

create or replace function cult_gift_at(p_uid uuid, p_novel_id bigint, p_index int) returns boolean
language sql immutable as $$
  select ('x00' || substr(md5(p_uid::text || ':' || p_novel_id || ':' || p_index), 1, 6))::bit(32)::int % 100 < 50;
$$;

create or replace function cult_claim_gift(p_novel_id bigint, p_index int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  if not cult_gift_at(uid, p_novel_id, p_index) then
    raise exception 'chương này không có quà';
  end if;
  perform cult_tick(uid);

  select * into it from cult_items order by random() limit 1;

  insert into cult_claims (user_id, novel_id, chapter_index, item_id)
  values (uid, p_novel_id, p_index, it.id); -- PK chặn nhận trùng → lỗi duplicate

  insert into user_cult_items (user_id, item_id, qty) values (uid, it.id, 1)
  on conflict (user_id, item_id) do update set qty = user_cult_items.qty + 1;

  return to_jsonb(it);
end $$;
