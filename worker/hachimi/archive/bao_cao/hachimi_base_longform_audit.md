# Kiểm toán Hachimi gốc trên 225 chương liên tục

## Kết luận ngắn

Không nên train bộ register/booster cũ. Hachimi gốc đã dùng `hắn`, `ta` - `ngươi`
khá ổn trong truyện cổ phong; lỗi lớn hơn nằm ở **quan hệ ngữ nghĩa trong câu dài,
gắn sai chủ thể, thuật ngữ theo miền và bỏ/đổi chi tiết quan trọng**.

Finetune đầu tiên nên dùng 1.200 cặp được sửa tay từ cảnh thật. Không dùng tên riêng làm
mục tiêu học thuộc và không đưa nguồn bẩn vào train chỉ vì nó đã có bản dịch.

## Cách chạy

- Model: `ngocdang83/HachimiMT-60-zh-vi`, CT2 INT8 local.
- Pipeline: `clean_source → Hachimi gốc → termguard → hậu xử lý production`.
- Không gọi LLM, không ghi DB.
- Mỗi nhóm lấy 15 chương liên tiếp:

| Nhóm | Novel ID | Truyện | Chương |
|---|---:|---|---:|
| Tiên hiệp | 1256 | Ngũ Hành Tiên Đế | 1-15 |
| Huyền huyễn dị giới | 32 | Dị Giới Long Hồn | 1-15 |
| Hệ thống, vô hạn | 1380 | Ngày Tận Thế: Tỷ Lệ Bùng Nổ... | 1-15 |
| Game huyền huyễn | 282 | Thế giới game siêu thực | 1-15 |
| Khoa huyễn | 322 | Dải Ngân Hà, Ta Là Lãnh Chúa Hải Tặc | 1-15 |
| Võng du, hệ thống | 1382 | Chủng Loại Bất Tận | 1-15 |
| Xuyên không | 992 | Vũ Trụ Hoàn Mỹ | 1-15 |
| Huyền huyễn học viện | 205 | Pháp Sư Toàn Thời | 1-15 |
| Tiên hiệp chính kịch | 409 | Xích Tâm Tuần Thiên | 1-15 |
| Hệ thống, vô hạn cổ | 24 | Trò Chơi Luân Hồi: Ma Thú | 1-15 |
| Huyền huyễn, ngôn tình | 356 | Thiên Uyên | 1-15 |
| Kiếm đạo | 293 | Kiếm Đế Cuồng Thần | 1-15 |
| Lãnh chúa, hệ thống | 1320 | Toàn Dân Lãnh Chúa... | 1-15 |
| Ngự thú | 1306 | Ngự Thú, Từ Bạch Nguyệt Thiên Lang | 1-15 |
| Tiên hiệp dị bản | 3978 | Nghịch Long Đạo | 1-15 |

DB chỉ có 23 truyện đạt 10 chương Trung liên tiếp. Chưa có chuỗi đủ dài cho đô thị,
ngôn tình hoặc cổ đại thuần, nên không giả vờ đánh giá dài hạn các nhóm đó bằng một
chương rời.

## Số liệu

- 225 chương, 609.963 ký tự Trung, 16.631 dòng.
- Tổng thời gian model: 1.011,5 giây, trung bình 4,5 giây/chương trên máy local.
- Raw giữ đúng 16.631 dòng và không còn chữ Hán.
- Pipeline còn 16.630 dòng: hậu xử lý đã gộp nhầm hai đoạn ở truyện 205 chương 3.
- Hậu xử lý thay đổi 1.845/16.631 dòng (11,1%).
- Heuristic thấy raw có 107 dòng lặp cụm, hậu xử lý còn 50. Trong đó có cả lặp có
  chủ ý của tác giả, nên không được tự động coi toàn bộ là lỗi.
