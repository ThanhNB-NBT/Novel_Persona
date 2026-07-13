-- Trận pháp hào quang hậu Phi Thăng: vật phẩm ĐỘI THẲNG lên nhân vật (không nằm ô trang
-- bị), rơi trong lúc ĐỌC như cơ duyên, CHỈ sau khi phi thăng (ascended_at). Là cosmetic
-- (không ảnh hưởng chỉ số) — server chỉ giữ danh sách sở hữu + cái đang đội, validate code.
-- Art client: app/assets/cult_halo/{code}.webp; danh mục mã ở app/lib/cultivation.dart.

alter table user_cultivation add column if not exists halos text[] not null default '{}';
alter table user_cultivation add column if not exists halo_worn text;

-- Allowlist mã trận (khớp tienHaloCodes app). Rơi/đội đều phải nằm trong đây.
create or replace function cult_halo_codes() returns text[] language sql immutable as $$
  select array['thai_duong', 'luc_du', 'huyen_tuyet', 'bach_ngan', 'hoang_kim', 'huyet_long'];
$$;

-- cult_state (đè 067): trả halos + halo_worn.
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
    'halos', to_jsonb(c.halos),
    'halo_worn', c.halo_worn,
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

-- Đội / cởi trận. Chỉ khi đã phi thăng. p_code=null → cởi. Phải sở hữu HOẶC là admin.
create or replace function cult_wear_halo(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  c user_cultivation;
  is_admin boolean;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  c := cult_tick(uid);
  if c.ascended_at is null then raise exception 'chỉ Tiên Nhân mới đội được trận pháp'; end if;
  if p_code is null then
    update user_cultivation set halo_worn = null where user_id = uid;
    return cult_state();
  end if;
  if not (p_code = any (cult_halo_codes())) then raise exception 'mã trận không hợp lệ'; end if;
  select coalesce((select p.is_admin from profiles p where p.id = uid), false) into is_admin;
  if not (p_code = any (c.halos)) and not is_admin then
    raise exception 'chưa sở hữu trận pháp này';
  end if;
  update user_cultivation set halo_worn = p_code where user_id = uid;
  return cult_state();
end $$;

-- DEV/admin: nhận trọn bộ trận để test (chỉ admin). Đội luôn cái đầu nếu chưa đội gì.
create or replace function cult_admin_grant_halos() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  if not coalesce((select is_admin from profiles where id = uid), false) then
    raise exception 'chỉ admin';
  end if;
  update user_cultivation
    set halos = cult_halo_codes(),
        halo_worn = coalesce(halo_worn, (cult_halo_codes())[1])
    where user_id = uid;
  return cult_state();
end $$;

-- Cơ duyên (đè 049): sau khi trao vật phẩm thường, nếu ĐÃ phi thăng thì có 30% cơ hội
-- BỔ SUNG một trận pháp CHƯA sở hữu (đội luôn nếu chưa đội gì). Trận là tập hợp (sở hữu 1
-- lần) nên không cần chống trùng riêng — hết bộ thì thôi. Trả kèm 'halo' nếu vừa nhận.
create or replace function cult_claim_gift(p_novel_id bigint, p_index int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
  c user_cultivation;
  new_halo text := null;
  res jsonb;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  if not cult_gift_at(uid, p_novel_id, p_index) then
    raise exception 'chương này không có quà';
  end if;
  c := cult_tick(uid);

  select * into it from cult_items order by random() limit 1;

  insert into cult_claims (user_id, novel_id, chapter_index, item_id)
  values (uid, p_novel_id, p_index, it.id); -- PK chặn nhận trùng → lỗi duplicate

  insert into user_cult_items (user_id, item_id, qty) values (uid, it.id, 1)
  on conflict (user_id, item_id) do update set qty = user_cult_items.qty + 1;

  if c.ascended_at is not null and random() < 0.30 then
    select code into new_halo
    from unnest(cult_halo_codes()) code
    where not (code = any (c.halos))
    order by random() limit 1;
    if new_halo is not null then
      update user_cultivation
        set halos = array_append(halos, new_halo),
            halo_worn = coalesce(halo_worn, new_halo)
        where user_id = uid;
    end if;
  end if;

  res := to_jsonb(it);
  if new_halo is not null then res := res || jsonb_build_object('halo', new_halo); end if;
  return res;
end $$;

grant execute on function cult_wear_halo(text) to authenticated;
grant execute on function cult_admin_grant_halos() to authenticated;
