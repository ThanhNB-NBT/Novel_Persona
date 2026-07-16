-- LINH CĂN v3 (sửa 067 theo ý user 2026-07-16): BẬC tách hẳn khỏi HỆ.
--   • Hệ (elements + variant) CỐ ĐỊNH — chỉ Chuyển Linh Đan tráo bộ hệ (giữ số hệ).
--   • Bậc = thang 7 nấc: Ngũ Hành Tạp(1) → Tứ(2) → Tam(3) → Song(4) → Đơn(5)
--     → Dị Linh Căn(6) → Tiên Linh Căn(7). Bậc GỐC suy từ hệ: số hệ ít = bậc cao
--     (5 hệ → Tạp, 1 hệ → Đơn); dị căn bẩm sinh (kiem/loi/bang/phong/am/…) vào
--     thẳng bậc Dị; thien/hon vào thẳng bậc Tiên (hon thêm hợp mọi công pháp).
--   • Đan luyện căn (kind 'linhcan') cộng ĐIỂM (cột linh_can, giữ nguyên cột):
--     điểm thăng BẬC, chi phí gấp đôi mỗi bậc (5→10→20→40→80→160), càng cao càng
--     khó. Điểm lẻ nội suy tuyến tính trong bậc; quá trần Tiên thì +10%/điểm.
--   • Tốc độ CẤP SỐ NHÂN: ×2 mỗi bậc (Tạp ×1 … Tiên ×64).
-- Mirror app PHẢI khớp: linhCanMult/rootName trong app/lib/cultivation.dart.

-- Chữ ký cũ (067) không còn chỗ gọi — dọn để khỏi nhầm bản.
drop function if exists cult_linhcan_mult(text[], text);

create or replace function cult_linhcan_mult(p_elements text[], p_variant text, p_linh_can int)
returns numeric language plpgsql immutable as $$
declare
  b int;                                    -- bậc hiện tại (1..7)
  rem int := greatest(0, coalesce(p_linh_can, 1) - 1);  -- điểm luyện căn
  cost int;
begin
  b := case
    when p_variant in ('thien', 'hon') then 7
    when p_variant is not null then 6
    else 6 - least(coalesce(array_length(p_elements, 1), 5), 5)
  end;
  while b < 7 loop
    cost := 5 * (2 ^ (b - 1))::int;         -- 5,10,20,40,80,160
    exit when rem < cost;
    rem := rem - cost;
    b := b + 1;
  end loop;
  if b < 7 then
    -- điểm lẻ: nhích dần về bậc kế (đủ cost thì đúng ×2)
    return (2 ^ (b - 1))::numeric * (1 + rem::numeric / (5 * (2 ^ (b - 1))::int));
  end if;
  return 64 * (1 + 0.1 * rem);              -- trần Tiên: +10%/điểm dư
end $$;

-- cult_base_rate (đè 067): bậc linh căn đã GỘP điểm luyện căn — bỏ hệ số refine rời.
create or replace function cult_base_rate(c user_cultivation) returns numeric
language sql stable as $$
  select 1
    * cult_mult((select grade from cult_items where id = c.equip_congphap))
    * case when c.variant = 'hon'
             or (select i.effect->>'element' from cult_items i where i.id = c.equip_congphap)
                = any (array_append(c.elements, 'all'))
           then 1.3 else 1 end
    * cult_linhcan_mult(c.elements, c.variant, c.linh_can)
    * case when c.race = 'ma' then 1.10 else 1 end
    * (1 + 0.2 * coalesce(c.tien_tier, 0))
    * (1 + coalesce((select sum((effect->>'rate_pct')::numeric) from cult_items
         where id in (c.equip_vukhi, c.equip_phapbao)), 0) / 100);
$$;
