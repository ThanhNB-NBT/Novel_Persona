-- Tâm Ma khảo nghiệm khi ĐỘT PHÁ ĐẠI CẢNH GIỚI (stage 9 → realm+1). Đè cult_advance ở 044.
-- Server tính MỘT LẦN từ 5 chỉ số (không combat theo lượt):
--   * mức "vũ trang" = (atk+def+hp+agi có đồ) / (bare tay không) — tự co giãn theo cảnh giới,
--     thưởng người chịu khó trang bị (tận dụng hệ vật phẩm sẵn có).
--   * thần thức trội (Linh tộc ×1.3) = đạo tâm chống tâm ma.
-- Thắng → +15% tỷ lệ đột phá và giảm NỬA tổn thất khi hỏng. Thua → đột phá thường,
-- KHÔNG khóa tiến trình (app đọc truyện, tránh gây ức chế). Lên tầng thường: không có tâm ma.
create or replace function cult_advance() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  c user_cultivation;
  req numeric;
  chance int;
  ok boolean;
  v_def numeric;
  v_loss numeric;
  stats jsonb;
  base numeric;
  geared numeric;
  mind numeric;
  tm_chance int;
  tm_win boolean := false;
  tm jsonb := null;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  c := cult_tick(uid);
  req := cult_req(c.realm, c.stage);
  if c.exp < req then raise exception 'chưa đủ tu vi'; end if;

  if c.stage < 9 then
    update user_cultivation set stage = stage + 1, exp = 0 where user_id = uid;
    return jsonb_build_object('success', true, 'chance', 100,
      'realm', c.realm, 'stage', c.stage + 1);
  end if;

  if c.realm >= 9 then raise exception 'đã tới đỉnh Độ Kiếp — chờ phi thăng'; end if;

  chance := least(100, greatest(10, 85 - 8 * (c.realm - 1) + c.bt_bonus_pct
    + coalesce((select (effect->>'bt_pct')::int from cult_items where id = c.equip_phapchu), 0)
    + case c.race when 'nhan' then 5 when 'ma' then -5 else 0 end));

  -- === Tâm Ma khảo nghiệm (chỉ đại cảnh giới) =================================
  stats := cult_stats(c);
  base := power(1.12, (c.realm - 1) * 9 + c.stage - 1); -- khớp cult_stats
  geared := (stats->>'atk')::numeric + (stats->>'def')::numeric
          + (stats->>'hp')::numeric + (stats->>'agi')::numeric;
  mind := (stats->>'than_thuc')::numeric / (11 * base); -- 1.0 thường, ~1.3 Linh tộc
  -- 35% nền + thưởng vũ trang (geared/bare − 1) + thưởng đạo tâm; kẹp [15,90].
  -- Hằng số là heuristic — chỉnh 3 hệ số dưới nếu cân lại, không đụng chỗ khác.
  tm_chance := round(35 + 45 * (geared / (87 * base) - 1) + 25 * (mind - 1));
  tm_chance := least(90, greatest(15, tm_chance));
  tm_win := random() * 100 < tm_chance;
  if tm_win then
    chance := least(100, greatest(10, chance + 15)); -- áp chế tâm ma → dễ đột phá hơn
  end if;
  tm := jsonb_build_object('win', tm_win, 'chance', tm_chance);
  -- ===========================================================================

  ok := random() * 100 < chance;

  if ok then
    update user_cultivation set realm = realm + 1, stage = 1, exp = 0, bt_bonus_pct = 0
    where user_id = uid;
  else
    -- mất 30% req, giảm theo phòng ngự (trần giảm 50%); Linh tộc chỉ mất nửa;
    -- thắng Tâm Ma cũng giảm nửa tổn thất
    v_def := (stats->>'def')::numeric;
    v_loss := 0.30 * (1 - least(0.5, v_def / (v_def + 1000)))
      * case when c.race = 'linh' then 0.5 else 1 end
      * case when tm_win then 0.5 else 1 end;
    update user_cultivation set exp = greatest(0, exp - req * v_loss), bt_bonus_pct = 0
    where user_id = uid;
  end if;
  return jsonb_build_object('success', ok, 'chance', chance,
    'realm', case when ok then c.realm + 1 else c.realm end,
    'stage', case when ok then 1 else 9 end,
    'tamma', tm);
end $$;
