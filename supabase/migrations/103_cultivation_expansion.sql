-- Migration 103: Mở rộng cảnh giới Tiên/Thánh Đạo (cult_tien_max 9)
-- và Tái cân bằng tu vi luyện hóa vật phẩm (cult_recycle: cấp số nhân theo phẩm).
-- Idempotent, an toàn khi chạy lại.

-- 1. Tối đa 10 bậc cõi Tiên & Thánh Đạo (0..9)
create or replace function cult_tien_max() returns int
language sql immutable as $$
  select 9;
$$;

-- 2. Điểm tu vi yêu cầu cho từng bậc Tiên & Thánh Đạo
-- Bậc 0..6: Tiên Nhân -> Đạo Tổ
-- Bậc 7..9: Hỗn Nguyên Thánh Nhân -> Hồng Mông Chí Tôn -> Hư Vô Đại Đạo Tổ
create or replace function cult_tien_req(p_tier int) returns numeric
language sql immutable as $$
  -- Đỉnh Độ Kiếp ~ 18.000.000 tu vi; mỗi bậc Tiên nhân × 1.6^(tier+1)
  select round(18000000.0 * power(1.6, least(greatest(p_tier, 0), 9) + 1));
$$;

-- 3. Tái cân bằng Luyện hóa vật phẩm dư (qty > 1) -> Linh khí / Tu vi
-- Công thức mới: Cấp số nhân theo độ quý hiếm của phẩm cấp
-- Phẩm 1 (Hoàng): 50
-- Phẩm 2 (Huyền): 300 (x6)
-- Phẩm 3 (Địa):   2,000 (~x6.7)
-- Phẩm 4 (Thiên): 12,000 (x6)
-- Phẩm 5 (Tiên):  80,000 (~x6.7)
-- Phẩm 6+ (Thần): 500,000
create or replace function cult_recycle_gain(p_grade int) returns numeric
language sql immutable as $$
  select case greatest(least(p_grade, 6), 1)
    when 1 then 50
    when 2 then 300
    when 3 then 2000
    when 4 then 12000
    when 5 then 80000
    else 500000
  end;
$$;

create or replace function cult_recycle(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
  v_qty int;
  v_spare int;
  v_per_item numeric;
  v_gain numeric;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  perform cult_tick(uid); -- chốt exp tích lũy trước khi cộng linh khí
  select * into it from cult_items where id = p_item_id;
  if not found then raise exception 'vật phẩm không tồn tại'; end if;

  select qty into v_qty from user_cult_items
    where user_id = uid and item_id = p_item_id;
  v_spare := coalesce(v_qty, 0) - 1; -- luôn chừa 1 bản
  if v_spare < 1 then
    raise exception 'không có bản dư để luyện hóa (cần số lượng > 1)';
  end if;

  v_per_item := cult_recycle_gain(it.grade);
  v_gain := v_spare * v_per_item;

  update user_cult_items set qty = 1
    where user_id = uid and item_id = p_item_id;
  update user_cultivation set exp = exp + v_gain
    where user_id = uid;

  return jsonb_build_object(
    'recycled', v_spare,
    'linh_khi', v_gain,
    'per_item', v_per_item
  );
end $$;

grant execute on function cult_tien_max() to authenticated, anon;
grant execute on function cult_tien_req(int) to authenticated, anon;
grant execute on function cult_recycle_gain(int) to authenticated, anon;
grant execute on function cult_recycle(int) to authenticated;
