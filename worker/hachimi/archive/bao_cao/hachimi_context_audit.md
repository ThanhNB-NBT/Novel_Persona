# Audit ngữ cảnh Hachimi — truyện 32

## Kết luận ngắn

Không checkpoint nào hiện đủ tốt để tối ưu bằng vài regex hậu xử lý. Lỗi đến từ
bốn tầng: nguồn Trung bẩn, chia câu mất ngữ cảnh, glossary thiếu và dữ liệu
fine-tune dạy xưng hô quá tuyệt đối.

## Đánh giá theo cảnh

| Cảnh | Fine-tune hiện tại | Hachimi gốc | Nhận xét về nghĩa |
|---|---|---|---|
| Giới thiệu đại lục và Long gia | Giữ số tốt hơn sau hậu xử lý, nhưng sai quan hệ gia đình và có câu vô nghĩa | Đảo hàng loạt số, sai quan hệ tương tự | Chưa bản nào đạt mức đọc tin cậy |
| Ngạo Thiên và dì Maria | Giữ đúng register `ta`, nhưng Maria thành Marya/Malia và nhầm chủ thể trong độc thoại của dì | Có lúc tự đổi sang `cháu/con`, tên vẫn dao động và tham chiếu vẫn sai | Fine-tune hợp register hơn base; lỗi thật nằm ở tên và chủ thể |
| Khách đến Long gia | Tách một lượt thoại thành nhiều cặp ngoặc; đảo `Tả tướng`; tên có `*` bị vỡ | Ít ngoặc lồng hơn nhưng vẫn đảo chức danh và tên | Lỗi chia câu cộng với nguồn bẩn |
| Công bố hôn ước | Nhầm cấu trúc liên hôn, lặp Hoa gia, dịch sai quan hệ cháu gái | Cũng không giữ được đầy đủ quan hệ | Đây là lỗi hiểu câu, không phải lỗi từ đơn |
| Lễ tẩy lễ | `耶` thành “Yah”, nhiều câu Hán-Việt máy móc | Đọc `耶` thành “Da”, đảo số nặng | Khi dịch cả đoạn, cả hai hiểu `耶` là “cũng” nhưng lại phá số |
| Ngạo Thiên bị ruồng bỏ | Đại từ `hắn/ta/mình` đổi giữa cùng một dòng; thoại gia đình bị xé | Có cùng loại lỗi, mức độ khác nhau | Cần gold theo cảnh và vai giao tiếp |

## Những câu người đọc hỏi

- Phần “Ngạo Thiên ngẩng đầu, nói với người phụ nữ này” có trong nguồn:
  `傲天抬起头，对这个女人说道！`; model không tự thêm.
- `玛利亚` là dì Maria. `暗莲` là Ám Liên, mẹ ruột của Ngạo Thiên, nên đây là
  hai người khác nhau.
- Dòng sau nguồn lại viết `玛丽莲` (Marilyn). Theo diễn biến, đây gần như chắc
  là tác giả gõ sai tên cùng một người.
- `“你不会吧？连这都问呀？...”` là một lượt thoại duy nhất. Bộ chia câu hiện tại
  đã xé nó thành nhiều lượt.
- `摩尔多左相到` phải hiểu là “Tả tướng Ma Nhĩ Đa đến”, không phải
  “Mordo đến Tả Tướng”.
- `/`, `( )` và dấu `*` trong tên có nguyên văn trong DB.
- Lời nhắn tác giả không bị runtime loại. Cả hai checkpoint đều dịch các dòng
  “xin sưu tầm/để lại lời nhắn” và giới thiệu sách của tác giả. Chỉ có 19 mẫu
  lời tác giả bị loại khỏi bộ gold sửa xưng hô vì không thuộc mục tiêu của bộ
  đó; chúng không bị xóa khỏi chương.

## Vấn đề trong dữ liệu fine-tune

- `train_gold_vnext.jsonl`: 8.060 dòng nhưng có 1.200 cặp trùng hoàn toàn.
- Booster có 1.200 cặp duy nhất, được chép thành 2.400 dòng rồi còn nhân
  `gold-repeat=5`: hiệu lực thành 12.000 lượt.
- Trong 779 dòng có `我` và dấu hiệu lời thoại, 726 bản đích chứa `ta`
  (khoảng 93%). Tỉ lệ này phù hợp quy ước `ta–ngươi`; không được coi `ta` trong
  lời thoại trẻ–người lớn là lỗi chỉ vì văn hiện đại thường dùng `cháu/con`.
- Gold register có hàng chưa đạt chuẩn nhưng mang trạng thái approved, ví dụ
  `Ngạo ThiênMaria` dính tên và các đoạn đổi sai chủ thể. `approved` ở đây là
  trạng thái nhập dữ liệu, không chứng minh đã được người đọc duyệt nghĩa.

