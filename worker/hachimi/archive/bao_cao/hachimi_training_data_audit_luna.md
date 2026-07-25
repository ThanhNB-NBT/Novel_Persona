# Kiểm toán dữ liệu fine-tune Hachimi — Luna

Phạm vi: đọc toàn bộ JSONL dưới `worker/hachimi_finetune`; không train, không DB, không sửa gold. `status=approved` chỉ là trạng thái trong file, không phải bằng chứng người duyệt.

## 1. Thống kê toàn bộ JSONL

| Tập | Dòng | Cặp duy nhất | Trùng cặp dư | ZH trùng | ZH xung đột VI | JSON lỗi |
|---|---:|---:|---:|---:|---:|---:|
| `_kaggle_upload/train_gold_vnext.jsonl` | 8060 | 6860 | 1200 | 1201 | 1 | 0 |
| `_kaggle_upload/train_v2.jsonl` | 87338 | 87338 | 0 | 0 | 0 | 0 |
| `approved_gold.jsonl` | 5000 | 5000 | 0 | 0 | 0 | 0 |
| `dataset/booster.jsonl` | 1200 | 1200 | 0 | 0 | 0 | 0 |
| `dataset/error_cases.jsonl` | 687 | 687 | 0 | 0 | 0 | 0 |
| `dataset/labeled_gold.jsonl` | 687 | 687 | 0 | 0 | 0 | 0 |
| `dataset/labeled_gold_sample.jsonl` | 40 | 40 | 0 | 0 | 0 | 0 |
| `dataset/raw_zh.jsonl` | 2320 | 2320 | 0 | 0 | 0 | 0 |
| `dataset/register_gold.jsonl` | 660 | 660 | 0 | 0 | 0 | 0 |
| `dataset/train_gold_vnext.jsonl` | 8060 | 6860 | 1200 | 1201 | 1 | 0 |
| `dataset/train_v2.jsonl` | 87338 | 87338 | 0 | 0 | 0 | 0 |
| `source_pool.jsonl` | 4800 | 4800 | 0 | 0 | 0 | 0 |

`_kaggle_upload/` chứa bản sao của `dataset/` cho hai manifest train; không coi đó là dữ liệu mới.

## 2. Phân bố domain/source

| Tập | domain | source/provenance | số dòng |
|---|---|---|---:|
| `_kaggle_upload/train_gold_vnext.jsonl` | `review` | <thiếu>=8060 | 4953 |
| `_kaggle_upload/train_gold_vnext.jsonl` | `register_booster` |  | 2400 |
| `_kaggle_upload/train_gold_vnext.jsonl` | `register` |  | 660 |
| `_kaggle_upload/train_gold_vnext.jsonl` | `xianxia` |  | 32 |
| `_kaggle_upload/train_gold_vnext.jsonl` | `game` |  | 12 |
| `_kaggle_upload/train_gold_vnext.jsonl` | `sci-fi` |  | 3 |
| `_kaggle_upload/train_v2.jsonl` | `<thiếu>` | <thiếu>=87338 | 87338 |
| `approved_gold.jsonl` | `review` | <thiếu>=5000 | 4953 |
| `approved_gold.jsonl` | `xianxia` |  | 32 |
| `approved_gold.jsonl` | `game` |  | 12 |
| `approved_gold.jsonl` | `sci-fi` |  | 3 |
| `dataset/booster.jsonl` | `register_booster` | <thiếu>=1200 | 1200 |
| `dataset/error_cases.jsonl` | `<thiếu>` | <thiếu>=687 | 687 |
| `dataset/labeled_gold.jsonl` | `<thiếu>` | <thiếu>=687 | 687 |
| `dataset/labeled_gold_sample.jsonl` | `<thiếu>` | <thiếu>=40 | 40 |
| `dataset/raw_zh.jsonl` | `<thiếu>` | shuhaige=2320 | 2320 |
| `dataset/register_gold.jsonl` | `register` | <thiếu>=660 | 660 |
| `dataset/train_gold_vnext.jsonl` | `review` | <thiếu>=8060 | 4953 |
| `dataset/train_gold_vnext.jsonl` | `register_booster` |  | 2400 |
| `dataset/train_gold_vnext.jsonl` | `register` |  | 660 |
| `dataset/train_gold_vnext.jsonl` | `xianxia` |  | 32 |
| `dataset/train_gold_vnext.jsonl` | `game` |  | 12 |
| `dataset/train_gold_vnext.jsonl` | `sci-fi` |  | 3 |
| `dataset/train_v2.jsonl` | `<thiếu>` | <thiếu>=87338 | 87338 |
| `source_pool.jsonl` | `game` | dataset_game/raw_zh.jsonl=4300, worker\benchmark_out\hachimimt-60-zh-vi\n293_c1_output.txt=69, worker\benchmark_out\hachimimt-60-zh-vi\n282_c2_output.txt=61, worker\benchmark_out\hachimimt-60-zh-vi\n356_c2_output.txt=58 | 800 |
| `source_pool.jsonl` | `xianxia` |  | 800 |
| `source_pool.jsonl` | `survival` |  | 700 |
| `source_pool.jsonl` | `benchmark` |  | 500 |
| `source_pool.jsonl` | `fandom` |  | 500 |
| `source_pool.jsonl` | `fantasy_scifi` |  | 500 |
| `source_pool.jsonl` | `modern_other` |  | 500 |
| `source_pool.jsonl` | `sports_esports` |  | 500 |

