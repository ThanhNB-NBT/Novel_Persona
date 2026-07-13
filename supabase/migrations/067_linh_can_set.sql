-- Đại tu hệ LINH CĂN: bỏ mô hình "1 hệ + linh_can là bậc" (thiếu nhất quán — Ngũ Hành
-- Tạp Căn mà chỉ hiện 1 hệ, Tẩy Tủy Đan lại đổi luôn TÊN bậc). Mô hình mới:
--   • elements text[]  — BỘ HỆ ngũ hành CỐ ĐỊNH trời định lúc khởi tạo (1..5 hệ).
--   • variant text     — dị/thiên linh căn (null = linh căn thường theo số hệ).
--   • linh_can (giữ)   — nay là MỨC LUYỆN CĂN (refine): Tẩy Tủy Đan +1, CHỈ tăng tốc,
--                        KHÔNG đổi hệ/không đổi tên bậc.
-- Tên bậc = số hệ (5 Ngũ Hành Tạp → 1 Đơn, ít hệ = thuần = nhanh) hoặc tên dị căn.
-- Tốc độ linh căn = cult_linhcan_mult(bộ hệ, dị căn) × (1 + 0.1×(refine−1)).
-- Kèm: buff thật theo cấp Tiên (064) vào rate + chỉ số; Tâm Ma khi Độ Thiên Kiếp.
-- Mirror app: rootName/_variantNames + hợp hệ theo set — app/lib/cultivation.dart.

alter table user_cultivation add column if not exists elements text[] not null default '{}';
alter table user_cultivation add column if not exists variant text;

-- Hệ số tốc độ theo linh căn. Ít hệ = thuần = nhanh; dị/thiên căn vượt trội.
-- ponytail: các hằng là heuristic cân bằng — chỉnh ở đây.
create or replace function cult_linhcan_mult(p_elements text[], p_variant text)
returns numeric language sql immutable as $$
  select case
    when p_variant = 'hon'  then 14.0   -- Hỗn Độn: hợp mọi công pháp + nhanh nhất
    when p_variant = 'thien' then 10.0   -- Thiên Linh Căn: đơn hệ thuần khiết tối thượng
    when p_variant in ('kiem', 'loi') then 8.0
    when p_variant in ('bang', 'phong', 'am') then 7.5
    when p_variant is not null then 7.0  -- dị căn khác
    else case coalesce(array_length(p_elements, 1), 5)
      when 1 then 5.0 when 2 then 3.4 when 3 then 2.4 when 4 then 1.6 else 1.0 end
  end;
$$;

-- Trời định bộ linh căn cho user (chạy 1 lần khi elements rỗng). Dị/thiên căn rất hiếm (2%);
-- còn lại nghiêng về NHIỀU hệ (tạp phổ biến, đơn hiếm).
create or replace function cult_assign_root(p_uid uuid) returns user_cultivation
language plpgsql security definer set search_path = public as $$
declare
  c user_cultivation;
  all5 text[] := array['kim', 'moc', 'thuy', 'hoa', 'tho'];
  r numeric := random();
  cnt int;
  els text[];
  vr text := null;
begin
  if r < 0.02 then
    vr := (array['thien', 'hon', 'kiem', 'loi', 'bang', 'phong', 'am'])[1 + floor(random() * 7)::int];
    if vr = 'hon' then els := all5;
    else els := array[all5[1 + floor(random() * 5)::int]];
    end if;
  else
    cnt := case
      when r < 0.37 then 5 when r < 0.64 then 4 when r < 0.84 then 3
      when r < 0.96 then 2 else 1 end;
    els := array(select e from unnest(all5) e order by random() limit cnt);
  end if;
  update user_cultivation set elements = els, variant = vr
    where user_id = p_uid returning * into c;
  return c;
end $$;

