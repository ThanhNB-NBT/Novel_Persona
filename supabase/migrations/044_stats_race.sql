-- CHỈ SỐ CƠ BẢN + CHỦNG TỘC + TRANG BỊ MỚI
--
-- Chỉ số (nền tăng theo cảnh giới ×1.12/tầng, trang bị cộng phẳng):
--   Công Kích (atk) · Phòng Ngự (def) · Khí Huyết (hp) · Thân Pháp (agi) · Thần Thức
-- Vũ khí KHÔNG còn tăng tốc tu luyện (vô lý) → chuyển sang atk (atk = rate_pct×4 cũ).
-- Thêm 2 loại trang bị: y phục (def+hp), hài (agi). Pháp bảo giữ vai trò tăng tốc.
-- Chỉ số có tác dụng thật: đột phá THẤT BẠI mất exp = 30% × (1 − def/(def+1000), trần
-- giảm 50%). Công/khí huyết để dành combat tâm ma (giai đoạn sau).
--
-- Chủng tộc (chọn 1 lần khi bắt đầu, RPC cult_set_race):
--   Nhân: đạo tâm kiên định — tỷ lệ đột phá +5%
--   Yêu:  thể phách cường hãn — công kích & khí huyết ×1.3
--   Ma:   tu luyện tà tốc — tốc độ ×1.10, tỷ lệ đột phá −5%
--   Linh: linh hồn thanh tịnh — thần thức ×1.3, thất bại đột phá chỉ mất nửa exp

alter table cult_items drop constraint if exists cult_items_type_check;
alter table cult_items add constraint cult_items_type_check
  check (type in ('congphap','danduoc','vukhi','phapbao','phapchu','linhthach','yphuc','giay'));

alter table user_cultivation
  add column if not exists race text check (race in ('nhan','yeu','ma','linh')),
  add column if not exists equip_yphuc int references cult_items(id),
  add column if not exists equip_giay int references cult_items(id);

-- Vũ khí: rate_pct → atk (idempotent: chạy lại không còn rate_pct thì no-op)
update cult_items set effect = jsonb_build_object('atk', (effect->>'rate_pct')::int * 4)
where type = 'vukhi' and effect ? 'rate_pct';

-- Chỉ số hiện tại của 1 tu sĩ: nền theo tầng tu vi + hệ số tộc + trang bị.
create or replace function cult_stats(c user_cultivation) returns jsonb
language plpgsql stable as $$
declare
  li int := (c.realm - 1) * 9 + c.stage - 1;
  base numeric := power(1.12, li);
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

-- Rate nền: thêm hệ số Ma tộc ×1.10 (đè bản 043).
create or replace function cult_base_rate(c user_cultivation) returns numeric
language sql stable as $$
  select 1
    * cult_mult((select grade from cult_items where id = c.equip_congphap))
    * case when (select i.effect->>'element' from cult_items i where i.id = c.equip_congphap)
             in (c.element, 'all') then 1.3 else 1 end
    * case when c.race = 'ma' then 1.10 else 1 end
    * (1 + 0.1 * (c.linh_can - 1))
    * (1 + coalesce((select sum((effect->>'rate_pct')::numeric) from cult_items
         where id in (c.equip_vukhi, c.equip_phapbao)), 0) / 100);
$$;