## 3. Provenance và cách train thực tế

- `dataset/train_gold_vnext.jsonl` có các trường `id`, `domain`, `status`, `zh`, `vi`; các dòng được trộn từ gold cũ, register và booster. Cần đối chiếu theo cặp ZH/VI, không chỉ theo `status`.
- So sánh theo cặp với các file thành phần:
  - `approved_gold.jsonl`: 5000 cặp duy nhất; 5000 lượt xuất hiện trong manifest (trước hệ số lặp).
  - `dataset/register_gold.jsonl`: 660 cặp duy nhất; 660 lượt xuất hiện trong manifest (trước hệ số lặp).
  - `dataset/labeled_gold.jsonl`: 687 cặp duy nhất; 660 lượt xuất hiện trong manifest (trước hệ số lặp).
  - `dataset/booster.jsonl`: 1200 cặp duy nhất; 2400 lượt xuất hiện trong manifest (trước hệ số lặp).
- Script train dùng base model `ngocdang83/HachimiMT-60-zh-vi`; không thấy cơ chế resume checkpoint.
- Mặc định `gold_repeat=5`; `load_extra_replay` xáo trộn seed 42, lọc register rồi lấy tối đa 20.000 dòng từ `train_v2.jsonl`; replay chính lấy từ dataset Hugging Face `DATASET_ID`, không nằm đầy đủ trong thư mục này.
- `train_gold_vnext` không nên truyền nguyên trạng nếu chưa tách provenance và duyệt lại: booster tự sinh, register_gold được suy ra từ labeled/error cases, còn approved là nhãn nhập file.

## 4. Vấn đề dữ liệu và mẫu cụ thể

- Cặp ZH trùng nhưng VI khác trong manifest: **1**.
- Cặp gần trùng (SequenceMatcher, ZH >= 0,92; mẫu giới hạn): **12**.
  - `train_gold_vnext.jsonl:3009`: 王长生非常肯定，自己现在的实力，绝对已经超过了当初的父亲和二叔，甚至只需要一招，就能够胜了父亲和二叔联手，为何父亲和二叔能够打开，而自己不能？ | Vương Trường Sinh vô cùng khẳng định, thực lực hiện tại của mình tuyệt đối đã vượt qua phụ thân và nhị thúc lúc trước, thậm chí chỉ cần một chiêu là có thể thắng được sự liên thủ c | cùng ZH có VI khác
  - `train_gold_vnext.jsonl:40`: 被叫做小二的人慢慢抬起头，轻声说道：老爷，这个问题太深奥了，小二不是太明白，不过...小二知道，对于普通人而言，能够活到百岁，就算是长生了吧！ | gần dòng 4825, ZH giống 0.99; VI đối chiếu: Người được gọi là tiểu nhị chậm rãi ngẩng đầu, khẽ nói: "Lão gia, vấn đề này quá
  - `train_gold_vnext.jsonl:64`: 少女轻咬着银牙，小脸气鼓鼓的，神色不善的盯着林轩，但似乎想到了什么，她眨了眨眼睛，轻声说道：林轩，我的宝剑出问题了，你帮我看看。 | gần dòng 409, ZH giống 0.98; VI đối chiếu: Thiếu nữ khẽ cắn răng, khuôn mặt nhỏ phồng lên, ánh mắt bất thiện nhìn chằm chằm
  - `train_gold_vnext.jsonl:53`: 刹那间，一幅幅画面在玩家的脑海中翻涌，一些陌生的数据和信息，迅速植入每个玩家的脑海中。 | gần dòng 268, ZH giống 0.98; VI đối chiếu: Trong chớp mắt, từng hình ảnh cuộn trào trong đầu người chơi; dữ liệu và thông t
  - `train_gold_vnext.jsonl:173`: 林晧然的脑袋炸响，浑身发软，抓着江荣华衣襟的手不由得松了几分，但很快就愤怒地瞪着他道："不可能，你在骗我！" | gần dòng 4843, ZH giống 0.96; VI đối chiếu: Đầu của Lâm Hạo Nhiên nổ vang, toàn thân mềm nhũn, bàn tay nắm lấy vạt áo Giang 
  - `train_gold_vnext.jsonl:174`: 画完方格，紫宝儿看了看他们找到的石子，还算是满意，但嘴上却说："先凑合着用，等有时间再去河边找那些光溜溜的。" | gần dòng 4844, ZH giống 0.96; VI đối chiếu: Vẽ xong phương cách, Tử Bảo Nhi nhìn đống đá họ tìm thấy, vẫn còn khá hài lòng, 