- 5.089 dòng nguồn có lời thoại:
  - 42 dòng nguồn đã lệch/mất dấu ngoặc;
  - raw có 115 dòng lệch;
  - model tự tạo thêm 85 ca lệch dù nguồn cân bằng.
- 1.083 dòng chứa chữ số Ả Rập; heuristic gắn cờ 51 dòng. Một số là quy đổi hợp lệ,
  nhưng đã xác nhận có ca mất `8:00` và mất cấp `t2`.

Các con số trên là kiểm tra cấu trúc, không được coi là điểm chất lượng dịch.

## Lỗi đọc thấy

### 1. Đảo hoặc làm mất nghĩa cốt lõi

Nguồn:

> 想要飞行谈何容易

Model:

> muốn bay thì dễ

`谈何容易` phải mang nghĩa “nào có dễ”. Đây là lỗi đảo nghĩa, không phải vấn đề văn
phong.

Nguồn có khung giờ `下午8:00到第二天早上6:00`, nhưng pipeline chỉ còn:

> là 6:00 đến sáng ngày hôm sau

Nguồn `t2重型攻击护卫舰` bị dịch thành “chiến hạm tấn công hạng nặng”, mất hẳn `t2`.

Ở truyện 32, một câu giới thiệu cấp bậc bỏ mất mệnh đề “đại lục hiện còn không quá
50 cao thủ Thánh cấp, Long gia có hai người”, khiến câu sau “lần lượt là...” không còn
đối tượng.

### 2. Gắn sai chủ thể và quan hệ

Truyện 32 vẫn là ca nặng nhất:

- quan hệ cha/con và tuổi bị gắn nhầm trong câu giới thiệu Long gia;
- `玛利亚` có lúc thành Mã Lợi Á, có lúc Marya;
- đoạn Maria chăm sóc Ngạo Thiên đổi qua lại giữa `hắn`, `nàng`, `mình`;
- `暗夜战` có lúc bị hiểu thành “chiến tranh đêm tối”.

Một phần do nguồn cũ nhiều lỗi chính tả và câu quá dài, nhưng model cũng không giữ
được cây quan hệ ngay trong cùng câu.

### 3. Thuật ngữ miền bị dịch theo nghĩa phổ thông

| Nguồn | Model | Nghĩa cần dùng |
|---|---|---|
| `顺劈` | thuận tiện chém | bổ/chém quét |
| `暴率/爆率` | tỷ lệ bạo lực/bùng nổ | tỷ lệ rơi đồ |
| `爆出装备` | bắn/rò rỉ trang bị | rơi trang bị |
| `七成熟的西冷牛排` | bít tết lạnh lẽo bảy chín | bít tết sirloin chín bảy phần |
| `榔头` | xà phòng | búa |
| `电离` | tia chớp cắt đứt | ion hóa |
| `公证处` | Công Chứng Xử | cơ quan/văn phòng công chứng |

Đây là nhóm phù hợp cho gold theo miền và glossary cụm từ. Không cần một booster đại
từ lớn để sửa chúng.

### 4. Câu dài bị rơi vai trò hoặc bám chữ

Các câu nhiều mệnh đề thường có:

- định ngữ gắn nhầm danh từ;
- chủ ngữ bị rơi ở mệnh đề sau;
- một cụm được dịch hai lần;
- viết hoa tùy tiện sau dấu phẩy;
- văn convert như “khẩu vị mở rộng”, “ngữ trọng tâm dạy bảo”, “mò mẫm ra cửa”.

Raw có ví dụ lặp nguyên cụm `theo phương thức Ngũ Hành Trường Sinh Công` hai lần.
Hậu xử lý xóa được phần lớn lặp bề mặt nhưng không sửa được gắn sai nghĩa.

### 5. Xưng hô không phải lỗi lớn nhất, nhưng chưa ổn định

Trong tiên hiệp/xuyên không, Hachimi gốc đã thường xuyên dùng đúng `hắn`,
`ta` - `ngươi`. Vì vậy không nên lặp lại 1.200 câu booster slot đơn giản.

