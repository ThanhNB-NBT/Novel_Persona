# Audit `moa/Chinese-Vietnamese-literature`

> Đây là replay candidate, không phải gold người duyệt và chưa được nhập vào train.

## Tổng quan

- Dòng gốc: **396,307**.
- Cặp duy nhất: **395,095**; dòng trùng hoàn toàn dư: **1,212**.
- Nguồn Trung xung đột nhiều bản Việt: **5,365**.
- Qua gate tự động: **244,105**.
- Lấy mẫu hash ổn định làm candidate: **50,000**.

## Loại bởi gate

| Lý do | Số dòng |
|---|---:|
| `modern_register` | 110,735 |
| `unbalanced_quotes` | 13,831 |
| `source_length` | 8,408 |
| `same_zh_conflict` | 5,365 |
| `digit_mismatch` | 4,431 |
| `length_ratio` | 1,768 |
| `target_han_leak` | 924 |
| `source_without_han` | 23 |
| `replacement_or_null` | 2 |

## Mẫu bị loại

### `digit_mismatch`
- 第三十回 宝钗借扇机带双敲 龄官划蔷痴及局外 → Hồi 30: Bảo Thoa mượn quạt châm chọc hai người, Lăng Quan vạch tường si dại ngoài cuộc.
- 第三十一回 撕扇子作千金一笑 因麒麟伏白首双星 → Hồi 31 - Xé quạt mua một nụ cười nghìn vàng; Vì kỳ lân ẩn hiện, duyên đôi lứa bạc đầu.
- 第三十二回 诉肺腑心迷活宝玉 含耻辱情烈死金钏 → Hồi 32: Bày tỏ nỗi lòng, Bảo Ngọc mê mẩn vật báu sống; Ôm nỗi nhục, Kim Xuyến khí tiết hy sinh.

### `modern_register`
- 话说林黛玉与宝玉角口后，也自后悔，但又无去就他之理，因此日夜闷闷，如有所失。 → Đại Ngọc từ hôm cãi nhau với Bảo Ngọc, trong bụng hối hận, nhưng không lẽ tự mình đến làm lành trước, vì thế ngày đêm bu
- 别人不知宝玉那脾气，难道咱们也不知道的。 → Người khác không biết rõ tính nết cậu Bảo, chứ chúng ta lẽ nào lại cũng không biết hay sao?
- 我怎么浮躁了？”紫鹃笑道：“好好的，为什么又剪了那穗子？岂不是宝玉只有三分不是，姑娘倒有七分不是。 → Thế nào là ta nóng nảy? Tự nhiên vô cớ, sao cô lại cắt cái dây đeo ngọc đi? Thế chả phải lỗi cậu Bảo chỉ có ba phần, mà 

### `unbalanced_quotes`
- 紫鹃度其意，乃劝道：“若论前日之事，竟是姑娘太浮躁了些。 → Tử Quyên đoán biết tâm lý ấy, liền khuyên nhủ: Việc hôm nọ là tự cô nóng nảy quá.
- 我看他素日在姑娘身上就好，皆因姑娘小性儿，常要歪派他，才这么样！”林黛玉正欲答话，只听院外叫门。 → Tôi xem ngày thường cậu ấy đối với cô rất tốt, chỉ vì cô khó tính thường vặn vẹo cậu ấy, nên đến nỗi vậy.
- 紫鹃听了一听，笑道：“这是宝玉的声音，想必是来赔不是来了！”林黛玉听了道：“不许开门！”紫鹃道：“姑娘又不是了。 → Đại Ngọc muốn nói lại, chợt ngoài sân có tiếng gọi cửa. Tử Quyên lắng tai nghe, cười nói: Thôi tiếng cậu Bảo rồi, chắc l

### `source_length`
- 幸而屋里没人。 → Khi đó trong nhà không có ai.
- 宝玉笑道。 → Bảo Ngọc cười nói:
- 宝玉想道。 → Bảo Ngọc nghĩ:

### `same_zh_conflict`
- 要知端的，且听下回分解。 → Tập Nhân thấy thế, lạnh đi một nửa người.
- 不在话下。 → Chuyện đó không nói nữa.
- 什么。 → “Thế nào lại,”