### số liệu không khớp cần duyệt: 77

- dataset/train_gold_vnext.jsonl:4: 罗森刚刚夜跑了10公里，他正在马路边上散步休息，右手还抓着一瓶柠檬味的脉动。 | La Sâm vừa chạy đêm mười cây số, đang tản bộ nghỉ ngơi bên đường, tay phải còn cầm một chai nước Mạch Động vị chanh. | số chữ số ZH/VI khác nhau
- dataset/train_gold_vnext.jsonl:82: 高材生也惊呼我想起来了：当年这个小丫头在台上因为积分制的原因一穿4外国顶尖西洋剑士。 | Ngay cả học sinh ưu tú cũng không khỏi kinh hô: "Ta nhớ ra rồi! Năm đó, trên sàn đấu, do thể thức tính điểm, nha đầu này đã một mình liên tiếp đánh bại bốn kiếm sĩ đấu kiếm phương  | số chữ số ZH/VI khác nhau
- dataset/train_gold_vnext.jsonl:87: 总共为320g灵尘，1枚2星普通随机招募精魄，4枚1星普通随机招募精魄以及一袋建筑资源袋。 | Tổng cộng nhận được: 320g Bụi Linh Hồn, 1 Tinh Phách Chiêu Mộ Ngẫu Nhiên Thường (2 sao), 4 Tinh Phách Chiêu Mộ Ngẫu Nhiên Thường (1 sao) và 1 Túi Tài Nguyên Xây Dựng. | số chữ số ZH/VI khác nhau
- dataset/train_gold_vnext.jsonl:144: 因此，对于最后100公里的路程，江漫雪并不担心，最多也就是拿不到宝箱。 | Bởi vậy, Giang Mạn Tuyết không hề lo lắng về một trăm ki-lô-mét cuối cùng; cùng lắm chỉ không lấy được rương báu mà thôi. | số chữ số ZH/VI khác nhau
- dataset/train_gold_vnext.jsonl:196: 平底占地面积大约有4万平方米，差不多6个足球场那么大，既方便防守又有足够的发展空间。 | Mặt bằng rộng khoảng bốn vạn mét vuông, xấp xỉ sáu sân bóng đá, vừa tiện phòng thủ lại vừa có đủ không gian phát triển. | số chữ số ZH/VI khác nhau

### xưng hô hiện đại cần duyệt: 496

