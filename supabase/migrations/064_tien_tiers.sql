-- Cấp bậc Tiên hậu Phi Thăng: sau khi phi thăng (ascended_at != null), tu vi KHÔNG còn
-- bị chặn ở đỉnh Độ Kiếp mà tiếp tục tích để "độ thiên kiếp" thăng dần lên các bậc tiên
-- (Tiên Nhân → Địa Tiên → … → Đạo Tổ). Không PvP, không phạt — vòng vinh danh cuối game.
-- Server vẫn là chuẩn; client chỉ SELECT + gọi RPC.
-- Cặp mirror app: tienTierNames/tienDaoTitles + cultAscendTier (app/lib/cultivation.dart).

alter table user_cultivation add column if not exists tien_tier int not null default 0;

-- Bậc tiên tối đa (0 Tiên Nhân .. 6 Đạo Tổ). Khớp độ dài tienTierNames trong app.
create or replace function cult_tien_max() returns int language sql immutable as $$
  select 6;
$$;

-- Tu vi cần để thăng TỪ bậc p_tier LÊN bậc kế. Nền = đỉnh Độ Kiếp, mỗi bậc ×1.6.
-- ponytail: hệ số 1.6 là heuristic — chỉnh ở đây nếu vòng vinh danh quá nhanh/chậm.
create or replace function cult_tien_req(p_tier int) returns numeric
language sql immutable as $$
  select floor(cult_req(9, 9) * power(1.6, p_tier + 1));
$$;

-- cult_tick: hậu phi thăng, trần exp = mốc thăng bậc tiên kế thay cho trần Độ Kiếp.
-- (Nền cối gốc dựa bản 043; chỉ đổi phần tính `cap`.)
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

-- cult_state: hậu phi thăng trả 'req' = mốc thăng bậc kế + 'tien_tier' (đè bản 055).
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
    'element', c.element,
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

-- Thăng một bậc tiên: tích đầy tiên nguyên → độ thiên kiếp lên bậc kế. Không Tâm Ma,
-- không phạt (đã là tiên) — exp về 0, trần tick tự nâng theo bậc mới. Trả {tier} bậc mới.
create or replace function cult_ascend_tier() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  c user_cultivation;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  c := cult_tick(uid);
  if c.ascended_at is null then raise exception 'phải phi thăng thành tiên trước đã'; end if;
  if c.tien_tier >= cult_tien_max() then raise exception 'đã tới Đạo Tổ — tiên đạo viên mãn'; end if;
  if c.exp < cult_tien_req(c.tien_tier) then raise exception 'chưa đủ tiên nguyên để độ kiếp'; end if;
  update user_cultivation
    set tien_tier = tien_tier + 1, exp = 0
    where user_id = uid returning * into c;
  return jsonb_build_object('tier', c.tien_tier);
end $$;

grant execute on function cult_ascend_tier() to authenticated;
