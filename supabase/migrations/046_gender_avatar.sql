-- 046: giới tính nhân vật (nam/nữ) + admin đổi tộc/giới tính tự do.
-- Giới tính CHỈ ảnh hưởng hiển thị; hệ số gốc vẫn theo tộc như 044.

alter table user_cultivation
  add column if not exists gender text not null default 'nam'
    check (gender in ('nam', 'nu'));

-- Chọn dung mạo (tộc + giới tính) — thay cult_set_race(text).
-- User thường: MỘT lần duy nhất (khi race còn null). Admin: đổi tự do.
create or replace function cult_set_avatar(p_race text, p_gender text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'chưa đăng nhập'; end if;
  if p_race not in ('nhan', 'yeu', 'ma', 'linh') then
    raise exception 'chủng tộc không hợp lệ';
  end if;
  if p_gender not in ('nam', 'nu') then
    raise exception 'giới tính không hợp lệ';
  end if;
  perform cult_tick(auth.uid()); -- đảm bảo có dòng
  if exists (select 1 from profiles where id = auth.uid() and is_admin) then
    update user_cultivation set race = p_race, gender = p_gender
    where user_id = auth.uid();
  else
    update user_cultivation set race = p_race, gender = p_gender
    where user_id = auth.uid() and race is null;
    if not found then
      raise exception 'đã chọn xuất thân rồi — nghịch thiên cải mệnh không dễ vậy';
    end if;
  end if;
  return cult_state();
end $$;
grant execute on function cult_set_avatar(text, text) to authenticated;

drop function if exists cult_set_race(text);

-- state: thêm gender (đè bản 044).
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
