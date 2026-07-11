-- Luyện hóa bản DƯ (qty > 1) → linh khí → cộng thẳng tu vi. Đóng vòng lặp đồ trùng
-- (quà ~50% chương, rơi đều nên kho nhanh đầy trùng) mà KHÔNG cần shop/tiền tệ/chợ.
-- Luôn giữ lại 1 bản mỗi món (để còn dùng/trang bị/sưu tập). Server là chuẩn.
create or replace function cult_recycle(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
  v_qty int;
  v_spare int;
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

  -- linh khí theo phẩm: cố ý NHỎ, chỉ để dọn kho (grade² × 20 mỗi bản).
  -- Chỉnh hằng ở dòng này nếu muốn cân lại — không đụng chỗ khác.
  v_gain := v_spare * (it.grade * it.grade * 20);

  update user_cult_items set qty = 1
    where user_id = uid and item_id = p_item_id;
  update user_cultivation set exp = exp + v_gain
    where user_id = uid;

  return jsonb_build_object('recycled', v_spare, 'linh_khi', v_gain);
end $$;

grant execute on function cult_recycle(int) to authenticated;