- dataset/train_gold_vnext.jsonl:28: 罗森调出自己的属性面板，淡蓝色的光幕在眼前展开： | La Sâm gọi ra bảng thuộc tính của mình, màn sáng xanh nhạt mở ra trước mắt: | có đại từ hiện đại; chưa kết luận sai
- dataset/train_gold_vnext.jsonl:46: 收好丹药，林轩朝着自己的小屋走去，他要尽快达到炼体九阶，再次尝试冲击灵脉。 | Cất kỹ đan dược, Lâm Hiên đi về căn nhà nhỏ của mình. Hắn phải mau chóng đạt tới Luyện Thể cửu giai, rồi thử xung kích linh mạch lần nữa. | có đại từ hiện đại; chưa kết luận sai
- dataset/train_gold_vnext.jsonl:58: 世人若是知晓，王长生把自己修炼秘籍毁去，肯定痛心疾首。 | Người đời nếu biết Vương Trường Sinh phá hủy bí tịch tu luyện của mình, chắc chắn sẽ vô cùng đau lòng. | có đại từ hiện đại; chưa kết luận sai
- dataset/train_gold_vnext.jsonl:70: 罗森的大拇指甲掐了一下自己的手指，略微有些刺痛，他蹲下身摸了摸草地。 | La Sâm dùng móng ngón cái bấm vào ngón tay mình, cảm thấy hơi đau nhói. Hắn ngồi xổm xuống, sờ thử bãi cỏ. | có đại từ hiện đại; chưa kết luận sai
- dataset/train_gold_vnext.jsonl:82: 高材生也惊呼我想起来了：当年这个小丫头在台上因为积分制的原因一穿4外国顶尖西洋剑士。 | Ngay cả học sinh ưu tú cũng không khỏi kinh hô: "Ta nhớ ra rồi! Năm đó, trên sàn đấu, do thể thức tính điểm, nha đầu này đã một mình liên tiếp đánh bại bốn kiếm sĩ đấu kiếm phương  | có đại từ hiện đại; chưa kết luận sai

### tỷ lệ độ dài bất thường: 4

- dataset/train_gold_vnext.jsonl:82: 高材生也惊呼我想起来了：当年这个小丫头在台上因为积分制的原因一穿4外国顶尖西洋剑士。 | Ngay cả học sinh ưu tú cũng không khỏi kinh hô: "Ta nhớ ra rồi! Năm đó, trên sàn đấu, do thể thức tính điểm, nha đầu này đã một mình liên tiếp đánh bại bốn kiếm sĩ đấu kiếm phương  | tỷ lệ ký tự VI/ZH=5.05
- dataset/train_gold_vnext.jsonl:1161: 玉简在她掌心泛着微光，映得指节苍白如雪。 | Ngọc giản tỏa ra ánh sáng nhạt trong lòng bàn tay nàng, phản chiếu những đốt ngón tay trắng bệch như tuyết. | tỷ lệ ký tự VI/ZH=5.35
- dataset/train_gold_vnext.jsonl:1468: 此名源于十大帝族共居于此，各据一方天阙，如十轮昊日统御万界。 | Cái tên này bắt nguồn từ việc mười đại đế tộc cùng cư ngụ tại đây, mỗi bên chiếm cứ một phương Thiên Khuyết, như mười vầng Hạo Nhật thống ngự vạn giới. | tỷ lệ ký tự VI/ZH=5.03
- dataset/train_gold_vnext.jsonl:3665: 灵光闪烁间，一张鎏金赌桌凭空出现在演武场外。 | Trong khoảnh khắc linh quang lóe lên, một chiếc bàn đánh bạc mạ vàng đột ngột xuất hiện bên ngoài diễn võ trường. | tỷ lệ ký tự VI/ZH=5.14

### artefact ký tự/dấu câu: 60

- dataset/train_gold_vnext.jsonl:201: 耳尖的欧阳听到身后的声音，一回头就看到林枫，顿时惊喜："哎枫子你来了啊！靠早和你说了是七点钟你还迟到，差点就见不着我的打野carry表现了好吗！" | Thính tai nghe thấy tiếng động phía sau, Âu Dương vừa quay đầu đã thấy Lâm Phong, liền mừng rỡ: "Đù, Phong Tử ngươi đến rồi à! Đã bảo với ngươi từ sớm là bảy giờ mà vẫn đến muộn, s | nghi mojibake hoặc marker
- dataset/train_gold_vnext.jsonl:249: “哪来那么多为什么，这是班级荣誉问题！”欧阳不由分说直接拍板；“下节课课间就去，就这么定了！” | “Làm gì lắm vì sao thế, đây là vấn đề vinh dự của lớp!” Âu Dương không cho ai phản đối, trực tiếp quyết định: “Giờ ra chơi tiết sau đi luôn, quyết thế đi!” | nghi mojibake hoặc marker
- dataset/train_gold_vnext.jsonl:808: 这莫名的声音又在每个人的脑海中最后响起... | Âm thanh kỳ lạ này lại vang lên cuối cùng trong đầu mỗi người... | nghi mojibake hoặc marker
- dataset/train_gold_vnext.jsonl:1046: 这一刻，她就像是一个魔力的绝缘体，哪怕在维克托的眼中，黎恩学院内部的元素浓度已经高到近乎能够化为实质，莉莉娅依然无法凝聚出一簇火苗。 | Giờ khắc này, nàng giống như một tuyệt duyên thể của ma lực, cho dù ở trong mắt Duy Khắc Thác, nồng độ nguyên tố bên trong học viện Lê Ân đã cao đến mức gần như có thể hóa thành th | nghi mojibake hoặc marker
- dataset/train_gold_vnext.jsonl:1138: 篮球破空而来的声响惊飞了草丛里的蟋蟀。于澜本能地跨步前冲，鞋底碾碎露珠的声响混着心跳。 | Âm thanh bóng rổ xé gió lao tới làm kinh động đến những con dế trong bụi cỏ. Vu Lan theo bản năng bước tới, tiếng đế giày nghiền nát sương mai hòa lẫn nhịp tim. | nghi mojibake hoặc marker

