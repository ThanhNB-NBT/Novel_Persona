-- Linh thạch: vật phẩm tiêu hao tăng tốc tu luyện, KÊNH RIÊNG với đan buff
-- (đeo song song, cộng dồn kiểu additive: rate = r0 × (1 + đan% + thạch%)).
-- Phân cấp theo phẩm: càng cao càng mạnh + càng lâu.
--
-- ==== HẰNG SỐ (seed cuối file) ==================================================
--  Hạ phẩm  +30%/8h · Trung +60%/12h · Thượng +100%/24h · Cực phẩm +200%/24h
--  Tiên thạch +300%/48h. Dùng viên mới ĐÈ viên cũ (không cộng dồn thời gian).
-- ===============================================================================

-- Idempotent: SQL này từng được áp thẳng vào DB (ngoài sổ migration) nên mọi
-- lệnh phải chạy lại được mà không đụng.
alter table cult_items drop constraint if exists cult_items_type_check;
alter table cult_items add constraint cult_items_type_check
  check (type in ('congphap','danduoc','vukhi','phapbao','phapchu','linhthach'));

alter table user_cultivation
  add column if not exists stone_pct int not null default 0,
  add column if not exists stone_until timestamptz;

-- Tick: cộng exp theo 3 phần additive — nền + đan buff (tới buff_until) + linh
-- thạch (tới stone_until), mỗi kênh kẹp trong khoảng elapsed (tối đa 48h).
create or replace function cult_tick(p_uid uuid) returns user_cultivation
language plpgsql security definer set search_path = public as $$
declare
  c user_cultivation;
  r0 numeric;           -- rate không buff (exp/giây)
  elapsed numeric;
  buffed numeric;
  stoned numeric;
  cap numeric;
begin
  insert into user_cultivation (user_id) values (p_uid) on conflict do nothing;
  select * into c from user_cultivation where user_id = p_uid for update;

  r0 := 1
    * cult_mult((select grade from cult_items where id = c.equip_congphap))
    * (1 + 0.1 * (c.linh_can - 1))
    * (1 + coalesce((select sum((effect->>'rate_pct')::numeric) from cult_items
         where id in (c.equip_vukhi, c.equip_phapbao)), 0) / 100);

  elapsed := least(extract(epoch from now() - c.last_tick), 48 * 3600);
  buffed := greatest(0, least(coalesce(extract(epoch from c.buff_until - c.last_tick), 0), elapsed));
  stoned := greatest(0, least(coalesce(extract(epoch from c.stone_until - c.last_tick), 0), elapsed));
  cap := cult_req(c.realm, c.stage);

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
    'buff_pct', c.buff_pct, 'buff_until', c.buff_until,
    'stone_pct', c.stone_pct, 'stone_until', c.stone_until,
    'bt_bonus_pct', c.bt_bonus_pct,
    'rate', 1 * cult_mult((select grade from cult_items where id = c.equip_congphap))
      * (1 + 0.1 * (c.linh_can - 1))
      * (1 + coalesce((select sum((effect->>'rate_pct')::numeric) from cult_items
           where id in (c.equip_vukhi, c.equip_phapbao)), 0) / 100)
      * (1 + (case when c.buff_until > now() then c.buff_pct else 0 end
            + case when c.stone_until > now() then c.stone_pct else 0 end) / 100.0),
    'equipped', (select coalesce(jsonb_object_agg(i.type, to_jsonb(i)), '{}'::jsonb)
      from cult_items i
      where i.id in (c.equip_congphap, c.equip_vukhi, c.equip_phapbao, c.equip_phapchu))
  );
end $$;

-- Dùng vật phẩm tiêu hao: đan dược như cũ + linh thạch (kind stone, kênh riêng).
create or replace function cult_use_item(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  perform cult_tick(uid); -- chốt exp theo buff cũ trước khi đổi buff
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
    else raise exception 'vật phẩm lỗi dữ liệu effect';
  end case;
  return cult_state();
end $$;

-- Seed linh thạch 5 phẩm (weight chuẩn theo grade: 90/45/18/6/2)
insert into cult_items (code, name, type, grade, weight, effect, descr, pixel) values
('lt_ha_pham',    'Hạ Phẩm Linh Thạch',   'linhthach', 1, 90, '{"kind":"stone","pct":30,"hours":8}',   'Linh thạch phổ thông, tốc độ +30% trong 8 giờ.', 'stone'),
('lt_trung_pham', 'Trung Phẩm Linh Thạch','linhthach', 2, 45, '{"kind":"stone","pct":60,"hours":12}',  'Linh khí tinh khiết, tốc độ +60% trong 12 giờ.', 'stone'),
('lt_thuong_pham','Thượng Phẩm Linh Thạch','linhthach',3, 18, '{"kind":"stone","pct":100,"hours":24}', 'Linh thạch thượng hạng, tốc độ +100% trong 24 giờ.', 'stone'),
('lt_cuc_pham',   'Cực Phẩm Linh Thạch',  'linhthach', 4,  6, '{"kind":"stone","pct":200,"hours":24}', 'Cực phẩm hiếm thấy, tốc độ +200% trong 24 giờ.', 'stone'),
('lt_tien_thach', 'Tiên Thạch',           'linhthach', 5,  2, '{"kind":"stone","pct":300,"hours":48}', 'Kết tinh tiên khí, tốc độ +300% trong 48 giờ.', 'stone')
on conflict (code) do nothing;
