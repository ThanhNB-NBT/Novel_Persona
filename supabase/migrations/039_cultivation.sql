-- Hệ thống Tu Luyện: game treo tu tiên cho mỗi user.
-- Exp tích lười (không server tick): mỗi lần gọi cult_state() mới cộng dồn
-- exp = rate × thời_gian_trôi_qua (kẹp 48h). Mọi ghi đều qua RPC SECURITY DEFINER,
-- client chỉ được SELECT dòng của mình.
--
-- ==== HẰNG SỐ CÂN BẰNG (chỉnh ở đây) ============================================
--  - Exp yêu cầu:      cult_req(realm, stage) = floor(300 × 1.30^((realm−1)×9 + stage−1))
--  - Tốc độ gốc:       1 exp/giây
--  - Công pháp:        Hoàng ×1.5, Huyền ×3, Địa ×6, Thiên ×12, Tiên ×24 (hàm cult_mult)
--  - Linh căn:         ×(1 + 0.1×(linh_căn−1))
--  - Offline kẹp:      48 giờ mỗi lần tick
--  - Đột phá:          85% − 8%×(realm−1) + bonus vật phẩm, kẹp [10,100]; fail mất 30% req
--  - Quà trong chương: md5 6 hex đầu % 100 < 30 (~30% chương, tất định theo user)
--  - Phẩm rơi:         grade tối đa = (realm+1)/2, tối thiểu = grade_max − 1
-- ===============================================================================

-- 9 cảnh giới × 9 tầng: Luyện Khí, Trúc Cơ, Kim Đan, Nguyên Anh, Hóa Thần,
-- Luyện Hư, Hợp Thể, Đại Thừa, Độ Kiếp. Hết Độ Kiếp 9 = Phi Thăng (max).

create function cult_req(p_realm int, p_stage int) returns numeric
language sql immutable as $$
  select floor(300 * power(1.30, (p_realm - 1) * 9 + p_stage - 1));
$$;

-- Hệ số công pháp theo phẩm (1=Hoàng..5=Tiên); 0/null = chưa học công pháp.
create function cult_mult(p_grade int) returns numeric
language sql immutable as $$
  select case coalesce(p_grade, 0)
    when 1 then 1.5 when 2 then 3 when 3 then 6 when 4 then 12 when 5 then 24
    else 1 end;
$$;

-- Chương này có quà cho user này không — tất định, không cần lưu trước.
-- Client (Dart) tính y hệt: int.parse(md5hex.substring(0,6), radix:16) % 100 < 30.
create function cult_gift_at(p_uid uuid, p_novel_id bigint, p_index int) returns boolean
language sql immutable as $$
  select ('x00' || substr(md5(p_uid::text || ':' || p_novel_id || ':' || p_index), 1, 6))::bit(32)::int % 100 < 30;
$$;

-- ==== BẢNG ====================================================================

-- Catalog vật phẩm (seed sẵn, đọc công khai).
create table cult_items (
  id int generated always as identity primary key,
  code text not null unique,
  name text not null,
  type text not null check (type in ('congphap','danduoc','vukhi','phapbao','phapchu')),
  grade int not null check (grade between 1 and 5), -- 1 Hoàng < 2 Huyền < 3 Địa < 4 Thiên < 5 Tiên
  weight int not null default 10,                   -- trọng số rơi (to = dễ rơi)
  effect jsonb not null,                            -- xem seed bên dưới
  descr text not null,
  pixel text not null                               -- khóa sprite pixel phía app
);

-- Trạng thái tu luyện mỗi user.
create table user_cultivation (
  user_id uuid primary key references auth.users(id) on delete cascade,
  realm int not null default 1 check (realm between 1 and 9),
  stage int not null default 1 check (stage between 1 and 9),
  exp numeric not null default 0,
  linh_can int not null default 1,
  last_tick timestamptz not null default now(),
  equip_congphap int references cult_items(id),
  equip_vukhi int references cult_items(id),
  equip_phapbao int references cult_items(id),
  equip_phapchu int references cult_items(id),
  buff_pct int not null default 0,   -- % buff đan dược đang chạy
  buff_until timestamptz,
  bt_bonus_pct int not null default 0 -- đan hộ thân đã uống, cộng vào lần đột phá tới
);