### dấu thoại không cân: 51

- dataset/train_gold_vnext.jsonl:307: 夜歌：“......那也不能到外面说，这只能是我们俩的小秘密，否则......否则我会被笑话的。 | Dạ Ca: "...Vậy cũng không thể ra ngoài nói, đây chỉ là bí mật nhỏ của hai chúng ta, nếu không... nếu không ta sẽ bị chê cười mất. | số dấu quote tiếng Việt lẻ
- dataset/train_gold_vnext.jsonl:535: “关叔，我刚才利用得到的卷纸图纸生产了许多卷纸售卖，几倍利润，赚翻了。 | "Quan thúc, bản vẽ cuộn vừa rồi con đã dùng được để sản xuất rất nhiều cuộn giấy để bán, lợi nhuận gấp mấy lần, kiếm được bộn tiền. | số dấu quote tiếng Việt lẻ
- dataset/train_gold_vnext.jsonl:615: 这十二经脉啊，一旦走到尽头，那就是各有各的惨法儿，咱们还是得好好保养，别让它们提前‘退休’了！” | Mười hai kinh mạch này, một khi đi đến hồi kết, đó chính là mỗi bên đều có những phương pháp thảm hại riêng, chúng ta vẫn nên chăm sóc tốt, đừng để chúng 'nghỉ hưu' sớm!" | số dấu quote tiếng Việt lẻ
- dataset/train_gold_vnext.jsonl:1076: 警告：播种要遵循自然规律，因为自己操作不当造成的损失系统概不负责。」 | Cảnh báo: gieo hạt phải tuân theo quy luật tự nhiên, bởi vì hệ thống tổn thất do thao tác không thỏa đáng của bản thân hoàn toàn không chịu trách nhiệm." | số dấu quote tiếng Việt lẻ
- dataset/train_gold_vnext.jsonl:1511: “夏天胃气带点微钩，健康标志；钩太多胃气少，心脏要遭殃；只有钩没胃气，也是凶多吉少。胃气里还带点‘石’（沉），那就是冬天可能有病；‘石’得很，就是现在病得不轻。心脏负责血脉，得悠着点。 | "Giữa mùa hè có chút móc nhẹ, dấu hiệu sức khỏe; móc quá nhiều hơi dạ dày ít, tim sẽ gặp họa; chỉ có móc không có hơi dạ dày, cũng là lành ít dữ nhiều. Vị khí còn mang chút 'thạch' | số dấu quote tiếng Việt lẻ

### tên/chữ Latin dính: 16

- dataset/train_gold_vnext.jsonl:437: 咦！这回对面其中两个人有ID，一个叫zhoKing,一个叫Uki。 | Ồ! Lần này hai người phe đối diện có ID: một tên zhoKing, một tên Uki. | nghi dính từ Latin
- dataset/train_gold_vnext.jsonl:487: “请IG.Rookie选手和IG.K'aiVen选手两分钟后，前往后台接受赛后采访。采访之后还需要进行咱们LPL赛区的出征仪式，请所有的参赛选手和主教练做好准备哈。” | “Mời tuyển thủ IG.Rookie và IG.K'aiVen tới hậu trường nhận phỏng vấn sau trận trong hai phút nữa. Sau phỏng vấn còn có lễ xuất chinh của khu vực LPL, mời toàn bộ tuyển thủ và huấn  | nghi dính từ Latin
- dataset/train_gold_vnext.jsonl:838: 对面在zhoKing和Uki的带领下，很显然没有重视对手，选择直接全部干拉rushB区。 | Đối phương dưới sự dẫn dắt của zhoKing và Uki, hiển nhiên không coi trọng đối thủ, lựa chọn trực tiếp đánh chiếm toàn bộ khu RushB. | nghi dính từ Latin
- dataset/train_gold_vnext.jsonl:1489: IG.K'aiVen皮城女警——凯特琳击杀WE.Xiye虚空行者——卡萨丁 | IG.K'aiVen Nữ Cảnh Piltover — Caitlyn hạ gục WE.Xiye Kẻ Bước Hư Không — Kassadin | nghi dính từ Latin
- dataset/train_gold_vnext.jsonl:1737: 麦迪在确定刚才没有听错后，难以置信的说道。 | Sau khi xác định vừa rồi không nghe nhầm, McGrady khó tin nói. | nghi dính từ Latin