### `length_ratio`
- 贾政犹嫌打轻了，一脚踢开掌板的，自己夺过来，咬着牙狠命盖了三四十下。 → Bảo Ngọc biết rằng mình có van cũng chẳng tha nào, đành khóc rống lên. Giả Chính cho là đánh khẽ quá, đá thằng cầm gậy, 
- 看看宝玉，果然打重了。再看看王夫人，儿这会子你倘或有个好歹，丢下我，叫我靠那一个！“数落一场，又哭”不争气的儿“。 → Thấy Bảo Ngọc bị đánh đau quá. Vương phu nhân cứ kêu con luôn miệng và nói: “Nếu mày chết đi cho anh Châu mày sống, thì 
- 宝玉叹气说道： 听说，便轻轻的伸手进去，将中衣褪下。 → Bảo Ngọc thở dài: Hỏi làm gì nữa? Chẳng qua cũng vì những việc ấy thôi! Nửa mình tôi đau lắm, chị thử xem đánh vào những

### `source_without_han`
- —————————– (1). Nước móc pha với quế. (2). Nước móc pha với nước hoa mai khôi có mùi thơm. → (1). Nước móc pha với quế. (2). Nước móc pha với nước hoa mai khôi có mùi thơm.
- ————————- (1). Ngày mồng 9 tháng Chín. (2). Tức Đào Tiềm, người đời Tấn. Vì ông làm quan l → ————————- (1). Ngày mồng 9 tháng Chín. (2). Tức Đào Tiềm, người đời Tấn. Vì ông làm quan lệnh ở Bành Trạch, nên cũng gọi
- (1). Tức Thích Huyền Trang, người đời Đường, sang Ấn Độ lấy kinh. Vua không cho đi, ông ta → (1). Tức Thích Huyền Trang, người đời Đường, sang Ấn Độ lấy kinh. Vua không cho đi, ông ta trốn ra cửa Ngọc Quan, rồi đế

### `target_han_leak`
- 管窥蠡测' 。 → (Đoạn này tiếng Việt ghi cụm từ tiếng Trung là "管窥蠡测" và dịch "Lấy ống nhòm trời, lấy bầu đong biển")
- 李纨道：“我们要看诗了，若看完了还不交卷是必罚的！”宝玉道：“稻香老农虽不善作却善看，又最公道，你就评阅优劣，我们都服的！” → Lý Hoàn nói: "Chúng ta muốn xem thơ rồi, nếu xem xong mà chưa nộp bài thì nhất định phải phạt!" Bảo Ngọc nói: "Đạo Hương
- 湘云依说将题录出，又看了一回，又问诗，何苦为韵所缚。咱们别学那小家派，只出题不拘韵。原为大家偶得了好句取乐，并不为此而难人。 → Tương Vân theo lời chép đề ra, lại xem một hồi, lại hỏi thơ, hà cớ gì phải bị vần trói buộc. Chúng ta đừng học theo phái

### `replacement_or_null`
- 这一次，顾逍没有及时回答，他把蒜蓉炒青菜盛出锅后才扭头看了张思�一眼，勾嘴笑问：“这么好奇打听，你是想给我当妹夫？” → Lần này Cố Tiêu không trả lời ngay, anh múc món rau xào tỏi ra đĩa rồi mới quay đầu nhìn Trương Tư Nghị, nhếch môi cười 
- 不料后座的顾逍却接着她的话题调侃了张思�一句：“我看练练车也有必要，以后不止回宁城，我还有可能带你去别的地方，总不能每次都让我一个人开，既然你有驾照，回头我带你练一下吧。” → Không ngờ Cố Tiêu ngồi sau lại tiếp lời cô để trêu chọc Trương Tư Nghị: "Anh thấy luyện xe cũng cần thiết đấy, sau này k

## Quyết định

- Không gọi tập này là gold: không có metadata người dịch/tác phẩm ở cấp dòng.
- Chỉ cân nhắc làm replay văn học sau khi đọc tay một mẫu cân bằng và kiểm tra điều khoản
  ShareAlike đối với model phát hành.
- Không dùng các dòng bị loại để sửa bằng heuristic rồi đưa trở lại.
