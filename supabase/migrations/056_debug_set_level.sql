-- CÔNG CỤ TEST (admin-only): đặt nhanh realm/stage + tuỳ chọn đầy tu vi, để soi
-- hiệu ứng lên tầng/đột phá/phi thăng mà không phải cày. CHỈ profiles.is_admin gọi được;
-- UI phía app còn chặn thêm ở kDebugMode. Không phải tính năng người chơi.
create or replace function cult_debug_set(
  p_realm int, p_stage int, p_fill boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_realm int := greatest(1, least(coalesce(p_realm, 1), 9));
  v_stage int := greatest(1, least(coalesce(p_stage, 1), 9));
begin
  if auth.uid() is null then raise exception 'chưa đăng nhập'; end if;
  if not exists (select 1 from profiles where id = auth.uid() and is_admin) then
    raise exception 'chỉ admin dùng được công cụ test';
  end if;
  perform cult_tick(auth.uid()); -- đảm bảo có dòng
  update user_cultivation set
    realm = v_realm,
    stage = v_stage,
    exp = case when p_fill then cult_req(v_realm, v_stage) else 0 end,
    bt_bonus_pct = 0,
    ascended_at = null,      -- cho test lại Phi Thăng
    last_tick = now()        -- khỏi cộng bù thời gian ngay sau khi set
  where user_id = auth.uid();
  return cult_state();
end $$;

grant execute on function cult_debug_set(int, int, boolean) to authenticated;