-- Rate nền (đè 044): hợp hệ theo BỘ HỆ (hoặc Hỗn Độn hợp mọi công pháp), nhân hệ số linh
-- căn mới, giữ refine (1+0.1×(linh_can−1)), + buff cấp Tiên ×(1+0.2×tien_tier).
create or replace function cult_base_rate(c user_cultivation) returns numeric
language sql stable as $$
  select 1
    * cult_mult((select grade from cult_items where id = c.equip_congphap))
    * case when c.variant = 'hon'
             or (select i.effect->>'element' from cult_items i where i.id = c.equip_congphap)
                = any (array_append(c.elements, 'all'))
           then 1.3 else 1 end
    * cult_linhcan_mult(c.elements, c.variant)
    * (1 + 0.1 * (c.linh_can - 1))
    * case when c.race = 'ma' then 1.10 else 1 end
    * (1 + 0.2 * coalesce(c.tien_tier, 0))
    * (1 + coalesce((select sum((effect->>'rate_pct')::numeric) from cult_items
         where id in (c.equip_vukhi, c.equip_phapbao)), 0) / 100);
$$;

-- Chỉ số (đè 044): thêm buff cấp Tiên ×(1+0.15×tien_tier) vào nền.
create or replace function cult_stats(c user_cultivation) returns jsonb
language plpgsql stable as $$
declare
  li int := (c.realm - 1) * 9 + c.stage - 1;
  base numeric := power(1.12, li) * (1 + 0.15 * coalesce(c.tien_tier, 0));
  g_atk numeric; g_def numeric; g_hp numeric; g_agi numeric;
begin
  select coalesce(sum((effect->>'atk')::numeric), 0),
         coalesce(sum((effect->>'def')::numeric), 0),
         coalesce(sum((effect->>'hp')::numeric), 0),
         coalesce(sum((effect->>'agi')::numeric), 0)
    into g_atk, g_def, g_hp, g_agi
  from cult_items where id in (c.equip_vukhi, c.equip_yphuc, c.equip_giay);
  return jsonb_build_object(
    'atk',       floor(10 * base * case when c.race = 'yeu' then 1.3 else 1 end + g_atk),
    'def',       floor(8 * base + g_def),
    'hp',        floor(60 * base * case when c.race = 'yeu' then 1.3 else 1 end + g_hp),
    'agi',       floor(9 * base + g_agi),
    'than_thuc', floor(11 * base * case when c.race = 'linh' then 1.3 else 1 end)
  );
end $$;

-- cult_tick (đè 064): trời định linh căn lần đầu (elements rỗng) rồi mới tính rate.
create or replace function cult_tick(p_uid uuid) returns user_cultivation
language plpgsql security definer set search_path = public as $$
declare
  c user_cultivation;
  r0 numeric;
  elapsed numeric;
  buffed numeric;
  stoned numeric;
  cap numeric;
begin
  insert into user_cultivation (user_id) values (p_uid) on conflict do nothing;
  select * into c from user_cultivation where user_id = p_uid for update;
  if coalesce(array_length(c.elements, 1), 0) = 0 then
    c := cult_assign_root(p_uid);
  end if;

  r0 := cult_base_rate(c);
  elapsed := least(extract(epoch from now() - c.last_tick), 48 * 3600);
  buffed := greatest(0, least(coalesce(extract(epoch from c.buff_until - c.last_tick), 0), elapsed));
  stoned := greatest(0, least(coalesce(extract(epoch from c.stone_until - c.last_tick), 0), elapsed));
  if c.ascended_at is not null then
    cap := cult_tien_req(least(c.tien_tier, cult_tien_max()));
  else
    cap := cult_req(c.realm, c.stage);
  end if;

  update user_cultivation set
    exp = least(cap, c.exp + r0 * elapsed
      + r0 * c.buff_pct / 100.0 * buffed
      + r0 * c.stone_pct / 100.0 * stoned),
    last_tick = now(),
    buff_pct = case when buff_until > now() then buff_pct else 0 end,
    buff_until = case when buff_until > now() then buff_until else null end,
    stone_pct = case when stone_until > now() then stone_pct else 0 end,
    stone_until = case when stone_until > now() then stone_until else null end
  where user_id = p_uid
  returning * into c;
  return c;
end $$;

