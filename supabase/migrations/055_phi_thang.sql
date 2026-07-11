-- Phi Thăng: kết thúc tiến trình hiện tại (KHÔNG mở thêm cảnh giới). Yêu cầu Độ Kiếp
-- tầng 9 đầy tu vi + THẮNG một trận Tâm Ma cuối. Giữ nguyên nhân vật + kho đồ, ghi
-- ascended_at, nhận danh hiệu Tiên Nhân. exp đã bị chặn ở bình cảnh (cult_tick) nên
-- hậu phi thăng không cộng tu vi vô hạn — không cần đụng tick.
alter table user_cultivation add column if not exists ascended_at timestamptz;

-- cult_state: bổ sung ascended_at (đè bản 046).
create or replace function cult_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c user_cultivation;
begin
  if auth.uid() is null then raise exception 'chưa đăng nhập'; end if;
  c := cult_tick(auth.uid());
  return jsonb_build_object(
    'realm', c.realm, 'stage', c.stage, 'exp', c.exp,
    'req', cult_req(c.realm, c.stage),
    'linh_can', c.linh_can,
    'element', c.element,
    'race', c.race,
    'gender', c.gender,
    'ascended_at', c.ascended_at,
    'stats', cult_stats(c),
    'buff_pct', c.buff_pct, 'buff_until', c.buff_until,
    'stone_pct', c.stone_pct, 'stone_until', c.stone_until,
    'bt_bonus_pct', c.bt_bonus_pct,
    'rate', cult_base_rate(c)
      * (1 + (case when c.buff_until > now() then c.buff_pct else 0 end
            + case when c.stone_until > now() then c.stone_pct else 0 end) / 100.0),
    'equipped', (select coalesce(jsonb_object_agg(i.type, to_jsonb(i)), '{}'::jsonb)
      from cult_items i
      where i.id in (c.equip_congphap, c.equip_vukhi, c.equip_phapbao,
                     c.equip_phapchu, c.equip_yphuc, c.equip_giay))
  );
end $$;

-- Phi Thăng: dùng lại công thức Tâm Ma đại cảnh giới (054). PHẢI thắng mới phi thăng;
-- thua → không đổi gì, thử lại (app đọc truyện, không phạt cái kết).
create or replace function cult_ascend() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  c user_cultivation;
  req numeric;
  stats jsonb;
  base numeric;
  geared numeric;
  mind numeric;
  tm_chance int;
  tm_win boolean;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  c := cult_tick(uid);
  if c.ascended_at is not null then raise exception 'đã phi thăng rồi'; end if;
  if c.realm < 9 or c.stage < 9 then
    raise exception 'phải tới Độ Kiếp tầng 9 mới phi thăng được';
  end if;
  req := cult_req(c.realm, c.stage);
  if c.exp < req then raise exception 'chưa đủ tu vi để phi thăng'; end if;

  stats := cult_stats(c);
  base := power(1.12, (c.realm - 1) * 9 + c.stage - 1);
  geared := (stats->>'atk')::numeric + (stats->>'def')::numeric
          + (stats->>'hp')::numeric + (stats->>'agi')::numeric;
  mind := (stats->>'than_thuc')::numeric / (11 * base);
  tm_chance := least(90, greatest(15,
    round(35 + 45 * (geared / (87 * base) - 1) + 25 * (mind - 1))));
  tm_win := random() * 100 < tm_chance;

  if tm_win then
    update user_cultivation set ascended_at = now() where user_id = uid;
  end if;

  return jsonb_build_object(
    'ascended', tm_win,
    'tamma', jsonb_build_object('win', tm_win, 'chance', tm_chance));
end $$;

grant execute on function cult_ascend() to authenticated;
