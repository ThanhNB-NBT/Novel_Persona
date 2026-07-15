-- FIX [MEDIUM] 2 lỗi hệ Tu Luyện phát sinh khi viết lại hàm:
--   1. cult_use_item (đè 067): bản viết lại cho đa linh căn ĐÁNH RƠI guard chống dùng đan/
--      linh thạch YẾU đè lên buff MẠNH đang chạy (guard này thêm ở 052). Khôi phục guard.
--   2. cult_recycle (đè 053): cộng exp không cap → tick kế (cult_tick least(cap,…)) xén mất
--      phần vượt trần. Chặn luyện hóa khi đã ở bình cảnh/đạt trần exp cảnh giới.

-- 1) cult_use_item: y hệt 067 + khôi phục guard buff/stone (052) trước khi trừ vật phẩm.
create or replace function cult_use_item(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
  c  user_cultivation;
  v_pct int;
  n int;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  perform cult_tick(uid);
  select * into c from user_cultivation where user_id = uid;
  select * into it from cult_items where id = p_item_id;
  if it.type not in ('danduoc', 'linhthach') then
    raise exception 'vật phẩm này không dùng trực tiếp được';
  end if;

  -- Chặn đè buff/linh thạch mạnh hơn đang còn hạn (khôi phục logic 052). Bằng thì cho
  -- dùng để làm mới thời hạn.
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
      if (select variant from user_cultivation where user_id = uid) is not null then
        raise exception 'linh căn dị bẩm — không thể chuyển hệ';
      end if;
      n := (select coalesce(array_length(elements, 1), 1) from user_cultivation where user_id = uid);
      update user_cultivation set elements =
        array(select e from unnest(array['kim', 'moc', 'thuy', 'hoa', 'tho']) e
              order by random() limit n)
      where user_id = uid;
    else raise exception 'vật phẩm lỗi dữ liệu effect';
  end case;
  return cult_state();
end $$;

-- 2) cult_recycle: y hệt 053 + chặn khi exp đã chạm trần cảnh giới hiện tại (không thì
-- linh khí cộng vào bị cult_tick xén mất → mất vật phẩm oan).
create or replace function cult_recycle(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
  c  user_cultivation;
  v_qty int;
  v_spare int;
  v_gain numeric;
  cap numeric;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  c := cult_tick(uid); -- chốt exp tích lũy trước khi cộng linh khí
  select * into it from cult_items where id = p_item_id;
  if not found then raise exception 'vật phẩm không tồn tại'; end if;

  cap := case when c.ascended_at is not null
              then cult_tien_req(least(c.tien_tier, cult_tien_max()))
              else cult_req(c.realm, c.stage) end;
  if c.exp >= cap then
    raise exception 'đang ở bình cảnh/đạt trần tu vi cảnh giới — đột phá trước khi luyện hóa';
  end if;

  select qty into v_qty from user_cult_items
    where user_id = uid and item_id = p_item_id;
  v_spare := coalesce(v_qty, 0) - 1; -- luôn chừa 1 bản
  if v_spare < 1 then
    raise exception 'không có bản dư để luyện hóa (cần số lượng > 1)';
  end if;

  -- linh khí theo phẩm: cố ý NHỎ, chỉ để dọn kho (grade² × 20 mỗi bản).
  v_gain := v_spare * (it.grade * it.grade * 20);

  update user_cult_items set qty = 1
    where user_id = uid and item_id = p_item_id;
  -- vẫn cap để không bao giờ vượt trần (dù đã chặn ở trên, phòng đua tick).
  update user_cultivation set exp = least(cap, exp + v_gain)
    where user_id = uid;

  return jsonb_build_object('recycled', v_spare, 'linh_khi', v_gain);
end $$;