-- cult_state (đè 064): trả elements + variant (bỏ phụ thuộc 'element' đơn; giữ 'element'
-- = hệ đầu cho tương thích cũ). 'linh_can' nay là mức luyện căn.
create or replace function cult_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c user_cultivation;
begin
  if auth.uid() is null then raise exception 'chưa đăng nhập'; end if;
  c := cult_tick(auth.uid());
  return jsonb_build_object(
    'realm', c.realm, 'stage', c.stage, 'exp', c.exp,
    'req', case when c.ascended_at is not null
                then cult_tien_req(least(c.tien_tier, cult_tien_max()))
                else cult_req(c.realm, c.stage) end,
    'linh_can', c.linh_can,
    'elements', to_jsonb(c.elements),
    'variant', c.variant,
    'element', c.elements[1],
    'race', c.race,
    'gender', c.gender,
    'ascended_at', c.ascended_at,
    'tien_tier', c.tien_tier,
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

-- cult_use_item (đè 043): nhánh 'element' (Chuyển Linh Đan) nay CHỈ tráo lại BỘ HỆ giữ
-- nguyên SỐ hệ (đổi hợp công pháp, không đổi bậc/tốc); linh căn dị bẩm không tráo được.
-- 'linhcan' (Tẩy Tủy Đan) tăng refine như cũ — chỉ tăng tốc, không đổi hệ.
create or replace function cult_use_item(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
  n int;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  perform cult_tick(uid);
  select * into it from cult_items where id = p_item_id;
  if it.type not in ('danduoc', 'linhthach') then
    raise exception 'vật phẩm này không dùng trực tiếp được';
  end if;

  update user_cult_items set qty = qty - 1
  where user_id = uid and item_id = p_item_id and qty > 0;
  if not found then raise exception 'không có vật phẩm này trong kho'; end if;

  case it.effect->>'kind'
    when 'linhcan' then
      update user_cultivation set linh_can = linh_can + (it.effect->>'add')::int
      where user_id = uid;
    when 'buff' then
      update user_cultivation set buff_pct = (it.effect->>'pct')::int,
        buff_until = now() + ((it.effect->>'hours')::numeric || ' hours')::interval
      where user_id = uid;
    when 'stone' then
      update user_cultivation set stone_pct = (it.effect->>'pct')::int,
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

-- Độ Thiên Kiếp (đè 064): thêm TÂM MA cuối mỗi lần thăng bậc tiên. Chỉ số/trang bị càng
-- mạnh, cơ hội càng cao. Thắng → thăng bậc (exp về 0); thua → giữ bậc, hao 20% tiên nguyên.
create or replace function cult_ascend_tier() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  c user_cultivation;
  stats jsonb;
  base numeric;
  geared numeric;
  chance int;
  win boolean;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  c := cult_tick(uid);
  if c.ascended_at is null then raise exception 'phải phi thăng thành tiên trước đã'; end if;
  if c.tien_tier >= cult_tien_max() then raise exception 'đã tới Đạo Tổ — tiên đạo viên mãn'; end if;
  if c.exp < cult_tien_req(c.tien_tier) then raise exception 'chưa đủ tiên nguyên để độ kiếp'; end if;

  stats := cult_stats(c);
  base := power(1.12, 80) * (1 + 0.15 * c.tien_tier); -- nền chỉ số đỉnh Độ Kiếp theo tien buff
  geared := (stats->>'atk')::numeric + (stats->>'def')::numeric
          + (stats->>'hp')::numeric + (stats->>'agi')::numeric;
  chance := least(90, greatest(20,
    round(45 + 40 * (geared / (87 * base) - 1)
              + 20 * ((stats->>'than_thuc')::numeric / (11 * base) - 1))));
  win := random() * 100 < chance;

  if win then
    update user_cultivation set tien_tier = tien_tier + 1, exp = 0
      where user_id = uid returning * into c;
  else
    update user_cultivation set exp = greatest(0, exp * 0.8)
      where user_id = uid returning * into c;
  end if;
  return jsonb_build_object('win', win, 'chance', chance, 'tier', c.tien_tier);
end $$;

-- Backfill: mọi user cũ (elements rỗng) được trời định lại một bộ linh căn (mô hình cũ chỉ
-- có 1 hệ nên không map 1-1 được). Mức luyện căn (linh_can) GIỮ NGUYÊN → không mất công cày.
do $$
declare u uuid;
begin
  for u in select user_id from user_cultivation where coalesce(array_length(elements, 1), 0) = 0
  loop perform cult_assign_root(u); end loop;
end $$;
