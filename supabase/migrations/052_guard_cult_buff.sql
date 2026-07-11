-- Chặn dùng đan/linh thạch YẾU đè lên buff MẠNH đang chạy (đè cult_use_item ở 043).
-- Từ chối phía server: không client nào bỏ qua được, và không tiêu mất món (raise rollback).
-- Bằng > (strictly): buff cùng mức vẫn cho dùng để làm mới thời hạn.
create or replace function cult_use_item(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
  c  user_cultivation;
  v_pct int;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  perform cult_tick(uid); -- chốt exp theo buff/hệ cũ trước khi đổi
  select * into c from user_cultivation where user_id = uid;
  select * into it from cult_items where id = p_item_id;
  if it.type not in ('danduoc', 'linhthach') then
    raise exception 'vật phẩm này không dùng trực tiếp được';
  end if;

  v_pct := (it.effect->>'pct')::int;
  if it.effect->>'kind' = 'buff' and c.buff_until > now() and c.buff_pct > v_pct then
    raise exception 'đang có đan tăng tốc mạnh hơn (+% phần trăm) — để dành món này', c.buff_pct;
  end if;
  if it.effect->>'kind' = 'stone' and c.stone_until > now() and c.stone_pct > v_pct then
    raise exception 'đang có linh thạch mạnh hơn (+% phần trăm) — để dành món này', c.stone_pct;
  end if;

  update user_cult_items set qty = qty - 1
  where user_id = uid and item_id = p_item_id and qty > 0;
  if not found then raise exception 'không có vật phẩm này trong kho'; end if;

  case it.effect->>'kind'
    when 'linhcan' then
      update user_cultivation set linh_can = linh_can + (it.effect->>'add')::int
      where user_id = uid;
    when 'buff' then
      update user_cultivation set buff_pct = v_pct,
        buff_until = now() + ((it.effect->>'hours')::numeric || ' hours')::interval
      where user_id = uid;
    when 'stone' then
      update user_cultivation set stone_pct = v_pct,
        stone_until = now() + ((it.effect->>'hours')::numeric || ' hours')::interval
      where user_id = uid;
    when 'hothan' then
      update user_cultivation set bt_bonus_pct = greatest(bt_bonus_pct, (it.effect->>'pct')::int)
      where user_id = uid;
    when 'element' then
      update user_cultivation u set element = (
        select e from unnest(array['kim', 'moc', 'thuy', 'hoa', 'tho']) e
        where e <> u.element order by random() limit 1)
      where user_id = uid;
    else raise exception 'vật phẩm lỗi dữ liệu effect';
  end case;
  return cult_state();
end $$;