-- Chọn chủng tộc — MỘT lần duy nhất, lúc bắt đầu tu.
create or replace function cult_set_race(p_race text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'chưa đăng nhập'; end if;
  if p_race not in ('nhan', 'yeu', 'ma', 'linh') then
    raise exception 'chủng tộc không hợp lệ';
  end if;
  perform cult_tick(auth.uid()); -- đảm bảo có dòng
  update user_cultivation set race = p_race
  where user_id = auth.uid() and race is null;
  if not found then raise exception 'đã chọn chủng tộc rồi — nghịch thiên cải mệnh không dễ vậy'; end if;
  return cult_state();
end $$;
grant execute on function cult_set_race(text) to authenticated;

-- state: thêm race + stats + 2 slot trang bị mới (đè bản 043).
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

-- equip: thêm 2 slot mới (đè bản 039).
create or replace function cult_equip(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  perform cult_tick(uid); -- chốt exp theo trang bị cũ trước khi đổi
  select * into it from cult_items where id = p_item_id;
  if it.type in ('danduoc', 'linhthach') then
    raise exception 'đồ tiêu hao thì dùng, không trang bị';
  end if;
  if not exists (select 1 from user_cult_items
      where user_id = uid and item_id = p_item_id and qty > 0) then
    raise exception 'không có vật phẩm này trong kho';
  end if;

  update user_cultivation set
    equip_congphap = case when it.type = 'congphap' then it.id else equip_congphap end,
    equip_vukhi    = case when it.type = 'vukhi'    then it.id else equip_vukhi end,
    equip_phapbao  = case when it.type = 'phapbao'  then it.id else equip_phapbao end,
    equip_phapchu  = case when it.type = 'phapchu'  then it.id else equip_phapchu end,
    equip_yphuc    = case when it.type = 'yphuc'    then it.id else equip_yphuc end,
    equip_giay     = case when it.type = 'giay'     then it.id else equip_giay end
  where user_id = uid;
  return cult_state();
end $$;

-- advance: tộc ảnh hưởng tỷ lệ; phòng ngự + Linh tộc giảm exp mất khi thất bại (đè 039).
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
  ok := random() * 100 < chance;

  if ok then
    update user_cultivation set realm = realm + 1, stage = 1, exp = 0, bt_bonus_pct = 0
    where user_id = uid;
  else
    -- mất 30% req, giảm theo phòng ngự (trần giảm 50%); Linh tộc chỉ mất nửa
    v_def := (cult_stats(c)->>'def')::numeric;
    v_loss := 0.30 * (1 - least(0.5, v_def / (v_def + 1000)))
      * case when c.race = 'linh' then 0.5 else 1 end;
    update user_cultivation set exp = greatest(0, exp - req * v_loss), bt_bonus_pct = 0
    where user_id = uid;
  end if;
  return jsonb_build_object('success', ok, 'chance', chance,
    'realm', case when ok then c.realm + 1 else c.realm end,
    'stage', case when ok then 1 else 9 end);
end $$;

-- Seed y phục (10) + hài (8). def/hp/agi leo theo phẩm; weight chuẩn theo grade.
insert into cult_items (code, name, type, grade, weight, effect, descr, pixel) values
('yp_tho_bo',      'Thô Bố Y',             'yphuc', 1, 100, '{"def":5,"hp":30}',    'Áo vải thô của tán tu nghèo. Thủ +5, khí huyết +30.', 'robe'),
('yp_thanh_sam',   'Thanh Sam Đạo Bào',    'yphuc', 1,  85, '{"def":7,"hp":40}',    'Đạo bào xanh giản dị. Thủ +7, khí huyết +40.', 'robe'),
('yp_huyen_vu',    'Huyền Vũ Giáp',        'yphuc', 2,  40, '{"def":14,"hp":85}',   'Giáp khắc văn Huyền Vũ. Thủ +14, khí huyết +85.', 'robe'),
('yp_tu_van',      'Tử Vân Đạo Bào',       'yphuc', 2,  35, '{"def":12,"hp":100}',  'Đạo bào dệt tơ mây tía. Thủ +12, khí huyết +100.', 'robe'),
('yp_kim_tam',     'Kim Tàm Bảo Y',        'yphuc', 3,  15, '{"def":26,"hp":170}',  'Dệt từ tơ kim tàm, đao kiếm khó phạm. Thủ +26, khí huyết +170.', 'robe'),
('yp_bich_lan',    'Bích Lân Giáp',        'yphuc', 3,  12, '{"def":30,"hp":150}',  'Ghép từ vảy giao long. Thủ +30, khí huyết +150.', 'robe'),
('yp_thien_tinh',  'Thiên Tinh Chiến Giáp','yphuc', 4,   5, '{"def":50,"hp":300}',  'Rèn từ sắt sao trời. Thủ +50, khí huyết +300.', 'robe'),
('yp_vo_cau',      'Vô Cấu Đạo Bào',       'yphuc', 4,   4, '{"def":42,"hp":360}',  'Bụi trần không bám, tà khí không xâm. Thủ +42, khí huyết +360.', 'robe'),
('yp_hon_nguyen',  'Hỗn Nguyên Tiên Y',    'yphuc', 5,   1, '{"def":90,"hp":600}',  'Tiên y hộ thân, vạn kiếp bất hoại. Thủ +90, khí huyết +600.', 'robe'),
('yp_bat_diet',    'Bất Diệt Thần Giáp',   'yphuc', 5,   1, '{"def":100,"hp":550}', 'Thần giáp thượng cổ từng đỡ một kích của tiên nhân. Thủ +100, khí huyết +550.', 'robe'),
('gi_thao_hai',    'Thảo Hài',             'giay', 1, 100, '{"agi":4}',  'Dép cỏ bện tay. Thân pháp +4.', 'boot'),
('gi_bo_ngoa',     'Bố Ngoa',              'giay', 1,  85, '{"agi":6}',  'Giày vải đế mềm. Thân pháp +6.', 'boot'),
('gi_tat_hanh',    'Tật Hành Ngoa',        'giay', 2,  40, '{"agi":12}', 'Đi ngày trăm dặm không mỏi. Thân pháp +12.', 'boot'),
('gi_truy_phong',  'Truy Phong Ngoa',      'giay', 2,  35, '{"agi":14}', 'Nhẹ như đuổi theo gió. Thân pháp +14.', 'boot'),
('gi_lang_ba',     'Lăng Ba Hài',          'giay', 3,  14, '{"agi":26}', 'Lướt trên mặt nước như đạp sóng. Thân pháp +26.', 'boot'),
('gi_dap_van',     'Đạp Vân Ngoa',         'giay', 4,   5, '{"agi":45}', 'Giẫm mây mà đi. Thân pháp +45.', 'boot'),
('gi_tung_dia',    'Túng Địa Kim Ngoa',    'giay', 4,   4, '{"agi":50}', 'Một bước ngàn trượng theo thuật Túng Địa. Thân pháp +50.', 'boot'),
('gi_thuan_thien', 'Thuấn Thiên Ngoa',     'giay', 5,   1, '{"agi":90}', 'Chớp mắt đã ở chân trời. Thân pháp +90.', 'boot')
on conflict (code) do nothing;