## Mức độ bẩn của nguồn truyện 32

DB hiện chỉ có 19 chương cho truyện này. Cả 19/19 chương đều có `/` rác cuối
đoạn, một dòng ngoặc rỗng và mất cân bằng ngoặc thoại. Ngoài ra:

- 56 vị trí `**` làm mất nội dung ở 12 chương.
- 95 dấu `*` nằm giữa hai chữ Hán ở 17 chương, chủ yếu là dấu phân cách tên bị
  mã hóa sai.
- 14 chữ `耶` khả nghi ở 4 chương.

Vì lỗi có hệ thống trên toàn bộ truyện, source cleaner chỉ cứu được hình thức.
Muốn phục hồi phần bị `**` che mất và các lỗi từ vựng của tác giả thì phải có
nguồn sạch hơn; model dịch không thể suy ra chắc chắn chữ đã mất.

## Kế hoạch tối ưu

### 1. Sửa đầu vào chắc chắn, không đoán nội dung

- Bỏ dòng chỉ có ngoặc hoặc dấu gạch chéo; bỏ `/` rác ở cuối đoạn.
- Đổi `*` nằm giữa hai cụm tên Hán thành dấu phân cách tên; không đụng `*1`,
  `*2` của vật phẩm game.
- Cân bằng dấu ngoặc thoại bị gõ nhầm trước khi chia câu.
- Không tự sửa các chỗ mất chữ `**`. Với truyện 32, ưu tiên recrawl nguồn sạch;
  model không thể phục hồi phần nguồn đã mất.

### 2. Chia theo đơn vị nghĩa

- Giữ nguyên toàn bộ lời thoại cùng câu dẫn và người nói.
- Văn kể vẫn chia ở ranh giới câu để model 57M không quá tải.
- Chỉ chia nhỏ hơn khi output thật sự chạm trần; không chia mọi dấu `？/！`
  nằm bên trong cùng một lượt thoại.

Thử nghiệm cho thấy giữ nguyên cả đoạn không phù hợp: tuy hết “Yah” và hết xé
thoại, model bắt đầu lặp ý, đảo số và nhầm chủ thể nhiều hơn.

### 3. Glossary theo nhân vật, không bắt model tự nhớ tên

- Bổ sung sau khi người dùng duyệt:
  - `玛利亚 → Maria`
  - `玛丽莲 → Maria` nếu xác nhận đây là lỗi tên của cùng nhân vật
  - tên đầy đủ có dấu `*`, thay vì ép từng nửa tên
- Mẫu thử phải dùng `db.get_glossary()` giống production. Bản mẫu cũ chỉ lấy
  `approved=true`, nên báo sai `glossary: 0 term`; production hiện có 41 term
  an toàn cho truyện 32.

### 4. Làm lại dữ liệu xưng hô trước khi train tiếp

- Xóa bản sao booster; giữ `ta–ngươi` làm register mặc định của lời thoại.
- Không tự chuyển sang `cháu/con/tôi/bạn` theo tuổi tác hoặc bối cảnh hiện đại.
  Quan hệ và mức tôn kính thể hiện bằng danh xưng (`dì`, `thúc thúc`, `sư phụ`,
  `tiền bối`), còn lời kể ngôi ba giữ `hắn/nàng`.
- Audit lại 660 register gold theo cả đoạn và quan hệ nhân vật. Không dùng lại
  hàng chỉ được máy sửa nhưng chưa duyệt nghĩa.
- Giữ các lời nhắn tác giả trong replay; không cần tăng trọng số vì model gốc
  và fine-tune đều đã dịch được.

### 5. Gate đánh giá mới

Lập bộ cố định khoảng 30 cảnh, không phải 30 câu rời. Mỗi cảnh chấm:

1. Đúng người, quan hệ và chủ thể hành động.
2. Đúng phủ định, số lượng, nhân quả và diễn biến.
3. Giữ lượt thoại và xác định đúng người nói.
4. Xưng hô nhất quán với vai.
5. Không thêm/bỏ mệnh đề.
6. Tên và thuật ngữ nhất quán.
7. Câu Việt tự nhiên.

Exact-string, số và dấu ngoặc chỉ là kiểm tra phụ. Chỉ train bản kế tiếp sau khi
người dùng duyệt các cặp `ZH | bản hiện tại | lỗi nghĩa | bản đề xuất`.

## Thứ tự thử tiếp theo

1. A/B bộ chia hiện tại với bộ chia giữ nguyên lượt thoại trên 30 cảnh.
2. A/B base và fine-tune với cùng source cleaner, glossary và decoder.
3. Duyệt lại gold xưng hô; tạo checkpoint mới từ base, không tiếp tục từ
   checkpoint hiện tại.
4. Chỉ chọn checkpoint nếu thắng theo điểm cảnh và không lùi các gate số,
   tên, cắt cụt.