-- Kho đồ.
create table user_cult_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id int not null references cult_items(id),
  qty int not null default 0 check (qty >= 0),
  primary key (user_id, item_id)
);

-- Chặn nhận quà trùng chương.
create table cult_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  novel_id bigint not null,
  chapter_index int not null,
  item_id int not null references cult_items(id),
  claimed_at timestamptz not null default now(),
  primary key (user_id, novel_id, chapter_index)
);

alter table cult_items enable row level security;
alter table user_cultivation enable row level security;
alter table user_cult_items enable row level security;
alter table cult_claims enable row level security;

create policy read_cult_items on cult_items for select using (true);
create policy read_own_cultivation on user_cultivation for select to authenticated
  using (user_id = auth.uid());
create policy read_own_cult_inventory on user_cult_items for select to authenticated
  using (user_id = auth.uid());
create policy read_own_cult_claims on cult_claims for select to authenticated
  using (user_id = auth.uid());
-- không có policy insert/update/delete: mọi ghi qua RPC SECURITY DEFINER bên dưới.

-- ==== RPC =====================================================================

-- Tick nội bộ: tạo dòng nếu chưa có, cộng exp theo thời gian trôi qua (kẹp 48h,
-- buff chỉ tính tới buff_until, exp kẹp trần tầng — "bình cảnh"), trả dòng mới.
create function cult_tick(p_uid uuid) returns user_cultivation
language plpgsql security definer set search_path = public as $$
declare
  c user_cultivation;
  r0 numeric;           -- rate không buff (exp/giây)
  elapsed numeric;
  buffed numeric;
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
  cap := cult_req(c.realm, c.stage);

  update user_cultivation set
    exp = least(cap, c.exp + r0 * (elapsed - buffed) + r0 * (1 + c.buff_pct / 100.0) * buffed),
    last_tick = now(),
    buff_pct = case when buff_until > now() then buff_pct else 0 end,
    buff_until = case when buff_until > now() then buff_until else null end
  where user_id = p_uid
  returning * into c;
  return c;
end $$;

-- Trạng thái đầy đủ cho màn Tu Tiên: tick xong trả state + chi tiết 4 món đang trang bị.
create function cult_state() returns jsonb
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
    'bt_bonus_pct', c.bt_bonus_pct,
    'rate', 1 * cult_mult((select grade from cult_items where id = c.equip_congphap))
      * (1 + 0.1 * (c.linh_can - 1))
      * (1 + coalesce((select sum((effect->>'rate_pct')::numeric) from cult_items
           where id in (c.equip_vukhi, c.equip_phapbao)), 0) / 100)
      * (1 + case when c.buff_until > now() then c.buff_pct else 0 end / 100.0),
    'equipped', (select coalesce(jsonb_object_agg(i.type, to_jsonb(i)), '{}'::jsonb)
      from cult_items i
      where i.id in (c.equip_congphap, c.equip_vukhi, c.equip_phapbao, c.equip_phapchu))
  );
end $$;