### author note/meta: 27

- dataset/train_gold_vnext.jsonl:1108: 作者目前完成过两本书，一本95万字，一本118万字。 | Tác giả hiện tại đã hoàn thành hai cuốn sách, một cuốn 95 vạn chữ, một cuốn 118 vạn chữ. | ZH có từ khóa lời tác giả/meta
- dataset/train_gold_vnext.jsonl:1382: 要说《末世盛宠：顾总的丧尸小娇妻》最让读者生气的，莫过于作者拿原主和宋之乔做对照组，明明原主处处比宋之乔优秀，但作者回回都只虐不反杀，甄苏苏看了三十多章，全是宋之乔单方面碾压原主。 | Phải nói ⟨Mạt Thế Thịnh Sủng: Tiểu kiều thê Zombie của Cố tổng ⟩ khiến độc giả tức giận nhất, không gì hơn tác giả lấy nguyên chủ và Tống Chi Kiều làm nhóm đối chiếu, rõ ràng nguyê | ZH có từ khóa lời tác giả/meta
- dataset/train_gold_vnext.jsonl:1654: “谢谢你，邪心先生。”宅博士真诚地感谢道。 | "Cảm ơn ngài, Tà Tâm tiên sinh." Tiến sĩ Trạch chân thành cảm ơn. | ZH có từ khóa lời tác giả/meta
- dataset/train_gold_vnext.jsonl:1779: 000998：感谢大哥，总算活了过来，暖洋洋的好舒服。 | 000998: Cảm ơn đại ca, cuối cùng cũng sống lại, ấm áp vô cùng thoải mái. | ZH có từ khóa lời tác giả/meta
- dataset/train_gold_vnext.jsonl:2107: 林轩掏出一个白瓷小瓶，将朱红色丹药放到小瓶中，然后小心的收了起来。这是疗伤的丹药，效果奇好，他每次都把丹药收藏起来，留着需要的时候在用。 | Lâm Hiên lấy ra một cái bình sứ trắng nhỏ, đặt đan dược màu đỏ chu sa vào trong bình nhỏ, sau đó cẩn thận cất đi. Đây là đan dược trị thương, hiệu quả rất tốt, mỗi lần hắn đều cất  | ZH có từ khóa lời tác giả/meta

## 5. Phân loại hành động

- **Giữ ứng viên:** chỉ các cặp có ZH/VI đầy đủ, không trùng cặp, provenance truy được và người duyệt xác nhận bản dịch; không suy ra từ `approved`.
- **Cách ly trước train:** mọi dòng có artefact ký tự/dấu câu, thiếu trường, xung đột cùng ZH khác VI, author note/meta, hoặc duplicate do trộn manifest.
- **Cần người duyệt:** các cờ xưng hô, tên Latin dính, tỷ lệ độ dài, chữ số và câu thiếu/thừa ngữ cảnh. Đây là danh sách kiểm tra, không phải phán quyết bản dịch sai.
- **Bộ ứng viên đề xuất:** manifest dedup theo cặp ZH/VI; giữ riêng `approved_gold` đã xác minh provenance, `register_gold` sau khi người duyệt xác nhận từng dòng, và `booster` như bộ thí nghiệm riêng. Không tạo bản dịch mới trong kiểm toán này.

## 6. Giới hạn

Near-duplicate là heuristic stdlib trên manifest, không thay cho đọc ngữ cảnh. Regex xưng hô không phân biệt tuyệt đối lời thoại, ngôi kể hay chủ thể; các mẫu đã nêu phải được đọc lại trước quyết định.
