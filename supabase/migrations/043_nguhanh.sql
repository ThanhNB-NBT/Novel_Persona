-- NGŨ HÀNH: linh căn mỗi user có THUỘC TÍNH (kim/mộc/thủy/hỏa/thổ, trời định
-- lúc khởi tạo), công pháp có HỆ (effect.element). Tu công pháp HỢP HỆ (trùng
-- thuộc tính, hoặc công pháp hệ 'all' — loại diễn hóa vạn pháp) → tốc độ ×1.3.
-- Chuyển Linh Đan đổi thuộc tính sang hệ khác ngẫu nhiên.
--
-- Kèm dọn nợ: công thức rate trùng lặp ở cult_tick và cult_state → gom về
-- cult_base_rate(). Bản tick/state ở đây kế thừa ĐỦ kênh linh thạch của 040.

alter table user_cultivation add column if not exists element text
  check (element in ('kim', 'moc', 'thuy', 'hoa', 'tho'));

-- user cũ: gieo thuộc tính ngẫu nhiên
update user_cultivation
set element = (array['kim', 'moc', 'thuy', 'hoa', 'tho'])[1 + floor(random() * 5)::int]
where element is null;

-- Rate nền (chưa tính buff đan/linh thạch): công pháp × hợp hệ × linh căn × trang bị.
create or replace function cult_base_rate(c user_cultivation) returns numeric
language sql stable as $$
  select 1
    * cult_mult((select grade from cult_items where id = c.equip_congphap))
    * case when (select i.effect->>'element' from cult_items i where i.id = c.equip_congphap)
             in (c.element, 'all') then 1.3 else 1 end
    * (1 + 0.1 * (c.linh_can - 1))
    * (1 + coalesce((select sum((effect->>'rate_pct')::numeric) from cult_items
         where id in (c.equip_vukhi, c.equip_phapbao)), 0) / 100);
$$;

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
  insert into user_cultivation (user_id, element)
  values (p_uid, (array['kim', 'moc', 'thuy', 'hoa', 'tho'])[1 + floor(random() * 5)::int])
  on conflict do nothing;
  select * into c from user_cultivation where user_id = p_uid for update;

  r0 := cult_base_rate(c);
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
    'element', c.element,
    'buff_pct', c.buff_pct, 'buff_until', c.buff_until,
    'stone_pct', c.stone_pct, 'stone_until', c.stone_until,
    'bt_bonus_pct', c.bt_bonus_pct,
    'rate', cult_base_rate(c)
      * (1 + (case when c.buff_until > now() then c.buff_pct else 0 end
            + case when c.stone_until > now() then c.stone_pct else 0 end) / 100.0),
    'equipped', (select coalesce(jsonb_object_agg(i.type, to_jsonb(i)), '{}'::jsonb)
      from cult_items i
      where i.id in (c.equip_congphap, c.equip_vukhi, c.equip_phapbao, c.equip_phapchu))
  );
end $$;

-- Thêm nhánh đan đổi hệ (kind 'element'): reroll sang một hệ KHÁC hệ hiện tại.
create or replace function cult_use_item(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  perform cult_tick(uid); -- chốt exp theo buff/hệ cũ trước khi đổi
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
      update user_cultivation u set element = (
        select e from unnest(array['kim', 'moc', 'thuy', 'hoa', 'tho']) e
        where e <> u.element order by random() limit 1)
      where user_id = uid;
    else raise exception 'vật phẩm lỗi dữ liệu effect';
  end case;
  return cult_state();
end $$;

-- Gán hệ cho công pháp có sẵn (nhập môn dan_khi/tho_nap để vô thuộc tính).
update cult_items set effect = effect || jsonb_build_object('element', e.el)
from (values
  ('cp_huyen_bang', 'thuy'), ('cp_huyen_thien', 'thuy'),
  ('cp_ngu_phong', 'moc'),
  ('cp_dia_sat', 'tho'), ('cp_luyen_the', 'tho'),
  ('cp_cuu_chuyen', 'kim'), ('cp_thien_cang', 'kim'),
  ('cp_dai_dien', 'all'), ('cp_hon_don', 'all'), ('cp_thai_co', 'all')
) as e(code, el)
where cult_items.code = e.code;

-- Bổ sung công pháp hệ Hỏa/Mộc (trước đây thiếu) + Chuyển Linh Đan.
insert into cult_items (code, name, type, grade, weight, effect, descr, pixel) values
('cp_liet_hoa',  'Liệt Hỏa Chân Quyết',        'congphap', 2, 35, '{"element":"hoa"}', 'Công pháp hệ Hỏa, luyện linh lực thành chân hỏa hừng hực.', 'scroll'),
('cp_thanh_moc', 'Thanh Mộc Trường Sinh Công', 'congphap', 3, 13, '{"element":"moc"}', 'Công pháp hệ Mộc, sinh cơ bất tận như rừng già.', 'book'),
('cp_xich_diem', 'Xích Diễm Phần Thiên Quyết', 'congphap', 4,  4, '{"element":"hoa"}', 'Hỏa công thượng thừa, một niệm thiêu trời.', 'scroll'),
('dd_chuyen_linh', 'Chuyển Linh Đan',          'danduoc',  3,  8, '{"kind":"element"}', 'Tẩy đổi thuộc tính linh căn sang một hệ khác (ngẫu nhiên).', 'pill')
on conflict (code) do nothing;