Các lỗi còn đáng dạy:

- hiện đại/khoa huyễn đôi lúc dùng `tôi`, `các người`;
- cùng một lượt có `ngài` rồi chuyển sang `ngươi`;
- đệ tử nói với sư phụ thành “truyền cho **con** rồi chứ”;
- trẻ nhỏ đôi lúc được kể bằng `cậu` thay vì `hắn`.

Từ `mình` trong “nhìn bàn tay mình” là phản thân tự nhiên, không được hard-reject.

### 6. Lời tác giả đã được giữ

Chương 6 của Vũ Trụ Hoàn Mỹ có lời tác giả xin độc giả bấm, bỏ phiếu và lưu truyện.
Model đã dịch đủ. Không cần tạo data “khôi phục lời tác giả”; chỉ cần bảo đảm bộ lọc
train không loại nhầm loại đoạn này.

### 7. Lỗi không nên giao cho finetune

- Tên riêng thay đổi theo truyện: tiếp tục dùng glossary + termguard.
- Nguồn `**`, sai chữ, thiếu ngoặc hoặc câu tự mâu thuẫn: sửa ở crawl/clean hoặc cách
  ly khỏi train.
- Nhất quán cần thông tin ở dòng trước: model hiện dịch từng dòng nên finetune không
  thể suy ra ngữ cảnh mà engine không đưa vào.
- Rơi chữ số/model ID: cần gate deterministic bên cạnh data; không đặt toàn bộ niềm
  tin vào model.

## Bộ data nên làm tiếp

### Eval trước, không dùng để train

Khóa 300 cảnh từ 225 chương: mỗi chương có ít nhất một cảnh, 75 cảnh còn lại lấy ở
những chương có câu dài, nhiều nhân vật hoặc UI hệ thống. Sửa tay đầy đủ, giữ metadata
`novel_id`, chương, dòng và nhóm lỗi. Đây là tập quyết định model có thực sự tốt lên
hay chỉ đổi cách viết.

### Gold pilot: 1.200 cặp

| Nhóm | Số cặp | Nội dung |
|---|---:|---|
| Câu dài, chủ thể và quan hệ | 400 | định ngữ, nhiều nhân vật, quan hệ gia đình/tông môn |
| Hội thoại và vai nói | 200 | lời dẫn + lời thoại, ta-ngươi, kính ngữ nhất quán |
| Thuật ngữ game/hệ thống/khoa huyễn | 240 | rơi đồ, kỹ năng, cấp tàu, UI, trang bị |
| Phủ định, số, cấp bậc, thêm-bớt | 160 | `谈何容易`, giờ, tỷ lệ, model ID, điều kiện |
| Ngoặc thoại và lời tác giả | 100 | nguồn cân bằng, không tự thêm/bỏ dấu hay meta |
| Việt hóa tự nhiên nhưng giữ nghĩa | 100 | sửa văn convert, không viết lại nội dung |

Mỗi cặp phải được duyệt ở dạng:

`ZH | bản Hachimi gốc | lỗi cụ thể | bản đề xuất`

Không lấy bản `content_vi` hiện có làm gold mặc định. Không sinh hàng loạt bằng slot.

### Replay

Chỉ sau khi 1.200 gold đã khóa mới lấy 10.000-20.000 replay sạch để chống quên. Replay
không được lặp, xung đột, dính eval hoặc chứa nguồn crawl lỗi. Không dùng cờ đại từ
đơn lẻ để loại tự động.

## Quyết định train

Train hai ứng viên từ model gốc:

- A: replay ×1 + gold ×1;
- B: replay ×1 + gold ×3.

Chỉ mở rộng gold nếu eval chỉ ra một nhóm vẫn không tiến bộ. Không xây booster mới,
không train tên riêng và không tăng số epoch trước khi hai thử nghiệm nhỏ này thất bại.
