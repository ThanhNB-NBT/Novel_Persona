-- 050: Pháp bảo VÒNG SÁNG (halo) — đeo vào là vòng sau đầu nhân vật đổi kiểu.
-- effect.halo = kiểu vẽ client (nguyet/tinh/loi/kim — docs/tu-tien.md §2-3);
-- vẫn là type phapbao nên dùng chung slot equip_phapbao, không đổi schema.
-- weight bỏ dùng từ 049 (rơi đồ uniform) — điền 10 cho có.

insert into cult_items (code, name, type, grade, weight, effect, descr, pixel) values
('pb_vong_nguyet', 'Nguyệt Quang Hoàn', 'phapbao', 2, 10,
 '{"rate_pct":6,"halo":"nguyet"}',
 'Hai lưỡi trăng non ôm sau đầu, quay ngược chiều nhau toả nguyệt hoa.', 'halo'),
('pb_vong_tinh', 'Tinh Thần Hoàn', 'phapbao', 3, 10,
 '{"rate_pct":10,"halo":"tinh"}',
 'Vòng sao vây quanh, đêm càng sâu sao càng sáng.', 'halo'),
('pb_vong_loi', 'Lôi Đình Hoàn', 'phapbao', 4, 10,
 '{"rate_pct":15,"halo":"loi"}',
 'Vành sấm răng cưa nổ lách tách, tà ma không dám lại gần.', 'halo'),
('pb_vong_kim', 'Kim Quang Phật Hoàn', 'phapbao', 5, 10,
 '{"rate_pct":25,"halo":"kim"}',
 'Kim quang vạn trượng sau đầu, thấp thoáng phạn âm.', 'halo')
on conflict (code) do nothing;
