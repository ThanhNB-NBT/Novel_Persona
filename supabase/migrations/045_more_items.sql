-- MỞ RỘNG KHO VẬT PHẨM: thêm ~34 món trải đều mọi loại + phẩm để quà rơi phong
-- phú hơn (drop = weighted sampling theo cửa sổ grade trong cult_claim_gift → món
-- mới tự vào pool, KHÔNG cần đổi code). Bám đúng quy ước effect từng loại:
--   congphap {} | {element}   · danduoc {kind:...}  · linhthach {kind:stone}
--   vukhi {atk}  · phapbao {rate_pct}  · yphuc {def,hp}  · giay {agi}  · phapchu {bt_pct}
-- Trọng số theo phẩm (to = dễ rơi): g1 ~80-110 · g2 ~30-45 · g3 ~9-16 · g4 ~5 · g5 ~1.
-- Sprite trộn cho đỡ trùng (theo 041): công pháp book/scroll/slip · pháp chú talisman/seal.
-- Idempotent: on conflict (code) do nothing.

insert into cult_items (code, name, type, grade, weight, effect, descr, pixel) values
-- Công pháp: lấp hệ ngũ hành còn thiếu ở các phẩm
('cp_hoa_chung',    'Hỏa Chủng Quyết',            'congphap', 1, 85, '{"element":"hoa"}',  'Gieo hỏa chủng vào đan điền, khí huyết bừng bừng.', 'scroll'),
('cp_thuy_van',     'Thủy Vân Công',              'congphap', 1, 85, '{"element":"thuy"}', 'Dẫn thủy khí nhu hòa, tu hành uyển chuyển.', 'slip'),
('cp_kim_cang_co',  'Kim Cang Cơ',                'congphap', 2, 32, '{"element":"kim"}',  'Rèn nền kim cang, khí kình sắc bén.', 'book'),
('cp_thuong_hai',   'Thương Hải Triều Sinh Kinh', 'congphap', 3, 13, '{"element":"thuy"}', 'Linh lực cuộn trào như triều dâng biển lớn.', 'scroll'),
('cp_thanh_van_moc','Thanh Vân Mộc Đế Kinh',      'congphap', 4,  4, '{"element":"moc"}',  'Sinh cơ mộc đế, cây khô gặp cũng nảy chồi.', 'slip'),
-- Đan dược: buff tốc độ (lấp khoảng giữa các mốc cũ)
('dd_ngung_khi',    'Ngưng Khí Đan',   'danduoc', 1, 110, '{"kind":"buff","pct":40,"hours":2}',  'Tốc độ tu luyện +40% trong 2 giờ.', 'gourd'),
('dd_thanh_tam',    'Thanh Tâm Đan',   'danduoc', 2,  45, '{"kind":"buff","pct":75,"hours":3}',  'Tốc độ tu luyện +75% trong 3 giờ.', 'gourd'),
('dd_dao_nguyen',   'Đạo Nguyên Đan',  'danduoc', 3,  16, '{"kind":"buff","pct":120,"hours":5}', 'Tốc độ tu luyện +120% trong 5 giờ.', 'gourd'),
('dd_thai_hu',      'Thái Hư Đan',     'danduoc', 4,   5, '{"kind":"buff","pct":250,"hours":5}', 'Tốc độ tu luyện +250% trong 5 giờ.', 'gourd'),
-- Đan dược: linh căn + hộ thân
('dd_ngoc_dich',    'Ngọc Dịch Đan',   'danduoc', 3,   9, '{"kind":"linhcan","add":5}',  'Ngọc dịch nhuận linh, linh căn +5.', 'pill'),
('dd_an_than',      'An Thần Đan',     'danduoc', 1,  55, '{"kind":"hothan","pct":4}',   'Lần đột phá tới +4% tỷ lệ thành công.', 'shield_pill'),
('dd_co_ban',       'Cố Bản Đan',      'danduoc', 3,   9, '{"kind":"hothan","pct":10}',  'Lần đột phá tới +10% tỷ lệ thành công.', 'shield_pill'),
-- Vũ khí (atk): đa dạng đao/thương/cung
('vk_lieu_diep',    'Liễu Diệp Đao',   'vukhi', 1, 95, '{"atk":14}',  'Đao mỏng như lá liễu. Công +14.', 'saber'),
('vk_thanh_phong',  'Thanh Phong Kiếm','vukhi', 2, 38, '{"atk":36}',  'Kiếm nhẹ như gió thoảng. Công +36.', 'sword'),
('vk_huyet_mang',   'Huyết Mang Đao',  'vukhi', 3, 14, '{"atk":66}',  'Đao khát máu, chém là thấy đỏ. Công +66.', 'saber'),
('vk_pha_khong',    'Phá Không Thương','vukhi', 3, 12, '{"atk":70}',  'Thương xuyên hư không. Công +70.', 'spear'),
('vk_cuu_u',        'Cửu U Huyền Cung','vukhi', 4,  5, '{"atk":110}', 'Cung bắn tên từ Cửu U. Công +110.', 'bow'),
('vk_diet_the',     'Diệt Thế Ma Đao', 'vukhi', 5,  1, '{"atk":220}', 'Ma đao từng chém rụng một phương trời. Công +220.', 'saber'),
-- Pháp bảo (rate_pct): sprite gương/quạt/bát/tháp/trận
('pb_thanh_dong_kinh','Thanh Đồng Cổ Kính','phapbao', 1, 85, '{"rate_pct":5}',  'Gương đồng cổ soi linh khí. Tốc độ +5%.', 'mirror'),
('pb_ngu_hanh_phan',  'Ngũ Hành Phan',     'phapbao', 2, 34, '{"rate_pct":11}', 'Phướn dẫn ngũ hành linh khí. Tốc độ +11%.', 'fan'),
('pb_tu_kim_bat',     'Tử Kim Bát',        'phapbao', 3, 14, '{"rate_pct":21}', 'Bát tử kim thu nhiếp linh khí. Tốc độ +21%.', 'cauldron'),
('pb_cuu_long_dinh',  'Cửu Long Đỉnh',     'phapbao', 4,  5, '{"rate_pct":36}', 'Đỉnh chín rồng luyện linh. Tốc độ +36%.', 'pagoda'),
('pb_tinh_than_do',   'Tinh Thần Đồ',      'phapbao', 5,  1, '{"rate_pct":72}', 'Đồ hình sao trời dẫn khí chu thiên. Tốc độ +72%.', 'array'),
-- Y phục (def+hp)
('yp_thanh_giao',   'Thanh Giao Bào',     'yphuc', 2, 38, '{"def":13,"hp":90}',   'Bào dệt tơ giao xanh. Thủ +13, khí huyết +90.', 'robe'),
('yp_bach_lan',     'Bạch Lân Bảo Giáp',  'yphuc', 3, 13, '{"def":28,"hp":160}',  'Giáp ghép vảy bạch lân. Thủ +28, khí huyết +160.', 'robe'),
('yp_cuu_thien_y',  'Cửu Thiên Huyền Y',  'yphuc', 5,  1, '{"def":95,"hp":580}',  'Tiên y từ Cửu Thiên, trần ai bất nhiễm. Thủ +95, khí huyết +580.', 'robe'),
-- Hài (agi)
('gi_van_tung',     'Vân Tung Ngoa',      'giay', 2, 38, '{"agi":13}', 'Bước đi để lại vệt mây. Thân pháp +13.', 'boot'),
('gi_liet_hoa_hai', 'Liệt Hỏa Hài',       'giay', 3, 13, '{"agi":27}', 'Hài phun hỏa đẩy thân đi nhanh. Thân pháp +27.', 'boot'),
('gi_hu_khong',     'Hư Không Ngoa',      'giay', 4,  5, '{"agi":48}', 'Đạp hư không mà tiến. Thân pháp +48.', 'boot'),
-- Pháp chú (bt_pct): talisman/seal
('pc_ngung_than',   'Phù Ngưng Thần',     'phapchu', 1, 78, '{"bt_pct":2}', 'Ngưng thần định khí trước đột phá. Tỷ lệ +2%.', 'talisman'),
('pc_tran_hon',     'Ấn Trấn Hồn',        'phapchu', 3, 13, '{"bt_pct":5}', 'Ấn trấn tam hồn khỏi tán loạn. Tỷ lệ đột phá +5%.', 'seal'),
('pc_thai_thuong',  'Thái Thượng Lệnh Phù','phapchu',4,  5, '{"bt_pct":9}', 'Phù mang uy Thái Thượng. Tỷ lệ đột phá +9%.', 'seal'),
-- Linh thạch (stone): thêm mốc trung gian
('lt_linh_tinh',    'Linh Tinh Sa',       'linhthach', 1, 95, '{"kind":"stone","pct":25,"hours":6}',  'Cát linh tinh vụn, tốc độ +25% trong 6 giờ.', 'stone'),
('lt_bich_tinh',    'Bích Tinh Thạch',    'linhthach', 3, 16, '{"kind":"stone","pct":80,"hours":18}', 'Thạch xanh biếc, tốc độ +80% trong 18 giờ.', 'stone')
on conflict (code) do nothing;