-- Nhận quà trong chương: verify công thức + chặn trùng, roll vật phẩm theo trọng số,
-- phẩm cấp giới hạn theo cảnh giới hiện tại. Trả vật phẩm vừa nhận.
-- ponytail: không bắt buộc đã đọc tới chương — không PvP nên gian lận vô hại;
-- siết bằng check reading_progress nếu sau này có xếp hạng.
create function cult_claim_gift(p_novel_id bigint, p_index int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  c user_cultivation;
  gmax int;
  it cult_items;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  if not cult_gift_at(uid, p_novel_id, p_index) then
    raise exception 'chương này không có quà';
  end if;
  c := cult_tick(uid);
  gmax := least(5, (c.realm + 1) / 2);

  select * into it from cult_items
  where grade between greatest(1, gmax - 1) and gmax
  order by -ln(random()) / weight limit 1;

  insert into cult_claims (user_id, novel_id, chapter_index, item_id)
  values (uid, p_novel_id, p_index, it.id); -- PK chặn nhận trùng → lỗi duplicate

  insert into user_cult_items (user_id, item_id, qty) values (uid, it.id, 1)
  on conflict (user_id, item_id) do update set qty = user_cult_items.qty + 1;

  return to_jsonb(it);
end $$;

-- Dùng đan dược: linhcan = cộng linh căn vĩnh viễn; buff = thay buff tốc độ (không cộng
-- dồn — uống viên mới đè viên cũ); hothan = nạp bonus cho lần đột phá kế tiếp (lấy max).
create function cult_use_item(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  perform cult_tick(uid); -- chốt exp theo buff cũ trước khi đổi buff
  select * into it from cult_items where id = p_item_id;
  if it.type <> 'danduoc' then raise exception 'chỉ dùng được đan dược'; end if;

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
    when 'hothan' then
      update user_cultivation set bt_bonus_pct = greatest(bt_bonus_pct, (it.effect->>'pct')::int)
      where user_id = uid;
    else raise exception 'đan dược lỗi dữ liệu effect';
  end case;
  return cult_state();
end $$;

-- Trang bị / học công pháp: gắn vào slot theo type (đè món cũ, món cũ vẫn trong kho).
create function cult_equip(p_item_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  it cult_items;
begin
  if uid is null then raise exception 'chưa đăng nhập'; end if;
  perform cult_tick(uid); -- chốt exp theo trang bị cũ trước khi đổi
  select * into it from cult_items where id = p_item_id;
  if it.type = 'danduoc' then raise exception 'đan dược thì uống, không trang bị'; end if;
  if not exists (select 1 from user_cult_items
      where user_id = uid and item_id = p_item_id and qty > 0) then
    raise exception 'không có vật phẩm này trong kho';
  end if;

  update user_cultivation set
    equip_congphap = case when it.type = 'congphap' then it.id else equip_congphap end,
    equip_vukhi    = case when it.type = 'vukhi'    then it.id else equip_vukhi end,
    equip_phapbao  = case when it.type = 'phapbao'  then it.id else equip_phapbao end,
    equip_phapchu  = case when it.type = 'phapchu'  then it.id else equip_phapchu end
  where user_id = uid;
  return cult_state();
end $$;

-- Lên tầng (luôn thành công) / đột phá đại cảnh giới (tầng 9, có tỷ lệ thất bại).
-- Trả {success, chance, realm, stage} để UI diễn hoạt.
create function cult_advance() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  c user_cultivation;
  req numeric;
  chance int;
  ok boolean;
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
    + coalesce((select (effect->>'bt_pct')::int from cult_items where id = c.equip_phapchu), 0)));
  ok := random() * 100 < chance;

  if ok then
    update user_cultivation set realm = realm + 1, stage = 1, exp = 0, bt_bonus_pct = 0
    where user_id = uid;
  else
    update user_cultivation set exp = greatest(0, exp - req * 0.30), bt_bonus_pct = 0
    where user_id = uid;
  end if;
  return jsonb_build_object('success', ok, 'chance', chance,
    'realm', case when ok then c.realm + 1 else c.realm end,
    'stage', case when ok then 1 else 9 end);
end $$;

revoke execute on function cult_tick(uuid) from public, anon, authenticated;
grant execute on function cult_state(), cult_claim_gift(bigint, int),
  cult_use_item(int), cult_equip(int), cult_advance() to authenticated;

-- ==== SEED CATALOG (~60 vật phẩm) =============================================
-- effect theo type:
--   congphap: {}                      (hệ số lấy từ grade qua cult_mult)
--   vukhi/phapbao: {"rate_pct": N}    (+N% tốc độ khi trang bị)
--   phapchu: {"bt_pct": N}            (+N% tỷ lệ đột phá khi trang bị)
--   danduoc: {"kind":"linhcan","add":N} | {"kind":"buff","pct":N,"hours":H}
--            | {"kind":"hothan","pct":N}
-- weight chuẩn theo grade: 100 / 40 / 15 / 5 / 1 (đan buff phổ biến hơn chút).

insert into cult_items (code, name, type, grade, weight, effect, descr, pixel) values
-- Công pháp (12)
('cp_dan_khi',      'Dẫn Khí Quyết',          'congphap', 1, 100, '{}', 'Công pháp nhập môn, dẫn linh khí vào cơ thể.', 'book'),
('cp_tho_nap',      'Thổ Nạp Công',           'congphap', 1, 100, '{}', 'Hít thở theo nhịp trời đất, tu vi chậm mà chắc.', 'book'),
('cp_luyen_the',    'Luyện Thể Thuật',        'congphap', 1,  80, '{}', 'Rèn thân như sắt, đặt nền móng tu hành.', 'book'),
('cp_huyen_bang',   'Huyền Băng Quyết',       'congphap', 2,  40, '{}', 'Lấy hàn khí ngưng linh lực, tinh thuần lạ thường.', 'book'),
('cp_ngu_phong',    'Ngự Phong Quyết',        'congphap', 2,  40, '{}', 'Mượn sức gió trời, tốc độ tu luyện tăng vọt.', 'book'),
('cp_huyen_thien',  'Huyền Thiên Công',       'congphap', 2,  30, '{}', 'Chính tông huyền môn, căn cơ vững vàng.', 'book'),
('cp_dia_sat',      'Địa Sát Chân Kinh',      'congphap', 3,  15, '{}', 'Hấp thu địa mạch sát khí, uy lực kinh người.', 'book'),
('cp_cuu_chuyen',   'Cửu Chuyển Kim Thân Quyết','congphap',3, 12, '{}', 'Chín lần tôi luyện, thân thể sánh pháp bảo.', 'book'),
('cp_thien_cang',   'Thiên Cang Kiếm Điển',   'congphap', 4,   5, '{}', 'Kiếm điển thượng cổ, mỗi chữ nặng nghìn cân.', 'book'),
('cp_dai_dien',     'Đại Diễn Thần Quyết',    'congphap', 4,   4, '{}', 'Diễn hóa vạn pháp, thiên hạ hiếm có.', 'book'),
('cp_hon_don',      'Hỗn Độn Tiên Kinh',      'congphap', 5,   1, '{}', 'Tiên kinh khai thiên, người phàm khó cầu.', 'book'),
('cp_thai_co',      'Thái Cổ Đạo Kinh',       'congphap', 5,   1, '{}', 'Đạo kinh từ thời Thái Cổ, huyền diệu vô cùng.', 'book'),
-- Đan dược: tẩy tủy tăng linh căn (5)
('dd_tay_tuy',      'Tẩy Tủy Đan',            'danduoc', 1, 60, '{"kind":"linhcan","add":1}',  'Tẩy kinh phạt tủy, linh căn +1.', 'pill'),
('dd_ngung_linh',   'Ngưng Linh Đan',         'danduoc', 2, 25, '{"kind":"linhcan","add":2}',  'Ngưng tụ linh căn, linh căn +2.', 'pill'),
('dd_thien_linh',   'Thiên Linh Đan',         'danduoc', 3, 10, '{"kind":"linhcan","add":4}',  'Linh đan hiếm có, linh căn +4.', 'pill'),
('dd_cuu_tay_linh', 'Cửu Chuyển Tẩy Linh Đan','danduoc', 4,  4, '{"kind":"linhcan","add":8}',  'Chín lần luyện chế, linh căn +8.', 'pill'),
('dd_tao_hoa',      'Hỗn Nguyên Tạo Hóa Đan', 'danduoc', 5,  1, '{"kind":"linhcan","add":16}', 'Đoạt tạo hóa trời đất, linh căn +16.', 'pill'),
-- Đan dược: buff tốc độ tu luyện (9)
('dd_tu_khi',       'Tụ Khí Đan',             'danduoc', 1, 120, '{"kind":"buff","pct":25,"hours":2}',  'Tốc độ tu luyện +25% trong 2 giờ.', 'gourd'),
('dd_bo_nguyen',    'Bổ Nguyên Đan',          'danduoc', 1, 100, '{"kind":"buff","pct":50,"hours":1}',  'Tốc độ tu luyện +50% trong 1 giờ.', 'gourd'),
('dd_linh_luc',     'Linh Lực Đan',           'danduoc', 2,  50, '{"kind":"buff","pct":50,"hours":4}',  'Tốc độ tu luyện +50% trong 4 giờ.', 'gourd'),
('dd_tinh_nguyen',  'Tinh Nguyên Đan',        'danduoc', 2,  40, '{"kind":"buff","pct":100,"hours":2}', 'Tốc độ tu luyện +100% trong 2 giờ.', 'gourd'),
('dd_long_ho',      'Long Hổ Đan',            'danduoc', 3,  18, '{"kind":"buff","pct":100,"hours":6}', 'Tốc độ tu luyện +100% trong 6 giờ.', 'gourd'),
('dd_tu_phu',       'Tử Phủ Đan',             'danduoc', 3,  15, '{"kind":"buff","pct":150,"hours":4}', 'Tốc độ tu luyện +150% trong 4 giờ.', 'gourd'),
('dd_thai_at',      'Thái Ất Chân Đan',       'danduoc', 4,   6, '{"kind":"buff","pct":200,"hours":6}', 'Tốc độ tu luyện +200% trong 6 giờ.', 'gourd'),
('dd_cuu_duong',    'Cửu Dương Thần Đan',     'danduoc', 4,   5, '{"kind":"buff","pct":300,"hours":4}', 'Tốc độ tu luyện +300% trong 4 giờ.', 'gourd'),
('dd_tien_nguyen',  'Tiên Nguyên Đan',        'danduoc', 5,   1, '{"kind":"buff","pct":500,"hours":6}', 'Tốc độ tu luyện +500% trong 6 giờ.', 'gourd'),
-- Đan dược: hộ thân đột phá (5)
('dd_ho_tam',       'Hộ Tâm Đan',             'danduoc', 1, 50, '{"kind":"hothan","pct":5}',  'Lần đột phá tới +5% tỷ lệ thành công.', 'shield_pill'),
('dd_dinh_than',    'Định Thần Đan',          'danduoc', 2, 22, '{"kind":"hothan","pct":8}',  'Lần đột phá tới +8% tỷ lệ thành công.', 'shield_pill'),
('dd_pha_canh',     'Phá Cảnh Đan',           'danduoc', 3,  9, '{"kind":"hothan","pct":12}', 'Lần đột phá tới +12% tỷ lệ thành công.', 'shield_pill'),
('dd_do_ach',       'Độ Ách Đan',             'danduoc', 4,  3, '{"kind":"hothan","pct":16}', 'Lần đột phá tới +16% tỷ lệ thành công.', 'shield_pill'),
('dd_tien_van',     'Tiên Vận Đan',           'danduoc', 5,  1, '{"kind":"hothan","pct":25}', 'Lần đột phá tới +25% tỷ lệ thành công.', 'shield_pill'),
-- Vũ khí (10)
('vk_thiet_kiem',   'Thiết Kiếm',             'vukhi', 1, 100, '{"rate_pct":3}',  'Kiếm sắt thường, có còn hơn không. Tốc độ +3%.', 'sword'),
('vk_dong_dao',     'Đồng Đao',               'vukhi', 1,  90, '{"rate_pct":4}',  'Đao đồng nặng tay. Tốc độ +4%.', 'saber'),
('vk_han_bang',     'Hàn Băng Kiếm',          'vukhi', 2,  40, '{"rate_pct":8}',  'Kiếm ngậm hàn khí. Tốc độ +8%.', 'sword'),
('vk_tu_kim',       'Tử Kim Thương',          'vukhi', 2,  35, '{"rate_pct":10}', 'Thương đúc tử kim. Tốc độ +10%.', 'spear'),
('vk_long_tuyen',   'Long Tuyền Kiếm',        'vukhi', 3,  15, '{"rate_pct":15}', 'Danh kiếm Long Tuyền. Tốc độ +15%.', 'sword'),
('vk_pha_quan',     'Phá Quân Kích',          'vukhi', 3,  12, '{"rate_pct":18}', 'Kích phá vạn quân. Tốc độ +18%.', 'spear'),
('vk_thien_tinh',   'Thiên Tinh Kiếm',        'vukhi', 4,   5, '{"rate_pct":25}', 'Rèn từ sắt sao trời. Tốc độ +25%.', 'sword'),
('vk_chu_tuoc',     'Chu Tước Cung',          'vukhi', 4,   4, '{"rate_pct":30}', 'Cung mang lửa Chu Tước. Tốc độ +30%.', 'bow'),
('vk_tien_thien',   'Tiên Thiên Kiếm',        'vukhi', 5,   1, '{"rate_pct":50}', 'Kiếm sinh trước trời đất. Tốc độ +50%.', 'sword'),
('vk_thi_than',     'Thí Thần Thương',        'vukhi', 5,   1, '{"rate_pct":60}', 'Thương từng thí thần. Tốc độ +60%.', 'spear'),
-- Pháp bảo (10)
('pb_la_ban',       'La Bàn Tầm Linh',        'phapbao', 1, 90, '{"rate_pct":5}',  'Chỉ hướng linh mạch. Tốc độ +5%.', 'compass'),
('pb_tui_ck',       'Túi Càn Khôn',           'phapbao', 1, 80, '{"rate_pct":6}',  'Túi chứa càn khôn thu nhỏ. Tốc độ +6%.', 'pouch'),
('pb_ngoc_boi',     'Ngọc Bội Hộ Thân',       'phapbao', 2, 40, '{"rate_pct":10}', 'Ngọc ấm dưỡng thần. Tốc độ +10%.', 'jade'),
('pb_tu_linh_tran', 'Tụ Linh Trận Bàn',       'phapbao', 2, 32, '{"rate_pct":12}', 'Bày trận tụ linh khí. Tốc độ +12%.', 'array'),
('pb_kim_quang',    'Kim Quang Kính',         'phapbao', 3, 15, '{"rate_pct":20}', 'Gương chiếu kim quang. Tốc độ +20%.', 'mirror'),
('pb_can_khon_dinh','Càn Khôn Đỉnh',          'phapbao', 3, 12, '{"rate_pct":22}', 'Đỉnh luyện càn khôn. Tốc độ +22%.', 'cauldron'),
('pb_ho_lo',        'Chiêu Linh Hồ Lô',       'phapbao', 4,  5, '{"rate_pct":35}', 'Hồ lô hút linh khí trăm dặm. Tốc độ +35%.', 'gourd_big'),
('pb_linh_thap',    'Thất Bảo Linh Tháp',     'phapbao', 4,  4, '{"rate_pct":38}', 'Tháp bảy báu trấn khí vận. Tốc độ +38%.', 'pagoda'),
('pb_hon_don_chau', 'Hỗn Độn Châu',           'phapbao', 5,  1, '{"rate_pct":70}', 'Châu báu khai thiên tích địa. Tốc độ +70%.', 'orb'),
('pb_thai_cuc_do',  'Thái Cực Đồ',            'phapbao', 5,  1, '{"rate_pct":75}', 'Đồ hình phân âm dương. Tốc độ +75%.', 'taiji'),
-- Pháp chú (8)
('pc_tinh_tam',     'Phù Tĩnh Tâm',           'phapchu', 1, 80, '{"bt_pct":2}',  'Giữ đạo tâm vững khi đột phá. Tỷ lệ +2%.', 'talisman'),
('pc_ho_the',       'Phù Hộ Thể',             'phapchu', 2, 38, '{"bt_pct":3}',  'Hộ thể trước phản phệ. Tỷ lệ đột phá +3%.', 'talisman'),
('pc_ngu_loi',      'Chú Ngự Lôi',            'phapchu', 2, 34, '{"bt_pct":4}',  'Ngự sấm sét hộ đạo. Tỷ lệ đột phá +4%.', 'talisman'),
('pc_kim_cang',     'Phù Kim Cang',           'phapchu', 3, 15, '{"bt_pct":5}',  'Thân cứng như kim cang. Tỷ lệ đột phá +5%.', 'talisman'),
('pc_pha_gioi',     'Chú Phá Giới',           'phapchu', 3, 12, '{"bt_pct":6}',  'Phá rào cản cảnh giới. Tỷ lệ đột phá +6%.', 'talisman'),
('pc_thien_loi',    'Chú Thiên Lôi Dẫn',      'phapchu', 4,  5, '{"bt_pct":8}',  'Dẫn thiên lôi tôi thể. Tỷ lệ đột phá +8%.', 'talisman'),
('pc_cuu_thien',    'Phù Cửu Thiên',          'phapchu', 4,  4, '{"bt_pct":9}',  'Mượn khí Cửu Thiên. Tỷ lệ đột phá +9%.', 'talisman'),
('pc_tien_van',     'Tiên Văn Cổ Chú',        'phapchu', 5,  1, '{"bt_pct":12}', 'Cổ chú khắc tiên văn. Tỷ lệ đột phá +12%.', 'talisman');
