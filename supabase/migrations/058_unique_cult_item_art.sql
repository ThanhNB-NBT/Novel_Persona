-- Ảnh riêng cho các món cấp cao đang dùng chung minh họa với nhiều món khác.
update cult_items set pixel = case code
  when 'dd_thai_hu' then 'void_pill'
  when 'vk_diet_the' then 'demonic_saber'
  when 'pb_cuu_long_dinh' then 'dragon_cauldron'
  when 'yp_cuu_thien_y' then 'celestial_robe'
end
where code in ('dd_thai_hu', 'vk_diet_the', 'pb_cuu_long_dinh', 'yp_cuu_thien_y');
