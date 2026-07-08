-- Đa dạng icon vật phẩm: trước đây cả loại dùng chung 1 sprite (12 công pháp
-- đều là sách, 8 pháp chú đều là phù giấy). Gán sprite mới đã thêm phía app:
-- scroll (cuộn trục), slip (thẻ ngọc), fan (quạt), seal (ấn chú).
-- Chỉ đổi cột hiển thị `pixel`, không đụng cơ chế.

update cult_items set pixel = 'scroll'
  where code in ('cp_luyen_the', 'cp_dia_sat', 'cp_thien_cang', 'cp_hon_don');
update cult_items set pixel = 'slip'
  where code in ('cp_huyen_bang', 'cp_cuu_chuyen', 'cp_dai_dien');
update cult_items set pixel = 'fan' where code = 'cp_ngu_phong';
update cult_items set pixel = 'seal'
  where code in ('pc_ho_the', 'pc_kim_cang', 'pc_thien_loi', 'pc_tien_van');
