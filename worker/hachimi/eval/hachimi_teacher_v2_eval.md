# Hachimi teacher-v2 — so sánh trên eval đã khóa

> `similarity` chỉ là chỉ báo ký tự để hỗ trợ đọc tay, không thay cho đánh giá nghĩa.
> Tập 60 cảnh chạy qua pipeline production (termguard + glossary approved); tập game
> là raw model, không glossary.

## 60 cảnh tham chiếu (60 câu)

| Model | Similarity TB | Hán sót | Đại từ hiện đại | Đệm thừa | Quote lỗi | Số lỗi |
|---|---:|---:|---:|---:|---:|---:|
| `base` | 0.7050 | 0 | 15 | 3 | 7 | 0 |
| `current` | 0.7107 | 0 | 15 | 2 | 6 | 0 |
| `teacher_v2` | 0.7213 | 0 | 25 | 3 | 1 | 0 |

## Game tiếng Anh đã khóa (36 câu)

| Model | Similarity TB | Hán sót | Đại từ hiện đại | Đệm thừa | Quote lỗi | Số lỗi |
|---|---:|---:|---:|---:|---:|---:|
| `base` | 0.6548 | 0 | 3 | 5 | 1 | 1 |
| `current` | 0.6604 | 0 | 2 | 2 | 1 | 1 |
| `teacher_v2` | 0.6697 | 0 | 1 | 5 | 0 | 1 |

## 1. [reference_60] semantic_context

- ZH: 这么一看才发现，原来体力值那一栏在不知道什么时候居然消耗了差不多三分之一了，在过了几秒之后，席然发现体力值再度减少，差不多是20秒左右减少一点。席然可记得就算在伐木的时候，体力值消耗也差不多等于没有，可是现在居然下降的这么快，想来应该是跟所做的事情有着关联，他现在保持这个状态确实是非常消耗体力的。“如果体力值成了0，那会是什么情况呢？很有可能，就是不能动弹，或者死去吧。”席然已经猜的仈jiu不离十了，在还有体力值的情况下，不论受到什么样的攻击都会扣掉相应的体力值，当然如果攻击力度过高，也有可能出现秒杀。体力值完全耗尽，那么一切的数据化都会消失，数据化时候所受到的伤害都会反馈到身体上，目前来说整个轮回空间还没有一人能够承受得住这样的反馈，毫无疑问体力值耗尽等于宣告死刑。不过，还有一种体力值耗尽的情况则是没有那么严重，那就是自身使用技能招式所导致的，但可以肯定这也不是好受的。
- Tham chiếu: Nhìn kỹ, Tịch Nhiên mới phát hiện thanh thể lực chẳng biết từ lúc nào đã hao gần một phần ba. Vài giây sau, hắn thấy nó lại giảm, đại khái cứ hai mươi giây mất một điểm. Hắn nhớ ngay cả lúc đốn gỗ, thể lực cũng gần như không hao, vậy mà giờ lại tụt nhanh đến thế. Có lẽ điều này liên quan đến việc hắn đang làm; duy trì trạng thái hiện tại quả thật tiêu tốn rất nhiều thể lực. “Nếu thể lực về không thì sẽ thế nào? Rất có thể sẽ không thể cử động, hoặc chết.” Phán đoán của Tịch Nhiên đã khá sát sự thật. Khi vẫn còn thể lực, bất kể chịu đòn tấn công nào, người ta cũng chỉ bị trừ lượng thể lực tương ứng; đương nhiên, nếu lực công kích quá lớn thì vẫn có thể bị giết trong một đòn. Một khi thể lực cạn sạch, trạng thái dữ liệu hóa sẽ biến mất, mọi thương tổn phải chịu khi dữ liệu hóa đều phản hồi lên thân thể. Hiện tại, trong toàn bộ không gian Luân Hồi chưa một ai chịu nổi sự phản hồi ấy. Không còn nghi ngờ gì, cạn thể lực đồng nghĩa với án tử. Tuy nhiên vẫn có một trường hợp ít nghiêm trọng hơn: thể lực hao hết vì tự sử dụng kỹ năng hoặc chiêu thức. Dẫu vậy, cảm giác ấy chắc chắn cũng chẳng dễ chịu.
- base: Nhìn như vậy mới phát hiện, hóa ra cột thể lực kia không biết từ lúc nào đã tiêu hao gần một phần ba, sau vài giây, Tịch Nhiên phát hiện thể lực lại giảm xuống, khoảng 20 giây giảm đi một chút. Tịch Nhiên nhớ rõ dù ở lúc đốn gỗ, tiêu hao thể lực cũng gần như không có, nhưng bây giờ lại giảm nhanh như vậy, chắc hẳn là có liên quan đến những việc đã làm, hiện tại hắn duy trì trạng thái này quả thực rất tiêu hao thể lực. "Nếu thể lực thành 0, thì sẽ là tình huống gì đây? Rất có khả năng, chính là không thể cử động, hoặc là chết đi." Tịch Nhiên đã đoán không rời mười, trong tình huống còn có thể lực, bất kể bị tấn công gì cũng sẽ bị trừ đi thể lực tương ứng, đương nhiên nếu lực công kích quá cao, cũng có khả năng xuất hiện giây sát. Thể lực đã cạn kiệt hoàn toàn, mọi dữ liệu hóa đều sẽ tiêu tán. Những tổn thương khi dữ liệu hóa sẽ được phản hồi lên cơ thể. Hiện tại toàn bộ không gian luân hồi chưa từng có ai chịu nổi phản hồi như vậy. Không nghi ngờ gì, thể lực cạn kiệt đồng nghĩa với tuyên bố tử hình. Tuy nhiên, tình trạng thể lực cạn kiệt không nghiêm trọng như vậy, đó là do bản thân sử dụng kỹ năng chiêu thức gây ra, nhưng có thể khẳng định đây cũng không phải là chuyện dễ chịu. `sim=0.6052; han=0; modern=0; quote=True; digits=True`
- current: Nhìn như vậy mới phát hiện, hóa ra cột thể lực không biết từ lúc nào đã tiêu hao gần một phần ba, sau vài giây, Tịch Nhiên phát hiện thể lực lại giảm xuống, khoảng 20 giây giảm một chút. Tịch Nhiên nhớ rõ dù ở lúc đốn gỗ, tiêu hao thể lực cũng tương đương không có, nhưng bây giờ lại giảm nhanh như vậy, hẳn là có liên quan đến những việc đã làm, hiện tại hắn duy trì trạng thái này quả thực rất tiêu hao thể lực. "Nếu thể lực thành 0, vậy tình huống sẽ ra sao? Rất có khả năng, chỉ là không thể cử động, hoặc là chết đi." Tịch Nhiên đã đoán không rời mười, trong tình huống còn có thể lực, bất kể bị tấn công gì cũng sẽ trừ đi thể lực tương ứng, đương nhiên nếu lực công kích vượt qua, cũng có khả năng xuất hiện giây sát. Thể lực hoàn toàn cạn kiệt, mọi dữ liệu hóa sẽ biến mất, sát thương phải chịu khi dữ liệu hóa sẽ được phản hồi về cơ thể. Hiện tại toàn bộ không gian luân hồi chưa một ai chịu nổi phản hồi như vậy, không nghi ngờ gì là thể lực cạn kiệt đồng nghĩa với tuyên bố tử hình. Tuy nhiên, vẫn còn tình trạng thể lực cạn kiệt thì không nghiêm trọng đến thế, đó là do bản thân sử dụng kỹ năng chiêu thức gây ra, nhưng có thể khẳng định đây cũng không phải chuyện dễ chịu. `sim=0.6270; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Nhìn như vậy mới phát hiện, thì ra cột thể lực không biết từ lúc nào đã tiêu hao gần một phần ba, sau vài giây, Tịch Nhiên phát hiện điểm thể lực lại giảm đi, khoảng 20 giây giảm đi một chút. Tịch Nhiên nhớ rằng ngay cả khi đốn gỗ, tiêu hao thể lực cũng gần như không có, nhưng bây giờ lại giảm nhanh như vậy, chắc hẳn có liên quan đến những việc đã làm. Việc duy trì trạng thái này của hắn hiện tại quả thực rất tiêu hao thể lực. “Nếu thể lực thành 0, thì tình hình sẽ ra sao? Rất có thể, chỉ là không thể cử động, hoặc là chết đi thôi.” Tịch Nhiên đã đoán không rời mười phần, trong tình huống còn có thể lực, bất kể bị tấn công gì cũng sẽ trừ đi thể lực tương ứng, đương nhiên nếu lực công kích quá cao, cũng có thể xuất hiện giây sát. Thể lực đã cạn kiệt hoàn toàn, mọi dữ liệu hóa đều sẽ biến mất. Những tổn thương phải chịu khi dữ liệu hóa sẽ được phản hồi lên cơ thể. Hiện tại trong toàn bộ không gian luân hồi chưa từng có ai chịu nổi phản hồi như vậy. Không nghi ngờ gì, thể lực cạn kiệt không khác nào tuyên bố tử hình. Tuy nhiên, vẫn còn một trường hợp thể lực cạn kiệt thì không nghiêm trọng đến thế, đó là do bản thân sử dụng kỹ năng chiêu thức gây ra, nhưng có thể khẳng định đây cũng không phải là chuyện dễ chịu. `sim=0.6516; han=0; modern=0; quote=True; digits=True`

## 2. [reference_60] semantic_context

- ZH: “你啊，干嘛为你那个没出息的儿子这样，他自己没本事考上魔法高中，就让他自生自灭好了，也快16岁了。而且啊，就算我这次帮你，把他弄上魔法高中，以他的尿性，肯定还是不务正业，成不了真正的魔法师，想当魔法师不是那么容易，不仅要靠自身天赋，后天努力，除此之外，那些魔法书、魔器、魔具你们家买得起吗，没有这些辅佐，他连一个初阶魔法师都成为不了……”那个叫做穆贺的男子用一种语重心长的口吻说道，但是莫凡听到的尽是一股子趾高气昂。
- Tham chiếu: “Ngươi cần gì phải làm đến mức này vì đứa con chẳng có tiền đồ ấy? Nó không đủ bản lĩnh thi vào trường trung học ma pháp thì cứ để nó tự sinh tự diệt, dù sao cũng sắp mười sáu tuổi rồi. Hơn nữa, cho dù lần này ta giúp ngươi đưa nó vào trường, với cái tính ấy, nó chắc chắn vẫn không lo chính sự, chẳng thể trở thành ma pháp sư chân chính. Muốn làm ma pháp sư đâu có dễ; không chỉ cần thiên phú và nỗ lực rèn luyện, mà còn phải có ma pháp thư, ma khí, ma cụ. Nhà ngươi mua nổi những thứ đó sao? Không có chúng hỗ trợ, nó đến ma pháp sư sơ giai cũng chẳng thành được...” Nam tử tên Mục Hạ nói bằng giọng ra chiều tận tình khuyên bảo, nhưng Mạc Phàm chỉ nghe thấy sự kiêu căng hống hách trong từng lời.
- base: “Ngươi đó, Tại sao lại làm như vậy với đứa con không có tiền đồ của ngươi Bản thân hắn không có bản lĩnh thi đỗ vào trường trung học ma pháp, Cứ để hắn tự sinh tự diệt là được, Cũng sắp 16 tuổi rồi. Hơn nữa, Coi như lần này ta giúp ngươi, Đưa hắn lên trường trung học ma pháp, Với cái tính cách của hắn, Chắc chắn vẫn là không lo việc chính sự, Không thể trở thành ma pháp sư chân chính, Muốn làm ma pháp sư không phải dễ dàng như vậy, Không chỉ phải dựa vào thiên phú của bản thân, Ngày kia cố gắng, Ngoài ra, Những cuốn ma pháp thư đó, Ma khí Ma cụ nhà các ngươi mua nổi sao Không có những phụ tá này, Hắn ngay cả một ma pháp sư sơ giai cũng không trở thành được..." Người đàn ông tên Mục Hạ dùng giọng điệu chân thành nói, Nhưng Mạc Phàm nghe xong toàn là vẻ kiêu ngạo hống hách. `sim=0.6748; han=0; modern=0; quote=False; digits=True`
- current: "Ngươi đó, Tại sao lại làm như vậy với đứa con vô dụng của ngươi, Bản thân hắn không có bản lĩnh thi đỗ vào trường cấp ba ma pháp, Cứ để hắn tự sinh tự diệt đi, Cũng sắp 16 tuổi rồi. Hơn nữa, Cho dù lần này ta giúp ngươi, Đưa hắn lên trường cấp ba ma pháp, Với cái tính cách của hắn, Chắc chắn vẫn không lo việc chính, Không thể trở thành ma pháp sư chân chính, Muốn làm ma pháp sư không dễ dàng như vậy, Không chỉ phải dựa vào thiên phú của bản thân, Ngày kia nỗ lực, Ngoài ra, Những cuốn sách ma pháp đó, 【Ma khí】 【Ma cụ nhà các ngươi mua nổi không?】 Không có những phụ tá này, Hắn ngay cả một ma pháp sư sơ giai cũng không trở thành được..." Người đàn ông tên Mục Hạ dùng giọng điệu trọng tâm trường nói, Nhưng Mạc Phàm nghe xong toàn là vẻ mặt ngạo mạn. `sim=0.6508; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Ngươi đó, Tại sao lại làm như vậy với đứa con trai vô dụng của ngươi, Bản thân hắn không có bản lĩnh thi đỗ trường trung học ma pháp, Cứ để hắn tự sinh tự diệt là được, Cũng sắp 16 tuổi rồi. Hơn nữa, Cho dù lần này ta giúp ngươi, Đưa hắn lên trường trung học ma pháp, Với cái tính cách của hắn, Chắc chắn vẫn không làm việc đàng hoàng, Không thể trở thành ma pháp sư chân chính, Muốn làm ma pháp sư không dễ dàng như vậy, Không chỉ phải dựa vào thiên phú của bản thân, Ngày kia cố gắng, Ngoài ra, Những cuốn ma pháp thư đó, Ma khí, Ma cụ các ngươi mua nổi không? Không có những phụ tá này, Hắn ngay cả một ma pháp sư sơ giai cũng không trở thành...” Người đàn ông tên Mục Hạ dùng giọng điệu chân thành nói, Nhưng Mạc Phàm nghe xong chỉ biết vênh váo tự đắc. `sim=0.6355; han=0; modern=0; quote=True; digits=True`

## 3. [reference_60] semantic_context

- ZH: K也不留他，挥挥手说道：“那，你去外面的客厅等0052给你领装备吧，然后，他会带你去你的住所，为了你的安全，我给你安排在了一个富人区的豪华别墅内。黑暗势力很讲究社会公德，他们甚至不会去偷普通百姓的钱包，所以，只要你在人群包围中，你的安全就是有保障的……因为我听说过一条流传了数百年的禁令：凡是黑暗议会所属，严禁骚扰民间。嗯，据说他们的禁令，还是从中国解放军最古老的军事戒条三大纪律八项注意里改编过来的。”
- Tham chiếu: K cũng không giữ hắn lại, chỉ phất tay nói: “Vậy ngươi ra phòng khách bên ngoài, đợi 0052 dẫn đi nhận trang bị. Sau đó hắn sẽ đưa ngươi đến chỗ ở. Vì sự an toàn của ngươi, ta đã sắp xếp một căn biệt thự sang trọng trong khu nhà giàu. Thế lực hắc ám rất coi trọng đạo đức xã hội, thậm chí còn không trộm ví của dân thường. Vì vậy, chỉ cần ở giữa đám đông, sự an toàn của ngươi sẽ được bảo đảm... Ta từng nghe về một lệnh cấm đã lưu truyền hàng trăm năm: mọi kẻ thuộc Hắc Ám Nghị Hội đều nghiêm cấm quấy nhiễu dân chúng. Ừm, nghe nói lệnh cấm ấy được cải biên từ ‘Ba điều kỷ luật, Tám điều chú ý’, quân quy lâu đời nhất của Quân Giải phóng Nhân dân Trung Quốc.”
- base: K cũng không giữ hắn lại, Vung tay nói: “Vậy, Ngươi ra phòng khách bên ngoài đợi 0052 cho ngươi nhận trang bị đi, Sau đó, Hắn sẽ dẫn ngươi đến nơi ở của ngươi Vì sự an toàn của ngươi, Ta đã sắp xếp cho ngươi trong biệt thự sang trọng của một khu nhà giàu. Thế lực hắc ám rất coi trọng công đức xã hội, Bọn họ thậm chí sẽ không đi trộm ví của dân thường Cho nên, Chỉ cần ngươi ở trong đám người bao vây Sự an toàn của ngươi là được đảm bảo... bởi vì ta từng nghe nói một lệnh cấm lưu truyền hàng trăm năm: Phàm là thuộc về Hắc Ám Nghị Hội, Nghiêm cấm quấy nhiễu dân gian. Ừm, Nghe nói lệnh cấm của bọn họ Lại được cải biên từ ba điều luật quân sự cổ xưa nhất của quân giải phóng Trung Quốc được cải biên từ ba điều khoản quân sự cổ xưa nhất của quân giải phóng Trung Quốc." `sim=0.7482; han=0; modern=0; quote=False; digits=True`
- current: K cũng không giữ hắn lại, Vung tay nói: "Vậy, Ngươi ra phòng khách bên ngoài đợi 0052 cho ngươi nhận trang bị đi, Sau đó, Hắn sẽ đưa ngươi đến nơi ở của ngươi, Vì sự an toàn của ngươi, Ta sắp xếp cho ngươi trong biệt thự xa hoa của một khu nhà giàu. Thế lực hắc ám rất coi trọng công đức xã hội, Bọn họ thậm chí không đi trộm ví tiền của dân thường, Cho nên, Chỉ cần ngươi ở trong vòng vây của đám đông, Sự an toàn của ngươi chính là được đảm bảo... bởi vì ta từng nghe nói một lệnh cấm lưu truyền hàng trăm năm: Phàm là thuộc về Hội đồng Hắc Ám, Nghiêm cấm quấy nhiễu dân gian. Ừm, Nghe nói lệnh cấm của bọn họ, Lại được cải biên từ ba điều khoản quân sự cổ xưa nhất của quân Giải phóng Trung Quốc được cải biên từ ba điều khoản quân sự cổ xưa nhất." `sim=0.7263; han=0; modern=0; quote=True; digits=True`
- teacher_v2: K cũng không giữ hắn lại, Vung tay nói: “Vậy, Ngươi ra phòng khách bên ngoài đợi 0052 nhận trang bị cho ngươi đi, Sau đó, Hắn sẽ đưa ngươi đến nơi ở của ngươi, Vì sự an toàn của em, Ta đã sắp xếp cho ngươi trong một biệt thự sang trọng ở khu nhà giàu. Thế lực hắc ám rất coi trọng công đức xã hội, Bọn họ thậm chí sẽ không đi trộm ví của dân thường, Cho nên, Chỉ cần ngươi ở trong đám người bao vây, Sự an toàn của ngươi là được đảm bảo... bởi vì ta từng nghe nói một lệnh cấm lưu truyền hàng trăm năm: Phàm là người của Hội đồng Hắc Ám, Nghiêm cấm quấy nhiễu dân gian. Ừm, Nghe nói lệnh cấm của bọn họ Lại được cải biên từ ba điều luật quân sự cổ xưa nhất của quân Giải phóng Trung Quốc." `sim=0.7622; han=0; modern=0; quote=False; digits=True`

## 4. [reference_60] semantic_context

- ZH: “哈－－－－－！”猛喝一声，傲天从天而降狠狠的把枪叉入地里，地面由于受到这股巨大的力量的原因沿着插入的地方一道道的裂痕瞬间漫步向四周！但是也是由于受力过大的缘故，在傲天松手后那根插入土里的，被傲天当做枪练习的木枝终于承受不住“崩”的一声化为碎片，掉落到了地上！
- Tham chiếu: “Ha——!” Ngạo Thiên quát lớn, từ trên không giáng xuống, hung hăng cắm cây thương vào mặt đất. Dưới sức mạnh khổng lồ ấy, từng vết nứt lập tức lan từ điểm cắm ra bốn phía! Nhưng cũng vì phải chịu lực quá lớn, sau khi Ngạo Thiên buông tay, cành cây được hắn dùng thay thương luyện tập cuối cùng không thể chống đỡ thêm. Chỉ nghe “rắc” một tiếng, nó vỡ vụn rồi rơi xuống đất.
- base: "Ha ha!" Một tiếng quát lớn, Ngạo Thiên từ trên trời giáng xuống hung hăng cắm súng xuống đất, mặt đất do chịu lực lượng khổng lồ này, từng vết nứt lập tức tản bộ ra bốn phía! Nhưng cũng chính vì chịu lực quá lớn, cành gỗ cắm sâu xuống đất sau khi Ngạo Thiên buông tay, được Ngạo Thiên dùng làm thương luyện tập cuối cùng không chịu nổi một tiếng "băng" rồi hóa thành mảnh vụn, rơi xuống đất! `sim=0.6568; han=0; modern=0; quote=True; digits=True`
- current: "Ha!!!" Hắn hét lớn một tiếng, Ngạo Thiên từ trên trời giáng xuống hung hăng cắm súng xuống đất, mặt đất do chịu lực lượng khổng lồ này, từng vết nứt lập tức tản bộ ra bốn phía! Nhưng cũng chính vì chịu lực quá lớn, cành gỗ cắm sâu vào đất sau khi Ngạo Thiên buông tay, được Ngạo Thiên dùng làm súng luyện tập cuối cùng không chịu nổi một tiếng "băng" rồi hóa thành mảnh vụn, rơi xuống đất! `sim=0.6457; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Ha ha—!” Hắn quát lớn một tiếng, Ngạo Thiên từ trên trời giáng xuống, hung hăng cắm súng xuống đất, mặt đất do bị luồng sức mạnh khổng lồ này, từng vết nứt lập tức tản bộ ra bốn phía! Nhưng cũng là do chịu lực quá lớn, cành gỗ sau khi Ngạo Thiên buông tay, bị Ngạo Thiên dùng làm súng luyện tập, cuối cùng không chịu nổi một tiếng "băng" rồi hóa thành mảnh vụn, rơi xuống đất! `sim=0.6712; han=0; modern=0; quote=True; digits=True`

## 5. [reference_60] semantic_context

- ZH: “影响确实不小，没有了领地玩家身份就会从‘准·天选领主’跌落为‘天选者’，在统御兵种上也有了数量限制，无法拥有兵种建筑等等，在未来前途上远远不如……咳咳，说多了，领主玩家当然比非领主玩家更有优势，但这里有一个前提，我们要先保障生存啊。”
- Tham chiếu: “Ảnh hưởng quả thật không nhỏ. Mất lãnh địa, thân phận người chơi sẽ từ ‘Chuẩn · Thiên Tuyển Lĩnh Chủ’ tụt xuống thành ‘Thiên Tuyển Giả’. Số lượng binh chủng có thể thống lĩnh cũng bị hạn chế, không thể sở hữu kiến trúc binh chủng và nhiều thứ khác; tiền đồ sau này kém xa... Khụ khụ, ta nói hơi nhiều rồi. Đương nhiên người chơi lãnh chúa có ưu thế hơn người chơi thông thường, nhưng tất cả đều phải dựa trên một tiền đề: trước hết chúng ta phải sống sót đã.”
- base: “Ảnh hưởng xác thực không nhỏ, không có thân phận người chơi lãnh địa sẽ từ ‘chuẩn - Thiên Tuyển Lĩnh Chủ’ rơi xuống thành ‘Thiên Tuyển Giả’, ở trên thống ngự binh chủng cũng có hạn chế số lượng, không thể có được kiến trúc binh chủng v.v., trong tương lai tiền đồ kém xa... Khụ khụ, nói nhiều rồi, người chơi lãnh chúa đương nhiên có ưu thế hơn không phải người chơi lãnh chúa, nhưng ở đây có một tiền đề, chúng ta phải bảo đảm sinh tồn trước đã.” `sim=0.6796; han=0; modern=0; quote=True; digits=True`
- current: “Ảnh hưởng quả thật không nhỏ, không có thân phận người chơi lãnh địa sẽ từ ‘Chuẩn·Thiên Tuyển Lĩnh Chủ’ rớt xuống thành ‘Thiên Tuyển Giả’, trên thống ngự binh chủng cũng có hạn chế số lượng, không thể có được kiến trúc binh chủng vân vân, tiền đồ tương lai kém xa...... Khụ khụ, nói nhiều rồi, người chơi lãnh chúa đương nhiên có ưu thế hơn không phải người chơi lãnh chúa, nhưng ở đây có một tiền đề, chúng ta phải bảo đảm sinh tồn trước đã.” `sim=0.7000; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Ảnh hưởng quả thật không nhỏ, không có thân phận người chơi lãnh địa sẽ từ ‘Chuẩn - Thiên Tuyển Lĩnh Chủ’ rơi xuống thành ‘Thiên Tuyển Giả’, trên thống ngự binh chủng cũng có hạn chế về số lượng, không thể có được kiến trúc binh chủng v.v., tiền đồ tương lai còn kém xa... Khụ khụ, nói nhiều rồi, người chơi lãnh chúa đương nhiên có ưu thế hơn người chơi không phải lãnh chúa, nhưng ở đây có một tiền đề, chúng ta phải đảm bảo sinh tồn trước đã.” `sim=0.7056; han=0; modern=0; quote=True; digits=True`

## 6. [reference_60] semantic_context

- ZH: 前方三尺多高的小塔内，传来老者颇为得意的笑声，他心中感叹道：“五行灵根从古到今，都是极其罕见的灵根，就算发现有五行灵根拥有者也全都是些不入品，连一品都达不到，没想到我长生仙尊沦落到这种地步，还能找到灵根达到一品的五行灵根徒弟。”
- Tham chiếu: Từ tòa tháp nhỏ cao hơn ba thước phía trước vọng ra tiếng cười khá đắc ý của lão giả. Trong lòng hắn cảm khái: “Ngũ Hành Linh Căn từ xưa đến nay vẫn cực kỳ hiếm thấy. Thế nhưng những người sở hữu loại linh căn này từng được phát hiện đều chẳng nhập phẩm, ngay cả nhất phẩm cũng không đạt tới. Không ngờ Trường Sinh Tiên Tôn ta đã sa sút đến nông nỗi này mà vẫn có thể tìm được một đồ đệ mang Ngũ Hành Linh Căn đạt tới nhất phẩm.”
- base: Trong tòa tháp nhỏ cao hơn ba thước phía trước, truyền đến tiếng cười đầy đắc ý của lão giả, trong lòng hắn cảm thán: "Ngũ Hành Linh Căn từ xưa đến nay đều là linh căn cực kỳ hiếm thấy, dù có phát hiện người sở hữu Ngũ Hành Linh Căn cũng đều là những kẻ không nhập phẩm, ngay cả nhất phẩm cũng không đạt tới, không ngờ Trường Sinh Tiên Tôn ta lại sa sút đến mức này, còn có thể tìm được đồ đệ Ngũ Hành Linh Căn có linh căn đạt tới nhất phẩm." `sim=0.7758; han=0; modern=0; quote=True; digits=True`
- current: Từ trong tòa tháp nhỏ cao hơn ba thước phía trước, truyền đến tiếng cười đầy đắc ý của lão giả, trong lòng hắn cảm thán: "Ngũ Hành linh căn từ xưa đến nay, đều là linh căn cực kỳ hiếm thấy, cho dù phát hiện người sở hữu Ngũ Hành linh căn cũng toàn là những thứ không nhập phẩm, ngay cả nhất phẩm cũng không đạt tới, không ngờ Trường Sinh Tiên Tôn ta lại sa sút đến mức này, còn có thể tìm được đồ đệ Ngũ Hành linh căn đạt tới nhất phẩm." `sim=0.7822; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Từ trong tòa tháp nhỏ cao hơn ba thước phía trước, truyền đến tiếng cười đắc ý của lão giả, trong lòng ông thầm cảm thán: “Ngũ Hành Linh Căn từ xưa đến nay đều là linh căn cực kỳ hiếm thấy, cho dù phát hiện người sở hữu Ngũ Hành Linh Căn cũng toàn là những kẻ không nhập phẩm, ngay cả Nhất phẩm cũng không đạt tới. Không ngờ Trường Sinh Tiên Tôn của ta lại sa sút đến mức này, còn có thể tìm được đồ đệ Ngũ Hành Linh Căn có linh căn đạt tới Nhất phẩm.” `sim=0.7668; han=0; modern=0; quote=True; digits=True`

## 7. [reference_60] semantic_context

- ZH: “怎么，一个连护卫舰驾驶资格都没有的垃圾。你好意思在这里冷嘲热讽的？别忘了你自己是什么身份。一个土老帽而已。你除了坐在桌子后面大放厥词之外，你还能干嘛？你要是敢自己上场。那我倒是会高看你一眼。可是你敢吗？”
- Tham chiếu: “Sao nào? Một tên phế vật đến tư cách lái tàu hộ vệ cũng không có mà còn mặt mũi đứng đây châm chọc người khác? Đừng quên ngươi có thân phận gì, chẳng qua chỉ là một tên nhà quê. Ngoài ngồi sau bàn huênh hoang khoác lác, ngươi còn làm được gì? Nếu ngươi dám tự mình ra trận, ta còn có thể xem trọng ngươi đôi chút. Nhưng ngươi có dám không?”
- base: “Sao, một tên rác rưởi ngay cả tư cách lái tàu hộ vệ cũng không có. Ngươi còn mặt mũi ở đây châm chọc mỉa mai à? Đừng quên thân phận của mình là gì. Chỉ là một tên nhà quê thôi. Ngoài việc ngồi sau bàn nói khoác lác, ngươi còn có thể làm gì nữa? Nếu ngươi dám tự mình ra sân, thì ta sẽ đánh giá cao ngươi một cái. Nhưng ngươi dám không?” `sim=0.7045; han=0; modern=2; quote=True; digits=True`
- current: “Sao thế, một tên rác rưởi ngay cả tư cách lái xe hộ vệ cũng không có. Ngươi dám ở đây châm chọc mỉa mai à? Đừng quên thân phận của mình là gì. Chỉ là một tên nhà quê thôi. Ngoài việc ngồi sau bàn buông lời ngông cuồng, ngươi còn có thể làm gì nữa? Nếu ngươi dám tự mình ra sân, vậy ta sẽ đánh giá cao ngươi một bậc. Nhưng ngươi dám không?” `sim=0.6441; han=0; modern=2; quote=True; digits=True`
- teacher_v2: “Sao nào, một tên rác rưởi ngay cả tư cách lái tàu hộ vệ cũng không có. Ngươi còn mặt mũi ở đây châm chọc mỉa mai à? Đừng quên thân phận của mình là gì. Chỉ là một tên nhà quê thôi. Ngoài việc ngồi sau bàn nói khoác lác, ngươi còn có thể làm gì nữa? Nếu ngươi dám tự mình ra sân, thì ta sẽ đánh giá cao ngươi một bậc. Nhưng ngươi dám không?” `sim=0.7119; han=0; modern=2; quote=True; digits=True`

## 8. [reference_60] semantic_context

- ZH: 林默：“李兄说话虽然不中听，但分析的倒也没错。即便是我有几小队稀有兵种，也不会半个小时便升级领地。不是打不过，而是兵种升级也需要时间，用1级兵种来对抗怪物潮必然损失极大，得不偿失！”
- Tham chiếu: Lâm Mặc: “Lời Lý huynh tuy khó nghe, nhưng phân tích không sai. Cho dù ta có vài tiểu đội binh chủng hiếm, cũng không thể nâng cấp lãnh địa chỉ trong nửa canh giờ. Không phải chúng ta đánh không lại, mà binh chủng cũng cần thời gian thăng cấp. Dùng binh chủng cấp một đối đầu triều quái vật chắc chắn sẽ tổn thất cực lớn, lợi bất cập hại!”
- base: Lâm Mặc: "Lý huynh nói tuy không đúng, nhưng phân tích cũng không sai. Dù ta có vài tiểu đội binh chủng quý hiếm, cũng không thể nâng cấp lãnh địa trong nửa tiếng. Không phải đánh không lại, mà là binh chủng thăng cấp cũng cần thời gian, dùng binh chủng cấp 1 để đối kháng với triều quái vật ắt tổn thất cực lớn, được không bù mất!" `sim=0.7910; han=0; modern=0; quote=True; digits=True`
- current: Lâm Mặc: "Lý huynh nói chuyện tuy không lọt tai, nhưng phân tích cũng không sai. Dù ta có vài tiểu đội binh chủng hiếm có, cũng không thể nâng cấp lãnh địa trong nửa tiếng đồng hồ. Không phải đánh không lại, mà là binh chủng thăng cấp cũng cần thời gian, dùng binh chủng cấp 1 để đối kháng với triều quái vật tất sẽ tổn thất cực lớn, được không bù mất!" `sim=0.7715; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Lâm Mặc: “Lý huynh nói chuyện tuy không đúng, nhưng phân tích cũng không sai. Cho dù ta có vài tiểu đội binh chủng quý hiếm, cũng sẽ không nâng cấp lãnh địa trong nửa tiếng. Không phải đánh không lại, mà là binh chủng thăng cấp cũng cần thời gian, dùng binh chủng cấp 1 để đối kháng với thủy triều quái vật chắc chắn sẽ tổn thất cực lớn, được không bù mất!” `sim=0.8022; han=0; modern=0; quote=True; digits=True`

## 9. [reference_60] semantic_context

- ZH: “外界啊……”老人露出回忆之色，一阵出神与怅然后才道：“世界太大，广袤无垠，从一域到另一域动辄数以百万里，没人知道真正有多么广阔，一个人徒步走上一辈子也走不出一域之地，大荒茫茫无尽。人族不同地域间很难通信往来，因为实在太危险了，大地上强横物种诸多，可怕而神秘，纵然是几十万人的部落或者宏伟的巨城，也可能在一夜间被几头太古遗种毁掉。当然，也有强大到难以想象的人类，媲美其他物种的绝顶战力，神威无匹，可称之为人族天骄。”
- Tham chiếu: “Thế giới bên ngoài sao...” Lão nhân lộ vẻ hồi tưởng, thất thần hồi lâu rồi mới buồn bã nói: “Thế giới rộng lớn vô biên. Từ vực này sang vực khác thường cách nhau hàng trăm vạn dặm; không ai biết nó thật sự rộng đến mức nào. Một người đi bộ cả đời cũng không thể rời khỏi một vực. Đại Hoang mênh mang vô tận. Nhân tộc ở các khu vực khác nhau rất khó liên lạc qua lại, bởi đường đi thật sự quá nguy hiểm. Trên mặt đất có vô số giống loài mạnh mẽ, đáng sợ mà thần bí. Ngay cả bộ lạc mấy chục vạn người hay cự thành hùng vĩ cũng có thể bị vài con Thái Cổ di chủng hủy diệt chỉ trong một đêm. Đương nhiên, nhân loại cũng có những cường giả mạnh đến khó tưởng tượng, sở hữu chiến lực tuyệt đỉnh sánh ngang các giống loài khác, thần uy vô song, có thể xưng là thiên kiêu của nhân tộc.”
- base: "Bên ngoài à..." Lão nhân lộ vẻ hồi tưởng, Một lúc xuất thần và hụt hẫng mới nói: “Thế giới quá lớn, Quảng rộng mênh mông vô tận Từ một vực đến một vực khác thường là hàng trăm vạn dặm, Không ai biết thực sự rộng lớn đến mức nào Một người đi bộ cả đời cũng không đi ra được một vực, Đại Hoang mênh mông vô tận. Nhân tộc ở các địa vực khác nhau rất khó liên lạc qua lại, Bởi vì thực sự quá nguy hiểm Trên mặt đất có rất nhiều chủng loại cường hãn, Đáng sợ mà thần bí, Cho dù là bộ lạc mấy chục vạn người hoặc cự thành hùng vĩ, Cũng có thể trong một đêm bị mấy đầu Thái Cổ di chủng hủy diệt. Đương nhiên, Cũng có nhân loại cường đại đến khó có thể tưởng tượng, So sánh với chiến lực tuyệt đỉnh của các loài khác, Thần uy vô tận, Có thể gọi là thiên kiêu nhân tộc." `sim=0.7479; han=0; modern=0; quote=False; digits=True`
- current: "Bên ngoài à..." Lão nhân lộ vẻ hồi tưởng, Nhất thời xuất thần và hụt hẫng mới nói: "Thế giới quá rộng lớn, Quảng rộng vô biên, Từ một vực đến một vực khác thường lên tới hàng triệu dặm, Không ai biết thực sự rộng lớn đến mức nào, Một người đi bộ cả đời cũng không thể đi ra khỏi một vùng đất, Đại Hoang mênh mông vô tận. Nhân tộc các khu vực khác nhau rất khó liên lạc qua lại, Bởi vì thực sự quá nguy hiểm, Trên mặt đất có vô số loài mạnh mẽ, Đáng sợ mà thần bí, Dù là bộ lạc mấy chục vạn người hay cự thành hùng vĩ, Cũng có thể trong một đêm bị mấy con Thái Cổ di chủng hủy diệt. Đương nhiên, Cũng có những con người mạnh đến mức khó tưởng tượng, So sánh với chiến lực tuyệt đỉnh của các loài khác, Thần uy vô song, "Có thể gọi là thiên kiêu nhân tộc." `sim=0.7940; han=0; modern=0; quote=False; digits=True`
- teacher_v2: “Bên ngoài à...” Lão nhân lộ vẻ hồi tưởng, Một lúc xuất thần và hụt hẫng mới nói: “Thế giới quá lớn, Quảng rộng lớn vô biên, Từ một vực đến một vực khác thường lên tới hàng triệu dặm, Không ai biết thực sự rộng lớn đến mức nào, Một người đi bộ cả đời cũng không thể đi được một vùng đất nào, Đại Hoang mênh mông vô tận. Nhân tộc ở các vùng khác nhau rất khó liên lạc qua lại, Bởi vì quá nguy hiểm, Trên mặt đất có rất nhiều chủng loại cường hãn, Đáng sợ mà thần bí, Dù là bộ lạc mấy chục vạn người hay cự thành hùng vĩ, Cũng có thể chỉ trong một đêm đã bị mấy con Thái Cổ di chủng hủy diệt. Đương nhiên, Cũng có những con người mạnh đến mức khó tưởng tượng, So sánh với chiến lực tuyệt đỉnh của các loài khác, Thần uy vô song, Có thể gọi là thiên kiêu nhân tộc.” `sim=0.7650; han=0; modern=0; quote=True; digits=True`

## 10. [reference_60] semantic_context

- ZH: “四哥，这是我最后一次叫你四哥，”枫林五侠中年龄最小的赵汝成终于出声。他面容稍有稚色但已极为俊美，此刻说话，竟如金玉，落地有声：“方得财姓方！世代服侍你方家！一群败匪能拿出什么条件收买他？你是在侮辱你方家的财势，还是在侮辱我们大家的智慧？西山一群败家之犬，又是怎么混进的枫林城并且还能在望月楼堂然设下陷阱？最后，既然你没有以死明志的决心，方才这一番惺惺作态，又是演给谁看？我赵汝成耻与你为伍！”
- Tham chiếu: “Tứ ca, đây là lần cuối cùng ta gọi ngươi là tứ ca.” Triệu Nhữ Thành, người nhỏ tuổi nhất trong Phong Lâm Ngũ Hiệp, cuối cùng cũng lên tiếng. Gương mặt hắn vẫn còn nét non trẻ nhưng đã vô cùng tuấn mỹ; từng lời lúc này vang lên trong trẻo như vàng ngọc rơi xuống đất: “Phương Đắc Tài mang họ Phương! Gia tộc hắn nhiều đời hầu hạ Phương gia ngươi! Một đám giặc bại trận có thể đưa ra điều kiện gì để mua chuộc hắn? Ngươi đang sỉ nhục tài lực của Phương gia, hay sỉ nhục trí tuệ của tất cả chúng ta? Đám chó mất nhà ở Tây Sơn làm cách nào trà trộn vào Phong Lâm Thành, còn ngang nhiên giăng bẫy tại Vọng Nguyệt Lâu? Cuối cùng, nếu ngươi vốn không có quyết tâm lấy cái chết chứng minh chí hướng, vậy màn giả vờ vừa rồi diễn cho ai xem? Triệu Nhữ Thành ta hổ thẹn khi phải đứng cùng hàng ngũ với ngươi!”
- base: “Tứ ca, đây là lần cuối cùng ta gọi ngươi là Tứ ca,” Triệu Nhữ Thành, người nhỏ tuổi nhất của Phong Lâm Ngũ Hiệp cuối cùng cũng lên tiếng. Gương mặt hắn có chút ngây thơ nhưng đã vô cùng tuấn mỹ, Lúc này nói chuyện, Lại như kim ngọc, Rơi xuống đất có tiếng: “Phương Đắc Tài họ Phương! Thế hệ hầu hạ Phương gia các ngươi! Một đám bại phỉ có thể đưa ra điều kiện gì để mua chuộc hắn? Ngươi đang sỉ nhục tài thế của Phương gia các ngươi, Hay là đang sỉ nhục trí tuệ của mọi người chúng ta? Tây Sơn là một lũ chó phá gia chi tử, Làm sao trà trộn vào Phong Lâm Thành và còn có thể giăng bẫy ngay tại Vọng Nguyệt Lâu? Cuối cùng, Nếu ngươi đã không có quyết tâm lấy cái chết để minh chí Vừa rồi một phen làm bộ làm tịch, Lại diễn cho ai xem? Ta Triệu Nhữ thành sỉ nhục làm bạn với ngươi!" `sim=0.7585; han=0; modern=1; quote=False; digits=True`
- current: “Tứ ca, đây là lần cuối cùng ta gọi ngươi là Tứ ca,” Triệu Nhữ Thành, người nhỏ tuổi nhất của Phong Lâm Ngũ Hiệp, cuối cùng cũng lên tiếng. Gương mặt hắn hơi non nớt nhưng đã vô cùng tuấn mỹ, Lúc này nói chuyện, Lại như kim ngọc, Rơi xuống đất có tiếng: “Phương Đắc Tài họ Phương! Bao đời hầu hạ Phương gia các ngươi! Một lũ bại tặc có thể đưa ra điều kiện gì để mua chuộc hắn? Ngươi đang sỉ nhục tài thế của Phương gia các ngươi, Hay là đang sỉ nhục trí tuệ của mọi người chúng ta? Tây Sơn một lũ chó phá gia chi tử, Làm sao trà trộn vào Phong Lâm Thành và còn có thể giăng bẫy ngay tại Vọng Nguyệt Lâu? Cuối cùng, Ngươi đã không có quyết tâm lấy cái chết để minh chí, Vừa rồi bộ dạng giả tạo này, Lại diễn cho ai xem? Ta Triệu Nhữ thành sỉ nhục làm bạn với ngươi!" `sim=0.7572; han=0; modern=1; quote=False; digits=True`
- teacher_v2: “Tứ ca, đây là lần cuối cùng ta gọi ngươi là Tứ ca,” Triệu Nhữ Thành, người nhỏ tuổi nhất trong ngũ hiệp Phong Lâm, cuối cùng cũng lên tiếng. Gương mặt hắn hơi non nớt nhưng đã vô cùng tuấn mỹ, Lúc này nói chuyện, Lại như kim ngọc, Rơi xuống đất có tiếng: “Phương Đắc Tài họ Phương! Bao đời hầu hạ Phương gia các ngươi! Một lũ bại phỉ có thể đưa ra điều kiện gì để mua chuộc hắn? Ngươi đang sỉ nhục tài thế của Phương gia các ngươi, Hay là đang sỉ nhục trí tuệ của mọi người chúng ta? Tây Sơn là một lũ chó phá gia chi tử, Lại làm sao trà trộn vào Phong Lâm Thành và còn có thể giăng bẫy ngay tại Vọng Nguyệt Lâu? Cuối cùng, Vì ngươi không có quyết tâm lấy cái chết để minh chí, Vừa rồi một màn giả vờ giả tạo này, Lại diễn cho ai xem? Ta Triệu Nhữ thành sỉ nhục làm bạn với ngươi!” `sim=0.7579; han=0; modern=1; quote=True; digits=True`

## 11. [reference_60] dialogue_register

- ZH: “嗯！”这时，在树上行走的席然，忽然感觉一古腥臭味从后方传来，同时也伴随着一阵翅膀扑打的声音。“翼龙！”想都没想，席然对准身后就是两枪，一颗打中了后面向他袭击的翼龙身上，一颗则是因为慌张而打偏了，不过总算解除了这一次的危机。翼龙虽然能够飞翔，可生命值却是相当脆弱的，仅仅是中了一枪，这翼龙也变得奄奄一息了，头上的生命值就剩下五分之一。奄奄一息的翼龙也没有了拍打翅膀的能力，很是滑稽的居然从半空中掉落下去，活活摔死了。这让席然的脸se一阵怪异，浪费了两颗子弹居然是这个结果，席然真想说一句，“坑爹”。
- Tham chiếu: “Ừm!” Đang di chuyển trên cây, Tịch Nhiên chợt ngửi thấy một luồng tanh hôi từ phía sau, đồng thời nghe tiếng cánh đập. “Dực Long!” Không kịp suy nghĩ, hắn xoay người bắn liền hai phát. Một viên trúng con Dực Long đang tập kích từ phía sau, viên còn lại vì hoảng hốt nên bay chệch, nhưng cuối cùng nguy cơ cũng được hóa giải. Dực Long tuy biết bay nhưng sinh mệnh lại vô cùng yếu ớt; chỉ trúng một phát đã thoi thóp, thanh sinh mệnh trên đầu chỉ còn một phần năm. Nó không còn sức vỗ cánh, cứ thế rơi khỏi không trung rồi ngã chết, trông vừa buồn cười vừa khó tin. Sắc mặt Tịch Nhiên trở nên cổ quái. Hắn đã lãng phí hai viên đạn mà cuối cùng lại nhận được kết quả thế này, thật chỉ muốn mắng một câu: “Đúng là chơi người!”
- base: "Ừ!" Lúc này, Tịch Nhiên đang đi trên cây bỗng nhiên cảm thấy mùi tanh hôi từ phía sau truyền đến, đồng thời cũng kèm theo tiếng vỗ cánh. "Dực Long!" Không chút do dự, hắn lặng lẽ nhắm vào hai phát súng phía sau, một tên trúng vào Dực Long đang tập kích hắn phía sau, một tên thì vì hoảng loạn mà đánh lệch, nhưng cuối cùng cũng giải trừ được nguy cơ lần này. Tuy Dực Long có thể bay lượn, nhưng giá trị sinh mệnh lại vô cùng yếu ớt, chỉ trúng một thương, Dực Long cũng trở nên thoi thóp, điểm sinh mệnh trên đầu chỉ còn lại một phần năm. Dực Long thoi thóp cũng không còn khả năng vỗ cánh, rất buồn cười mà từ trên không trung rơi xuống, ngã chết tươi. Điều này khiến sắc mặt Tịch Nhiên trở nên kỳ quái, lãng phí hai viên đạn lại là kết quả như vậy, Tịch Nhiên thật muốn nói một câu, “Hố cha”. `sim=0.6214; han=0; modern=0; quote=True; digits=True`
- current: "Ừm!" Lúc này, Tịch Nhiên đang đi trên cây bỗng cảm thấy mùi tanh hôi từ phía sau truyền đến, đồng thời cũng kèm theo tiếng vỗ cánh. "Dực Long!" Không chút do dự, hắn nhắm thẳng về phía sau bắn hai phát, một phát trúng Dực Long đang tấn công hắn phía sau, một con thì bị đánh lệch vì hoảng loạn, nhưng cuối cùng cũng giải trừ được nguy cơ lần này. Dực Long tuy có thể bay lượn, nhưng sinh mệnh lại vô cùng yếu ớt, chỉ trúng một phát súng, Dực Long cũng trở nên thoi thóp, sinh mệnh trên đầu chỉ còn lại một phần năm. Dực Long thoi thóp cũng không còn khả năng vỗ cánh, rất buồn cười lại rơi từ trên không trung xuống, ngã chết tươi. Điều này khiến mặt Tịch Nhiên trở nên kỳ quái, lãng phí hai viên đạn lại là kết quả như vậy, Tịch Nhiên thật muốn nói một câu, “Hố cha”. `sim=0.6213; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Ừm!” Lúc này, Tịch Nhiên đang đi trên cây bỗng cảm thấy mùi tanh hôi của Nhất Cổ truyền đến từ phía sau, đồng thời cũng kèm theo tiếng vỗ cánh. “Dực Long!” Không cần suy nghĩ, Tịch Nhiên nhắm thẳng vào hai phát súng sau lưng, một phát trúng Dực Long đang tấn công về phía sau, một con thì bị đánh lệch vì hoảng loạn, nhưng cuối cùng cũng giải trừ được nguy cơ lần này. Tuy Dực Long có thể bay lượn, nhưng giá trị sinh mệnh lại vô cùng yếu ớt, chỉ trúng một phát súng, Dực Long cũng trở nên thoi thóp, điểm sinh mệnh trên đầu chỉ còn lại một phần năm. Dực Long thoi thóp cũng không còn khả năng vỗ cánh, rất buồn cười lại rơi từ trên không trung xuống, ngã chết tươi. Điều này khiến mặt Tịch Nhiên trở nên kỳ quái, việc lãng phí hai viên đạn lại là kết quả như vậy, Tịch Nhiên thật sự muốn nói một câu, “Đùa cha”. `sim=0.6083; han=0; modern=0; quote=True; digits=True`

## 12. [reference_60] dialogue_register

- ZH: 安呆呆的站在那里，狠狠的抓了抓脑袋，不解的说道：“Alin的确受伤了啊，可是又不是什么大不了的伤势，不过是为了抓住你这小子，耗费了太多的体力，然后手上擦伤了不少，休息几天也就恢复了，你这么着急干什么？”突然间，安又兴奋起来：“啊，所谓的奥义训练，不知道会教给我们什么东西呢？唔，应该比在这里学到的东西强很多罢？哈哈哈，有了这些强大的技能，等我回去镇子上，哼哼……”
- Tham chiếu: Ann ngây người đứng đó, gãi mạnh đầu rồi khó hiểu nói: “Alin đúng là bị thương, nhưng có nghiêm trọng gì đâu. Chẳng qua vì bắt tên tiểu tử ngươi mà hắn hao quá nhiều thể lực, tay lại trầy xước không ít. Nghỉ vài ngày là khỏi, ngươi sốt ruột như vậy làm gì?” Đột nhiên, Ann lại trở nên phấn khích: “À, không biết cái gọi là huấn luyện áo nghĩa sẽ dạy chúng ta thứ gì? Ừm, hẳn phải mạnh hơn những thứ học ở đây rất nhiều chứ? Ha ha ha, có được những kỹ năng mạnh như vậy, đợi ta trở về thị trấn, hừ hừ...”
- base: An ngơ ngác đứng đó, Hắn hung hăng gãi gãi đầu Khó hiểu nói: "A Lâm đúng là bị thương rồi, Nhưng cũng không phải thương thế gì to tát, Chẳng qua là vì bắt được tiểu tử ngươi Tiêu tốn quá nhiều thể lực, Sau đó tay hắn đã bị trầy xước không ít, Nghỉ ngơi vài ngày là hồi phục, Ngươi vội vàng như vậy làm gì?" Đột nhiên, An lại trở nên phấn khích: “A, Cái gọi là huấn luyện áo nghĩa, Không biết sẽ dạy cho chúng ta thứ gì đây? Ừm, Chắc là tốt hơn nhiều so với những gì học được ở đây nhỉ? Ha ha ha, Có những kỹ năng cường đại này, Đợi ta trở về trấn, Hừ hừ..." `sim=0.7120; han=0; modern=0; quote=False; digits=True`
- current: An ngơ ngác đứng đó, Hắn hung hăng gãi đầu, Hắn khó hiểu nói: "A Lâm đúng là bị thương rồi, Nhưng cũng không phải thương thế gì to tát, Chẳng qua là để bắt lấy tiểu tử ngươi, Tiêu hao quá nhiều thể lực, Sau đó tay hắn bị trầy xước không ít, Nghỉ ngơi vài ngày rồi cũng hồi phục, "Ngươi vội vàng làm gì?" Đột nhiên, An Hựu hưng phấn hẳn lên: "A, Cái gọi là huấn luyện áo nghĩa, Không biết sẽ dạy cho chúng ta thứ gì đây? Ừm, Chắc là tốt hơn nhiều so với những gì học được ở đây nhỉ? Ha ha ha, Có được những kỹ năng mạnh mẽ này, Đợi ta trở về trấn, "Hừ hừ..." `sim=0.6796; han=0; modern=0; quote=True; digits=True`
- teacher_v2: An ngơ ngác đứng đó, Hắn hung hăng gãi đầu, Hắn khó hiểu nói: “A Lâm đúng là bị thương rồi, Nhưng cũng không phải thương thế gì lớn, Chẳng qua là để bắt tiểu tử ngươi, Tiêu tốn quá nhiều thể lực, Sau đó tay hắn đã bị trầy xước không ít, Nghỉ ngơi vài ngày là hồi phục, Ngươi vội vàng làm gì thế?” Đột nhiên, An lại trở nên phấn khích: “A, Cái gọi là huấn luyện áo nghĩa, Không biết sẽ dạy cho chúng ta thứ gì đây? Ừm, Chắc là tốt hơn nhiều so với những gì học được ở đây nhỉ? Ha ha ha, Có được những kỹ năng mạnh mẽ này, Đợi ta trở về trấn, Hừ hừ...” `sim=0.7237; han=0; modern=0; quote=True; digits=True`

## 13. [reference_60] dialogue_register

- ZH: “莫凡，你怎么又迟到，就不能态度端正一点吗，你本来就天赋不如绝大多数同学，底子又特别差劲，还学得这么不认真，你看看我们班的照庭同学，天赋雷系，天资聪颖，底子好，学魔法态度又好，别人现在已经可以把控4颗雷系星子，而你呢，我听说你火系星子至今还不会把控，火系的觉醒在你身上都要浪费了！”张建国一看到莫凡姗姗来迟，马上毫不客气的训斥了起来。
- Tham chiếu: “Mạc Phàm, sao ngươi lại đến muộn nữa? Không thể nghiêm túc hơn một chút sao? Thiên phú của ngươi vốn đã kém phần lớn học viên, căn cơ lại đặc biệt yếu, vậy mà học hành còn chẳng chăm chỉ. Nhìn Chiếu Đình trong lớp chúng ta đi: thức tỉnh Lôi hệ, tư chất thông minh, căn cơ tốt, thái độ học ma pháp cũng nghiêm túc. Giờ hắn đã có thể khống chế bốn viên Lôi hệ tinh tử. Còn ngươi thì sao? Ta nghe nói đến nay ngươi vẫn chưa khống chế nổi Hỏa hệ tinh tử. Hỏa hệ thức tỉnh trên người ngươi đúng là bị uổng phí!” Vừa thấy Mạc Phàm thong thả đến muộn, Trương Kiến Quốc lập tức không chút khách khí quở trách.
- base: "Mạc Phàm, Sao ngươi lại đến muộn rồi Không thể giữ thái độ đoan chính hơn một chút sao, Vốn dĩ thiên phú của ngươi không bằng tuyệt đại đa số bạn học, Nền tảng lại đặc biệt kém cỏi, Còn học không nghiêm túc như vậy, Ngươi nhìn bạn học Chiếu Đình lớp chúng ta xem, Thiên phú Lôi hệ, Thiên tư thông minh, Nền tảng tốt, Thái độ học ma pháp lại tốt, Người khác hiện tại đã có thể khống chế 4 ngôi sao lôi hệ, Còn ngươi thì sao Ta nghe nói Hỏa hệ Tinh Tử của ngươi đến nay vẫn chưa khống chế được Việc thức tỉnh hỏa hệ ở trên người ngươi đều phải lãng phí rồi!" Trương Kiến Quốc vừa thấy Mạc Phàm đến muộn, Lập tức không chút khách khí quở trách. `sim=0.6379; han=0; modern=2; quote=True; digits=True`
- current: "Mạc Phàm, Sao ngươi lại đến muộn thế? Không thể giữ thái độ đoan chính hơn, Ngươi vốn dĩ thiên phú không bằng tuyệt đại đa số bạn học, Nền tảng lại cực kỳ kém cỏi, Còn học không nghiêm túc như vậy, [Ngươi nhìn bạn học Chiếu Đình lớp chúng ta xem,] Thiên phú Lôi hệ, Thiên tư thông minh, Nền tảng tốt, Học ma pháp thái độ lại tốt, Người khác hiện tại đã có thể khống chế 4 viên tinh tử hệ Lôi, Còn ngươi thì sao, Ta nghe nói Tinh tử hệ Hỏa của ngươi đến nay vẫn chưa khống chế được, 【Thức tỉnh hệ Hỏa】 ở trên người ngươi đều lãng phí hết rồi!" Trương Kiến Quốc vừa thấy Mạc Phàm đến muộn, Lập tức không chút khách khí quở trách. `sim=0.4933; han=0; modern=2; quote=True; digits=True`
- teacher_v2: “Mạc Phàm, Sao ngươi lại đến muộn rồi? Không thể giữ thái độ đoan chính hơn một chút sao, Vốn dĩ thiên phú của ngươi không bằng tuyệt đại đa số bạn học, Nền tảng lại đặc biệt kém cỏi, Còn học không nghiêm túc như vậy, Cậu nhìn bạn học Chiếu Đình lớp chúng tôi xem, Thiên phú Lôi hệ, Thiên tư thông minh, Nền tảng tốt, Thái độ học ma pháp lại tốt, Người khác hiện tại đã có thể khống chế được 4 ngôi sao hệ Lôi, Còn ngươi thì sao, Ta nghe nói Tinh tử hệ Hỏa của ngươi đến nay vẫn chưa kiểm soát được Việc thức tỉnh hệ Hỏa sẽ lãng phí hết cả lên người ngươi đấy!” Trương Kiến Quốc vừa thấy Mạc Phàm đến muộn, Lập tức không khách khí mà quở trách. `sim=0.6045; han=0; modern=4; quote=True; digits=True`

## 14. [reference_60] dialogue_register

- ZH: “咳咳兄弟，打扰一下，我相信你现在有着很多困惑和迷茫……哦对，忘了先自我介绍，我是这个论坛的管理者，和你一样是一名超凡游戏玩家，同时也是玄国官方有关部门的工作人员，你可以叫我杨空……对了，看到我头像没，我女儿很可爱吧。”
- Tham chiếu: “Khụ khụ, huynh đệ, làm phiền một chút. Ta tin hiện giờ ngươi đang có rất nhiều nghi vấn... À đúng rồi, quên tự giới thiệu. Ta là người quản lý diễn đàn này, cũng là một người chơi trò chơi siêu phàm giống ngươi, đồng thời làm việc cho cơ quan hữu quan của Huyền Quốc. Ngươi có thể gọi ta là Dương Không... Phải rồi, ngươi thấy ảnh đại diện của ta chưa? Con gái ta đáng yêu lắm đúng không?”
- base: “Khụ khụ huynh đệ, làm phiền một chút, ta tin rằng hiện tại ngươi có rất nhiều khó hiểu và mơ hồ... Ồ đúng rồi, quên tự giới thiệu trước, ta là người quản lý diễn đàn này, giống như ngươi, là một người chơi game siêu phàm, đồng thời cũng là nhân viên của bộ phận liên quan chính thức Huyền Quốc, ngươi có thể gọi ta là Dương Không... Đúng rồi, thấy ảnh đại diện của ta chưa, con gái ta rất đáng yêu đúng không.” `sim=0.7785; han=0; modern=0; quote=True; digits=True`
- current: “Khụ khụ huynh đệ, làm phiền một chút, ta tin rằng hiện tại ngươi có rất nhiều khó hiểu và mơ hồ... Ồ đúng rồi, quên tự giới thiệu trước, ta là người quản lý diễn đàn này, giống như ngươi, là một người chơi game siêu phàm, đồng thời cũng là nhân viên của cơ quan chính thức Huyền Quốc, ngươi có thể gọi ta là Dương Không... Đúng rồi, thấy ảnh đại diện của ta chưa, con gái ta đáng yêu lắm phải không.” `sim=0.7917; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Khụ khụ huynh đệ, làm phiền một chút, ta tin ngươi bây giờ có rất nhiều khó hiểu và mơ hồ... À đúng rồi, quên tự giới thiệu trước, ta là người quản lý diễn đàn này, cũng là một người chơi game siêu phàm giống ngươi, đồng thời cũng là nhân viên của bộ phận liên quan chính thức Huyền Quốc, ngươi có thể gọi ta là Dương Không... Đúng rồi, thấy ảnh đại diện của ta chưa, con gái ta đáng yêu lắm phải không?” `sim=0.8134; han=0; modern=0; quote=True; digits=True`

## 15. [reference_60] dialogue_register

- ZH: 林浩忍不住握了握拳头，心中想道：“沉睡的师父长生仙尊说，一品五行灵根在远古是顶级灵根，只是修炼所需灵气巨大而已，靠着万古长生塔，和五行长生功，相信要不了多久，我就能让这些家伙闭嘴。”
- Tham chiếu: Lâm Hạo không nhịn được siết chặt nắm tay, thầm nghĩ: “Sư phụ Trường Sinh Tiên Tôn đang ngủ say từng nói, Ngũ Hành Linh Căn nhất phẩm là linh căn đỉnh cấp thời viễn cổ, chỉ có điều cần lượng linh khí khổng lồ để tu luyện. Có Vạn Cổ Trường Sinh Tháp và Ngũ Hành Trường Sinh Công, tin rằng chẳng bao lâu nữa ta sẽ khiến đám người kia phải câm miệng.”
- base: Lâm Hạo nhịn không được nắm chặt nắm đấm, trong lòng thầm nghĩ: "Sư phụ ngủ say Trường Sinh Tiên Tôn nói, linh căn ngũ hành nhất phẩm ở thời viễn cổ là linh căn đỉnh cấp, chỉ là cần linh khí tu luyện cực lớn mà thôi, dựa vào Vạn Cổ Trường Sinh Tháp cùng Ngũ Hành Trường Sinh Công, tin tưởng không bao lâu nữa, ta có thể khiến bọn chúng câm miệng." `sim=0.6837; han=0; modern=0; quote=True; digits=True`
- current: Lâm Hạo không nhịn được nắm chặt nắm đấm, trong lòng thầm nghĩ: "Sư phụ ngủ say Trường Sinh Tiên Tôn nói, nhất phẩm ngũ hành linh căn ở viễn cổ là linh căn đỉnh cấp, chỉ là linh khí cần thiết để tu luyện cực lớn mà thôi, dựa vào Vạn Cổ Trường Sinh Tháp và Ngũ Hành Trường Sinh Công, tin rằng không bao lâu nữa, ta có thể khiến bọn chúng câm miệng." `sim=0.7166; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Lâm Hạo không nhịn được nắm chặt nắm đấm, trong lòng thầm nghĩ: “Sư phụ Trường Sinh Tiên Tôn đang ngủ say nói, linh căn Ngũ Hành nhất phẩm ở thời viễn cổ là linh căn đỉnh cấp, chỉ là linh khí cần thiết cho việc tu luyện cực lớn mà thôi. Dựa vào Vạn Cổ Trường Sinh Tháp và Ngũ Hành Trường Sinh Công, tin rằng không bao lâu nữa ta sẽ khiến bọn chúng câm miệng.” `sim=0.7482; han=0; modern=0; quote=True; digits=True`

## 16. [reference_60] dialogue_register

- ZH: 李沐泽继续道：“江辰你听好了，你还有一个小时时间准备，希望到时候你领地内的精铁数量能够让我满意。还有，你不许抵抗，我的兵种死一个，我便摧毁你的领地；死两个，你便永远留在万族战场吧。”
- Tham chiếu: Lý Mộc Trạch tiếp tục: “Giang Thần, nghe cho kỹ. Ngươi còn một canh giờ để chuẩn bị. Hy vọng đến lúc ấy, số tinh thiết trong lãnh địa của ngươi đủ khiến ta hài lòng. Còn nữa, ngươi không được phép chống cự. Một binh chủng của ta chết, ta sẽ phá hủy lãnh địa của ngươi; nếu hai tên chết, ngươi sẽ vĩnh viễn chôn thân tại chiến trường Vạn Tộc.”
- base: Lý Mộc Trạch tiếp tục nói: "Giang Thần ngươi nghe cho kỹ, ngươi còn một giờ chuẩn bị, hy vọng đến lúc đó số lượng tinh thiết trong lãnh địa của ngươi có thể làm ta hài lòng. Còn nữa, ngươi không được kháng cự, binh chủng của ta chết một tên, ta sẽ phá hủy lãnh địa của ngươi; chết hai tên, ngươi sẽ vĩnh viễn ở lại chiến trường vạn tộc." `sim=0.8411; han=0; modern=0; quote=True; digits=True`
- current: Lý Mộc Trạch tiếp tục nói: “Giang Thần, ngươi nghe cho kỹ đây, ngươi còn một giờ chuẩn bị, hy vọng đến lúc đó số lượng tinh thiết trong lãnh địa của ngươi có thể làm ta hài lòng. Còn nữa, ngươi không được chống cự, binh chủng của ta chết một tên, ta sẽ phá hủy lãnh địa của ngươi; chết hai tên, ngươi hãy vĩnh viễn ở lại chiến trường vạn tộc đi.” `sim=0.8413; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Lý Mộc Trạch tiếp tục nói: “Giang Thần, ngươi nghe cho kỹ đây, ngươi còn một giờ chuẩn bị, hy vọng đến lúc đó số lượng tinh thiết trong lãnh địa của ngươi có thể làm ta hài lòng. Còn nữa, ngươi không được chống cự, binh chủng của ta chết một tên, ta sẽ phá hủy lãnh địa của ngươi; chết hai tên, ngươi hãy mãi mãi ở lại chiến trường vạn tộc.” `sim=0.8253; han=0; modern=0; quote=True; digits=True`

## 17. [reference_60] dialogue_register

- ZH: “呵呵，这不是战五渣领主吗。这么早就过来。是准备提前来观察地形的吗。那你可能要失望了。这里的地形可是很复杂的。一个弄不好，你可能就要撞山。啧啧，那一定非常有趣。”
- Tham chiếu: “Ha ha, đây chẳng phải vị lãnh chúa phế vật sao? Đến sớm như vậy là định quan sát địa hình trước à? Thế thì ngươi e phải thất vọng rồi. Địa hình nơi này phức tạp lắm, chỉ sơ suất một chút là có thể đâm thẳng vào núi. Chậc chậc, cảnh đó nhất định sẽ thú vị lắm.”
- base: "Ha ha, đây không phải là Chiến Ngũ Tra Lĩnh Chủ sao. Đến sớm như vậy, là chuẩn bị đến quan sát địa hình trước sao. Vậy ngươi có thể phải thất vọng rồi. Địa hình nơi này rất phức tạp. Không khéo một chút, ngươi có thể sẽ đâm đầu vào núi. Chậc chậc, vậy nhất định rất thú vị." `sim=0.6954; han=0; modern=0; quote=True; digits=True`
- current: “Ha ha, đây không phải là Chiến Ngũ Tra Lĩnh Chủ sao. Đến sớm như vậy, là chuẩn bị đến quan sát địa hình trước sao. Vậy ngươi có thể phải thất vọng rồi. Địa hình nơi này rất phức tạp. Không khéo một chút, ngươi có thể sẽ đâm đầu vào núi. Chậc chậc, vậy nhất định rất thú vị.” `sim=0.7050; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Ha ha, đây không phải là Chiến Ngũ Tra Lĩnh Chủ sao. Đến sớm như vậy. Là chuẩn bị đến quan sát địa hình trước sao. Vậy ngươi có lẽ phải thất vọng rồi. Địa hình ở đây rất phức tạp. Nếu không cẩn thận, ngươi có thể sẽ đâm đầu vào núi. Chậc chậc, chắc chắn rất thú vị.” `sim=0.6439; han=0; modern=0; quote=True; digits=True`

## 18. [reference_60] dialogue_register

- ZH: 听到师傅的话，很奇怪以前自己的装备都是师父提前准备好的傲天不禁问道：“师父，以前我需要的东西部都是您准备好了给我的吗？这次怎么没有啊？”
- Tham chiếu: Nghe sư phụ nói vậy, Ngạo Thiên không khỏi cảm thấy kỳ lạ. Trước đây mọi thứ hắn cần đều được sư phụ chuẩn bị sẵn, vì thế hắn hỏi: “Sư phụ, trước kia chẳng phải những thứ con cần đều do người chuẩn bị rồi giao cho con sao? Tại sao lần này lại không có?”
- base: Nghe lời sư phụ, thật kỳ lạ khi trước đây trang bị của mình đều do sư phụ chuẩn bị sẵn, Ngạo Thiên hỏi: "Sư phụ, những thứ ta cần trước đây đều là ngài chuẩn bị sẵn sàng cho ta sao? Sao lần này lại không có?" `sim=0.6201; han=0; modern=1; quote=True; digits=True`
- current: Nghe lời sư phụ, rất kỳ lạ trước đây trang bị của ta đều là Ngạo Thiên sư phụ chuẩn bị sẵn, không nhịn được hỏi: "Sư phụ, những bộ phận ta cần trước đây đều là ngài chuẩn bị sẵn sàng cho ta sao? Sao lần này lại không có?" `sim=0.5109; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Nghe lời sư phụ, rất kỳ lạ khi trước đây trang bị của mình đều do sư phụ chuẩn bị sẵn, Ngạo Thiên hỏi: “Sư phụ, những thứ ta cần trước đây đều là người chuẩn bị sẵn sàng cho con sao? Sao lần này lại không có?” `sim=0.6462; han=0; modern=1; quote=True; digits=True`

## 19. [reference_60] dialogue_register

- ZH: “二叔虽然实力不强，给你搞不到那种血脉珍稀的妖兽，但是精英级血脉的妖兽幼崽还是能搞到的，你喜欢什么妖兽，我去给你找？”
- Tham chiếu: “Thực lực của nhị thúc tuy không mạnh, không thể kiếm cho ngươi loại yêu thú mang huyết mạch quý hiếm, nhưng ấu thú có huyết mạch cấp Tinh Anh thì vẫn tìm được. Ngươi thích loại yêu thú nào? Ta sẽ đi tìm cho ngươi.”
- base: "Nhị thúc tuy thực lực không mạnh, không kiếm được loại yêu thú có huyết mạch trân quý như vậy, nhưng ấu thú yêu thú có huyết mạch tinh anh thì vẫn có thể kiếm được, ngươi thích yêu thú gì, ta đi tìm cho ngươi?" `sim=0.6071; han=0; modern=0; quote=True; digits=True`
- current: "Nhị thúc tuy thực lực không mạnh, không kiếm được loại yêu thú có huyết mạch quý hiếm đó cho ngươi, nhưng ấu tể yêu thú có huyết mạch cấp tinh anh thì vẫn có thể kiếm được, ngươi thích yêu thú gì, ta đi tìm cho ngươi?" `sim=0.7661; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Nhị thúc tuy thực lực không mạnh, nhưng không kiếm được loại yêu thú có huyết mạch trân quý như vậy, nhưng ấu thú yêu thú có huyết mạch cấp tinh anh thì vẫn có thể kiếm được. Cháu thích yêu thú gì, để cháu đi tìm cho cháu nhé?” `sim=0.6877; han=0; modern=3; quote=True; digits=True`

## 20. [reference_60] dialogue_register

- ZH: “哈？丧尸，什么东西啊，是不是有人在外面放广播扰民啊。”——一个一直沉浸在游戏中的男孩放下游戏机，叫骂道。
- Tham chiếu: “Hả? Xác sống? Thứ gì vậy? Có kẻ nào bên ngoài mở loa quấy rầy mọi người sao?” Một thiếu niên vẫn luôn chìm đắm trong trò chơi đặt máy chơi game xuống, bực bội chửi lớn.
- base: "Hả? Zombie, cái gì vậy, có phải có người đang phát thanh quảng bá quấy nhiễu người khác không?" - Một cậu bé vẫn luôn đắm chìm trong game đặt máy chơi game xuống, chửi bới. `sim=0.4797; han=0; modern=1; quote=True; digits=True`
- current: "Hả? Zombie, thứ gì vậy, có phải có người đang ở bên ngoài phát sóng làm phiền người không?" - Một cậu bé vẫn luôn đắm chìm trong game đặt máy chơi game xuống, chửi bới. `sim=0.5693; han=0; modern=1; quote=True; digits=True`
- teacher_v2: “Hả? Zombie, cái gì thế này, có phải có người ở bên ngoài phát thanh quảng bá quấy nhiễu người khác không?” —— Một cậu bé vẫn luôn đắm chìm trong game đặt máy chơi game xuống, chửi rủa. `sim=0.5286; han=0; modern=1; quote=True; digits=True`

## 21. [reference_60] domain_terms

- ZH: 好吧，在这个类似于游戏的世界里，有不少的事情都变得简单了许多，没有多久两个化石矿已经出现在帐篷附近，而采集也变得简单了许多。化石矿上面有一个凹槽，恰好是两个手掌状的只要双手放进里面按着凹槽里的按钮两分钟，便完成一次采集，一次采集能能够获得10个单位的黄金，虽然一次xing比游戏里多了不少，可是按照时间的比例来算比起游戏里确实是慢了许多。席然获得了第一次采集完成之后心中想道“按照这个速度，一个小时大概能够获得300单位的金币吧。不过，一直保持这个姿势，按照我现在的身体素质实在是太折腾了些。”
- Tham chiếu: Trong thế giới giống trò chơi này, rất nhiều việc đã trở nên đơn giản hơn. Chẳng bao lâu sau, hai mỏ hóa thạch xuất hiện gần lều, cách thu thập cũng vô cùng dễ dàng. Trên mỗi mỏ có hai hõm vừa khít hình bàn tay; chỉ cần đặt hai tay vào, giữ nút bên trong hai phút là hoàn thành một lần thu thập. Mỗi lần có thể nhận mười đơn vị vàng. Sản lượng một lượt cao hơn trong trò chơi khá nhiều, nhưng nếu tính theo thời gian thì thật ra lại chậm hơn hẳn. Hoàn thành lần thu thập đầu tiên, Tịch Nhiên thầm tính: “Với tốc độ này, một giờ đại khái thu được ba trăm đơn vị vàng. Nhưng cứ phải giữ nguyên tư thế, với thể chất hiện tại của ta thì quả thật quá khổ sở.”
- base: Được rồi, trong thế giới giống như trò chơi này, có không ít chuyện trở nên đơn giản hơn nhiều, không lâu sau hai mỏ hóa thạch đã xuất hiện gần lều bạt, mà thu thập cũng trở nên đơn giản hơn nhiều. Trên mỏ hóa thạch có một cái rãnh, vừa vặn là hai bàn tay hình bàn tay, chỉ cần hai tay đặt vào bên trong ấn nút trong rãnh hai phút, liền hoàn thành một lần thu thập, một lần thu thập có thể nhận được 10 đơn vị vàng, mặc dù một lần Xing nhiều hơn trong game không ít, nhưng tính theo tỷ lệ thời gian thì so với trong game thì quả thực chậm hơn rất nhiều. Sau khi Tịch Nhiên đạt được lần thu thập đầu tiên, trong lòng thầm nghĩ: "Theo tốc độ này, khoảng một giờ có thể nhận được 300 đơn vị vàng. Tuy nhiên, cứ giữ nguyên tư thế này, dựa theo tố chất cơ thể hiện tại của ta thật sự quá vất vả." `sim=0.6270; han=0; modern=0; quote=True; digits=True`
- current: Được rồi, trong thế giới giống như trò chơi này, có không ít chuyện trở nên đơn giản hơn nhiều, không lâu sau hai mỏ hóa thạch đã xuất hiện gần lều bạt, mà việc thu thập cũng trở nên đơn giản hơn nhiều. Trên mỏ Hóa Thạch có một rãnh lõm, vừa vặn là hai bàn tay hình bàn tay, chỉ cần hai tay đặt vào bên trong ấn nút trong rãnh hai phút, liền hoàn thành một lần thu thập, một lần thu thập có thể nhận được 10 đơn vị vàng, tuy một lần xing nhiều hơn trong game không ít, nhưng tính theo tỷ lệ thời gian thì quả thực chậm hơn rất nhiều so với trong game. Tịch Nhiên sau khi nhận được lần thu thập đầu tiên hoàn tất, trong lòng thầm nghĩ: "Theo tốc độ này, một tiếng đồng hồ có thể nhận được 300 đơn vị tiền vàng. Tuy nhiên, vẫn luôn giữ nguyên tư thế này, dựa theo tố chất cơ thể hiện tại của ta thực sự quá giày vò." `sim=0.6096; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Được rồi, trong thế giới giống như trò chơi này, có không ít chuyện trở nên đơn giản hơn nhiều, không lâu sau hai mỏ hóa thạch đã xuất hiện gần lều, và việc thu thập cũng trở nên đơn giản hơn nhiều. Trên mỏ hóa thạch có một cái rãnh, vừa vặn là hai bàn tay hình bàn tay, chỉ cần hai tay đặt vào bên trong ấn nút trong rãnh hai phút, liền hoàn thành một lần thu thập, một lần thu thập có thể nhận được 10 đơn vị vàng, mặc dù một lần so với trong game nhiều hơn không ít, nhưng tính theo tỷ lệ thời gian thì quả thực chậm hơn nhiều so với trong game. Sau khi hoàn thành lần thu thập đầu tiên, Tịch Nhiên thầm nghĩ: “Theo tốc độ này, khoảng một giờ có thể nhận được khoảng 300 đơn vị tiền vàng. Tuy nhiên, cứ giữ nguyên tư thế này, theo thể chất hiện tại của ta thì thật sự quá vất vả.” `sim=0.6690; han=0; modern=0; quote=True; digits=True`

## 22. [reference_60] domain_terms

- ZH: 在场的高层神职人员同时点头还礼，在三名红衣圣堂的率领下，快步的走了出去。直到这些高层走远了，一直站在角落里的哈尔才猛的吐出了一口气，喃喃自语到：“这次可真是幸运呀，莱茵哈特！你受了邪恶的血族魔法的污染，虽然没有死，可是力量却被破坏得差不多了！幸好有两名红衣圣堂正在欧洲处理事务，加上神庭总部派来的神巢的新领导，三位红衣圣堂联手，才在最短的时间内让你复原呀。”
- Tham chiếu: Các thần chức cấp cao có mặt đồng loạt gật đầu đáp lễ rồi nhanh chóng rời đi dưới sự dẫn dắt của ba vị Hồng Y Thánh Đường. Đợi những người ấy đi xa, Harl vẫn đứng trong góc mới thở phào, lẩm bẩm: “Lần này ngươi thật sự quá may mắn, Reinhardt! Ngươi bị ma pháp tà ác của Huyết Tộc làm ô nhiễm. Tuy không chết, sức mạnh lại gần như bị phá hủy hoàn toàn! May mà có hai vị Hồng Y Thánh Đường đang xử lý công việc tại châu Âu, cộng thêm tân lãnh đạo Thần Sào do tổng bộ Thần Đình phái tới. Nhờ ba người liên thủ, ngươi mới có thể hồi phục trong thời gian ngắn nhất.”
- base: Các thần chức cấp cao hiện trường đồng loạt gật đầu đáp lễ, dưới sự dẫn dắt của ba vị Hồng Y Thánh Đường, bước nhanh ra ngoài. Cho đến khi những cao tầng này đi xa, Harl vẫn luôn đứng trong góc mới thở phào một hơi, lẩm bẩm tự nói: "Lần này thật sự là may mắn nha, Rhine Harter! Ngươi bị ma pháp huyết tộc tà ác ô nhiễm, tuy không chết nhưng sức mạnh đã bị phá hủy gần hết rồi! May mà có hai Hồng Y Thánh Đường đang xử lý công việc ở châu Âu, cộng thêm lãnh đạo mới của Thần Sào do tổng bộ Thần Đình phái tới, ba vị Hồng Y Thánh Đường liên thủ, mới khiến ngươi phục hồi trong thời gian ngắn nhất mà." `sim=0.7605; han=0; modern=0; quote=True; digits=True`
- current: Các thần chức cấp cao có mặt tại đây đồng loạt gật đầu đáp lễ, dưới sự dẫn dắt của ba vị Hồng Y Thánh Đường, rảo bước đi ra ngoài. Cho đến khi những cao tầng này đi xa, Harl vẫn luôn đứng trong góc mới thở phào một hơi, lẩm bẩm tự nói: "Lần này thật là may mắn, Rhine Harter! Ngươi bị ma pháp huyết tộc tà ác ô nhiễm, tuy không chết, nhưng sức mạnh đã bị phá hủy gần hết rồi! May mà có hai Hồng Y Thánh Đường đang xử lý công việc ở châu Âu, cộng thêm lãnh đạo mới của Thần Sào do tổng bộ Thần Đình phái tới, ba vị Hồng Y Thánh Đường liên thủ, mới khiến ngươi phục hồi trong thời gian ngắn nhất." `sim=0.7781; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Các nhân viên cấp cao có mặt tại đó đồng loạt gật đầu đáp lễ, dưới sự dẫn dắt của ba vị Hồng Y Thánh Đường, bước nhanh ra ngoài. Mãi đến khi đám cao tầng này đi xa, Harl vẫn luôn đứng trong góc mới thở phào một hơi, lẩm bẩm tự nói: “Lần này thật là may mắn, Rhine Hart! Ngươi bị ma pháp huyết tộc tà ác làm ô nhiễm, tuy chưa chết nhưng sức mạnh đã bị phá hủy gần hết rồi! May mà có hai Hồng Y Thánh Đường đang xử lý công việc ở châu Âu, cộng thêm lãnh đạo mới của Thần Sào do tổng bộ Thần Đình phái tới, ba vị Hồng Y Thánh Đường liên thủ mới khiến ngươi phục hồi trong thời gian ngắn nhất.” `sim=0.7534; han=0; modern=0; quote=True; digits=True`

## 23. [reference_60] domain_terms

- ZH: “黑教廷？怎么可能……是，是这样的……哦，对，我其实不是在开学典礼那天觉醒的，我在更早的时候认识了一位老头，他跟我说，小伙子，我看你根骨奇佳、天资过人，不如和我学魔法吧，我当时就问，你谁啊大叔，他告诉我他是魔都魔法协会的成员，可以先帮我觉醒……总而言之，我其实不是5个月就学会的。”莫凡反应神速的解释道。
- Tham chiếu: “Hắc Giáo Đình? Sao có thể... Phải, chuyện là thế này... À đúng rồi, thật ra ta không thức tỉnh vào ngày khai giảng. Trước đó ta từng quen một lão nhân. Ông ấy nói: ‘Tiểu tử, ta thấy ngươi căn cốt tuyệt hảo, thiên tư hơn người, chi bằng theo ta học ma pháp.’ Khi ấy ta hỏi: ‘Đại thúc là ai?’ Ông ấy cho biết bản thân là thành viên Hiệp hội Ma pháp Ma Đô, có thể giúp ta thức tỉnh trước... Tóm lại, thật ra ta không chỉ học trong năm tháng.” Mạc Phàm phản ứng cực nhanh, lập tức giải thích.
- base: "Hắc Giáo Đình? Sao có thể... Phải, Là như vậy... Ồ, Đúng vậy, Thực ra ta không phải đang thức tỉnh vào ngày khai giảng, Ta quen biết một ông lão từ sớm hơn, Hắn nói với ta, Chàng trai trẻ, Ta thấy căn cốt của ngươi cực tốt Thiên tư hơn người, Chi bằng học ma pháp với ta đi, Ta liền hỏi, Ngươi là ai vậy đại thúc Hắn nói cho ta biết hắn là thành viên của Hiệp hội Ma pháp Ma Đô Có thể giúp ta thức tỉnh trước... Tóm lại, Thực ra ta không phải học được từ 5 tháng." Mạc Phàm phản ứng thần tốc giải thích. `sim=0.7165; han=0; modern=0; quote=True; digits=True`
- current: "Hắc Giáo Đình? Sao có thể... phải, Là như vậy... Ồ, Đúng vậy, Thực ra ta không phải thức tỉnh vào ngày khai giảng, Ta quen biết một ông lão từ sớm hơn, Hắn nói với ta, Chàng trai trẻ, Ta thấy căn cốt ngươi cực kỳ xuất sắc. Thiên tư hơn người, Chi bằng học ma pháp với ta đi, Ta lập tức hỏi, Ngươi là ai vậy đại thúc, Hắn nói với ta rằng hắn là thành viên Hiệp hội Ma pháp Ma Đô, Có thể giúp ta thức tỉnh trước... Tóm lại, "Ta thật ra không phải học được từ 5 tháng." Mạc Phàm phản ứng thần tốc giải thích. `sim=0.7018; han=0; modern=0; quote=False; digits=True`
- teacher_v2: “Hắc Giáo Đình? Sao có thể... phải, Là thế này... Ồ, Đúng vậy, Thực ra ta không phải thức tỉnh vào ngày lễ khai giảng, Ta quen một ông lão từ sớm hơn, Hắn nói với ta, Chàng trai trẻ, Ta thấy căn cốt của ngươi cực kỳ tốt, Thiên tư hơn người, Chi bằng học ma pháp với ta đi, Ta liền hỏi, Ngươi là ai vậy đại thúc, Hắn nói với ta là thành viên của Hiệp hội Ma pháp Ma Đô, Có thể giúp ta thức tỉnh trước... Tóm lại, Thực ra tôi không phải học được từ 5 tháng đâu.” Mạc Phàm phản ứng thần tốc giải thích. `sim=0.7150; han=0; modern=1; quote=True; digits=True`

## 24. [reference_60] domain_terms

- ZH: “在获得玩家资格、跟永恒大陆建立起联系后，没猜错的话兄弟你肯定便开始从网络上查找相关信息了吧，大多数新人在紧张、激动过后都会这么做，而只要有人查找类似信息，最终便会找到这类论坛，这不是偶然，而是一种因果的必然。”
- Tham chiếu: “Sau khi có tư cách người chơi và thiết lập liên hệ với đại lục Vĩnh Hằng, nếu ta đoán không sai, huynh đệ chắc chắn đã lên mạng tra cứu thông tin liên quan. Phần lớn người mới sau khi trải qua căng thẳng và kích động đều làm như vậy. Chỉ cần có người tìm những thông tin tương tự, cuối cùng họ sẽ đến được loại diễn đàn này. Đó không phải ngẫu nhiên, mà là kết quả tất yếu của nhân quả.”
- base: "Sau khi có được tư cách người chơi, thiết lập liên lạc với đại lục Vĩnh Hằng, nếu không đoán sai thì huynh đệ chắc chắn đã bắt đầu tìm kiếm thông tin liên quan từ trên mạng rồi, đại đa số người mới sau khi căng thẳng, kích động đều sẽ làm như vậy, mà chỉ cần có người tìm kiếm thông tin tương tự, cuối cùng sẽ tìm được loại diễn đàn này, đây không phải là ngẫu nhiên, mà là một sự tất yếu của nhân quả." `sim=0.7929; han=0; modern=0; quote=True; digits=True`
- current: “Sau khi có được tư cách người chơi, thiết lập liên lạc với đại lục Vĩnh Hằng, nếu không đoán sai thì huynh đệ chắc chắn đã bắt đầu tìm kiếm thông tin liên quan từ trên mạng rồi nhỉ, đa số người mới sau khi căng thẳng, kích động đều sẽ làm như vậy, mà chỉ cần có người tra cứu thông tin tương tự, cuối cùng sẽ tìm thấy diễn đàn loại này, đây không phải là ngẫu nhiên, mà là một loại tất yếu của nhân quả.” `sim=0.7625; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Sau khi có được tư cách người chơi, thiết lập liên lạc với Đại Lục Vĩnh Hằng, nếu không đoán sai thì huynh đệ chắc chắn đã bắt đầu tìm kiếm thông tin liên quan trên mạng rồi. Đa số người mới sau khi căng thẳng và kích động đều sẽ làm như vậy. Chỉ cần có người tìm kiếm thông tin tương tự, cuối cùng sẽ tìm được diễn đàn như thế này. Đây không phải là ngẫu nhiên, mà là một sự tất yếu của nhân quả.” `sim=0.8013; han=0; modern=0; quote=True; digits=True`

## 25. [reference_60] domain_terms

- ZH: “还好林师弟来了，实力在炼气二重，我们便能继续在此山修炼，上山之后我们四人相互照应，那畜生不敢对我们出手。”姜胜想了想继续道：“若是林师弟害怕妖兽，我们今日可以不去此山。”
- Tham chiếu: “May mà Lâm sư đệ đã tới, tu vi lại đạt Luyện Khí nhị trọng. Như vậy chúng ta có thể tiếp tục tu luyện trên ngọn núi này. Sau khi lên núi, bốn người cùng chăm nom lẫn nhau, con súc sinh kia sẽ không dám ra tay.” Khương Thắng nghĩ một lát rồi nói tiếp: “Nếu Lâm sư đệ sợ yêu thú, hôm nay chúng ta có thể không lên núi.”
- base: "May mà Lâm sư đệ đã đến, thực lực ở Luyện Khí nhị trọng, chúng ta có thể tiếp tục tu luyện ở ngọn núi này, sau khi lên núi bốn người chúng ta chiếu cố lẫn nhau, con súc sinh đó không dám ra tay với chúng ta." Khương Thắng suy nghĩ một chút rồi nói tiếp: "Nếu Lâm sư đệ sợ yêu thú, hôm nay chúng ta có thể không đến ngọn núi này." `sim=0.8104; han=0; modern=0; quote=True; digits=True`
- current: “May mà Lâm sư đệ đã đến, thực lực ở Luyện Khí nhị trọng, chúng ta có thể tiếp tục tu luyện ở ngọn núi này, sau khi lên núi bốn người chúng ta chiếu cố lẫn nhau, con súc sinh đó không dám ra tay với chúng ta.” Khương Thắng suy nghĩ một lát rồi nói tiếp: “Nếu Lâm sư đệ sợ yêu thú, hôm nay chúng ta có thể không đến ngọn núi này.” `sim=0.8360; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “May mà Lâm sư đệ đã đến, thực lực ở Luyện Khí nhị trọng, chúng ta có thể tiếp tục tu luyện ở ngọn núi này, sau khi lên núi bốn người chúng ta chiếu cố lẫn nhau, con súc sinh đó không dám ra tay với chúng ta.” Khương Thắng suy nghĩ một lát rồi nói tiếp: “Nếu Lâm sư đệ sợ yêu thú, hôm nay chúng ta có thể không đến ngọn núi này.” `sim=0.8360; han=0; modern=0; quote=True; digits=True`

## 26. [reference_60] domain_terms

- ZH: 林默却不放弃：“呵呵，我年长你1岁，今后就叫你小江吧！小江你也别把话说的那么死。像你这种平民领主，进入万族战场不就是为了赚钱么？有什么条件都可以谈！”
- Tham chiếu: Lâm Mặc vẫn không chịu bỏ cuộc: “Ha ha, ta lớn hơn ngươi một tuổi, sau này cứ gọi ngươi là Tiểu Giang vậy! Tiểu Giang, ngươi cũng đừng nói tuyệt đối như thế. Một lãnh chúa bình dân như ngươi tiến vào chiến trường Vạn Tộc chẳng phải để kiếm tiền sao? Điều kiện gì cũng có thể thương lượng!”
- base: Lâm Mặc lại không bỏ cuộc: "Ha ha, ta lớn hơn ngươi 1 tuổi, từ nay về sau cứ gọi ngươi là Tiểu Giang đi! Tiểu Giang ngươi cũng đừng nói lời chết tiệt như ngươi. Một lãnh chúa dân thường như ngươi, tiến vào chiến trường vạn tộc không phải là để kiếm tiền sao? Có điều kiện gì cũng có thể thương lượng!" `sim=0.8412; han=0; modern=0; quote=True; digits=True`
- current: Lâm Mặc lại không từ bỏ: "Ha ha, ta lớn hơn ngươi 1 tuổi, từ nay về sau cứ gọi ngươi là Tiểu Giang đi! Tiểu Giang ngươi cũng đừng nói lời chết tiệt như ngươi. Một lãnh chúa bình dân như ngươi, tiến vào chiến trường vạn tộc không phải là để kiếm tiền sao? Có điều kiện gì cũng có thể thương lượng!" `sim=0.8485; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Lâm Mặc lại không bỏ cuộc: “Ha ha, ta lớn hơn ngươi 1 tuổi, sau này cứ gọi ngươi là Tiểu Giang đi! Tiểu Giang ngươi cũng đừng nói lời chết như vậy. Một lãnh chúa bình dân như ngươi, tiến vào chiến trường vạn tộc không phải là để kiếm tiền sao? Có điều kiện gì cũng có thể thương lượng!” `sim=0.8943; han=0; modern=0; quote=True; digits=True`

## 27. [reference_60] domain_terms

- ZH: “领主大人。这是你现在手头最后的资产。我建议卖掉西边的度假村。那样咱们还能有一些盈余。不过哈里男爵跟赵顾男爵那边肯定会压低价格。”
- Tham chiếu: “Lãnh chúa đại nhân, đây là số tài sản cuối cùng chúng ta còn nắm giữ. Ta đề nghị bán khu nghỉ dưỡng phía tây, như vậy vẫn có thể dư ra một khoản. Có điều phía Nam tước Harry và Nam tước Triệu Cố chắc chắn sẽ nhân cơ hội ép giá.”
- base: "Thưa lãnh chúa. Đây là tài sản cuối cùng trong tay ngươi hiện tại. Ta đề nghị bán đi khu nghỉ dưỡng phía tây. Như vậy chúng ta còn có thể có chút dư dả. Nhưng Nam tước Harry và Nam tước Triệu Cố chắc chắn sẽ ép giá xuống." `sim=0.7123; han=0; modern=0; quote=True; digits=True`
- current: “Lãnh chúa đại nhân. Đây là tài sản cuối cùng trong tay ngươi hiện tại. Ta đề nghị bán đi làng nghỉ dưỡng phía tây. Như vậy chúng ta còn có thể có chút dư dả. Nhưng Nam tước Harry và Nam tước Triệu Cố chắc chắn sẽ ép giá.” `sim=0.7486; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Thưa Lãnh chúa. Đây là tài sản cuối cùng trong tay ngài bây giờ. Tôi đề nghị bán đi khu nghỉ dưỡng phía Tây. Như vậy chúng ta còn có chút dư dả. Nhưng Nam tước Harry và Nam tước Triệu Cố chắc chắn sẽ ép giá.” `sim=0.7294; han=0; modern=1; quote=True; digits=True`

## 28. [reference_60] domain_terms

- ZH: “看来还是找一道找寻灵药的任务吧！找寻灵药的时候，还可以猎杀妖兽，不仅可以制作血脉精华，还可以淬炼银月的战斗力！”
- Tham chiếu: “Xem ra vẫn nên nhận một nhiệm vụ tìm linh dược! Trong lúc tìm kiếm, ta còn có thể săn giết yêu thú, vừa chế tạo tinh hoa huyết mạch, vừa tôi luyện sức chiến đấu của Ngân Nguyệt!”
- base: "Xem ra vẫn là tìm một nhiệm vụ tìm linh dược đi! Lúc tìm linh dược, còn có thể săn giết yêu thú, không chỉ có thể chế tạo huyết mạch tinh hoa, còn có thể rèn luyện lực chiến đấu của Ngân Nguyệt!" `sim=0.7143; han=0; modern=0; quote=True; digits=True`
- current: "Xem ra vẫn nên tìm một nhiệm vụ tìm kiếm linh dược đi! Lúc tìm kiếm linh dược còn có thể săn giết yêu thú, không chỉ có thể chế tạo tinh hoa huyết mạch, mà còn có thể tôi luyện sức chiến đấu của Ngân Nguyệt!" `sim=0.7961; han=0; modern=1; quote=True; digits=True`
- teacher_v2: “Xem ra vẫn nên tìm một nhiệm vụ tìm kiếm linh dược đi! Lúc tìm kiếm linh dược còn có thể săn giết yêu thú, không chỉ có thể chế tạo tinh hoa huyết mạch, mà còn có thể tôi luyện sức chiến đấu của Ngân Nguyệt!” `sim=0.8092; han=0; modern=1; quote=True; digits=True`

## 29. [reference_60] domain_terms

- ZH: 本书为【游戏入侵现实】题材小说，主打【游戏数据流】（对此题材不了解读者可以自行搜索）。
- Tham chiếu: Truyện này thuộc đề tài 【Trò Chơi Xâm Nhập Hiện Thực】, chủ yếu đi theo hướng 【Dòng Dữ Liệu Trò Chơi】. Độc giả chưa biết về đề tài này có thể tự tìm hiểu.
- base: Cuốn sách này là tiểu thuyết đề tài [Xâm Nhập Hiện Thực], chủ yếu là [Dòng dữ liệu trò chơi] (không hiểu chủ đề này có thể tự mình tìm kiếm). `sim=0.6320; han=0; modern=1; quote=True; digits=True`
- current: Cuốn sách này là tiểu thuyết đề tài [Trò Xâm Nhập Hiện Thực], chủ yếu là [Lưu dữ liệu trò chơi] (không hiểu chủ đề này có thể tự mình tìm kiếm). `sim=0.6266; han=0; modern=1; quote=True; digits=True`
- teacher_v2: Cuốn sách này là tiểu thuyết đề tài [Trò Chơi Xâm Nhập Hiện Thực], chủ yếu là [Dòng dữ liệu trò chơi] (không hiểu chủ đề này, độc giả có thể tự mình tìm kiếm). `sim=0.6286; han=0; modern=1; quote=True; digits=True`

## 30. [reference_60] domain_terms

- ZH: “无聊？你还以为……”公羊白将合在身前的双手摊开，猛然往上一抬，“这是你的游戏吗！”
- Tham chiếu: “Nhàm chán? Ngươi vẫn còn tưởng...” Công Dương Bạch tách hai bàn tay đang chắp trước ngực, đột ngột nâng mạnh lên, “...đây là trò chơi của ngươi sao!”
- base: "Nhàm chán? Ngươi còn tưởng..." Công Dương Bạch dang hai tay đang chắp trước người ra, đột ngột nâng lên, "Đây là trò chơi của ngươi sao!" `sim=0.8462; han=0; modern=0; quote=True; digits=True`
- current: "Nhàm chán? Ngươi còn tưởng..." Công Dương Bạch Tướng dang rộng hai tay đang chắp trước người, đột ngột nâng lên, "Đây là trò chơi của ngươi sao!" `sim=0.8299; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Nhàm chán? Ngươi còn tưởng...” Công Dương Bạch dang hai tay đang chắp trước người ra, đột ngột nhấc lên, “Đây là trò chơi của ngươi sao!” `sim=0.8632; han=0; modern=0; quote=True; digits=True`

## 31. [reference_60] number_negation

- ZH: “好了，快到了，停下来慢慢走过去吧！”青年男子沉声道，还时不时的瞄向四周。很明显的是在境界，这些资深者可没有一个是省油的灯，不然也不能够在这个世界活下来了。虽说游戏地图开始的前几分钟里基本上见不到半只的恐龙，可这是在轮回世界，在这世界中一切皆有可能。青年男子可不希望到时候在这里建立起了一个基地，却忽然发现这里是一个恐龙窝，如果这种情况出现，那么就太糟糕了。他这也是无奈之举，刚才轮回世界给他的时间根本就不够让他仔细盘查，等计时开始之后再找建设基地的地方那就太浪费时间了，所以只能如此了。
- Tham chiếu: “Được rồi, sắp tới rồi. Dừng lại, từ từ đi bộ qua đó!” Thanh niên trầm giọng nói, thỉnh thoảng lại liếc nhìn bốn phía. Rõ ràng hắn đang cảnh giới. Những người chơi kỳ cựu này chẳng ai dễ đối phó; nếu không, họ đã chẳng thể sống sót trong thế giới này. Mấy phút đầu sau khi bản đồ trò chơi mở ra thường gần như không thấy bóng khủng long, nhưng đây là thế giới Luân Hồi, nơi mọi chuyện đều có thể xảy ra. Thanh niên không muốn dựng xong căn cứ rồi mới phát hiện chỗ này lại là ổ khủng long; nếu vậy thì quá tệ. Hắn cũng chỉ đành làm thế. Thời gian thế giới Luân Hồi vừa cho căn bản không đủ để kiểm tra kỹ khu vực, còn đợi bắt đầu tính giờ mới đi tìm nơi xây căn cứ thì quá lãng phí.
- base: "Được rồi, sắp tới rồi, dừng lại chậm rãi đi qua đi!" Thanh niên nam tử trầm giọng nói, còn thỉnh thoảng liếc nhìn bốn phía. Rõ ràng là ở cảnh giới, những kẻ thâm niên này không ai là kẻ dễ đối phó, nếu không cũng không thể sống sót trên thế giới này. Dù mấy phút đầu bản đồ trò chơi gần như không thấy nửa con khủng long nào, nhưng đây là thế giới luân hồi, mọi thứ trong thế giới này đều có thể xảy ra. Thanh niên nam tử cũng không hy vọng đến lúc đó xây dựng một căn cứ ở đây, lại đột nhiên phát hiện nơi này là một tổ khủng long, nếu như tình huống này xuất hiện, như vậy sẽ quá tồi tệ. Đây cũng là hành động bất đắc dĩ của hắn, thời gian Luân Hồi thế giới cho hắn lúc nãy căn bản không đủ để hắn kiểm tra kỹ lưỡng, đợi đến khi bắt đầu giờ mới tìm nơi xây dựng căn cứ thì quá lãng phí thời gian, nên chỉ có thể như vậy. `sim=0.6861; han=0; modern=0; quote=True; digits=True`
- current: "Được rồi, sắp đến rồi, dừng lại chậm rãi đi qua đi!" Thanh niên nam tử trầm giọng nói, còn thỉnh thoảng liếc nhìn bốn phía. Rõ ràng là ở cảnh giới, những kẻ thâm niên này không có ai là người dễ đối phó, nếu không cũng không thể sống sót ở thế giới này. Dù mấy phút đầu bản đồ trò chơi cơ bản không thấy nửa con khủng long nào, nhưng đây là thế giới luân hồi, trong thế giới này mọi thứ đều có thể xảy ra. Nam tử trẻ tuổi không hy vọng đến lúc đó xây dựng một căn cứ ở đây, lại đột nhiên phát hiện nơi này là một ổ khủng long, nếu tình huống này xuất hiện, vậy thì quá tệ rồi. Hắn cũng là hành động bất đắc dĩ, vừa rồi thế giới Luân Hồi cho hắn thời gian căn bản không đủ để hắn kiểm tra kỹ lưỡng, đợi khi thời gian bắt đầu rồi tìm nơi xây dựng căn cứ thì quá lãng phí thời gian, cho nên chỉ có thể như vậy. `sim=0.6568; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Được rồi, sắp đến rồi, dừng lại rồi từ từ đi!” Thanh niên nam tử trầm giọng nói, còn thỉnh thoảng liếc nhìn bốn phía. Rõ ràng là ở cảnh giới, những kẻ thâm niên này không có ai là người dễ đối phó, nếu không cũng không thể sống sót ở thế giới này. Dù mấy phút đầu bản đồ trò chơi gần như không thấy nửa con khủng long nào, nhưng đây là thế giới luân hồi, mọi thứ trong thế giới này đều có thể xảy ra. Thanh niên nam tử không muốn đến lúc đó xây dựng một căn cứ ở đây, lại đột nhiên phát hiện đây là một tổ khủng long, nếu tình huống này xảy ra thì thật quá tồi tệ. Đây cũng là hành động bất đắc dĩ của hắn. Thời gian mà thế giới Luân Hồi ban nãy cho hắn căn bản không đủ để hắn kiểm tra kỹ lưỡng. Đợi đến khi bắt đầu tính giờ mới tìm nơi xây dựng căn cứ thì quá lãng phí thời gian, nên chỉ có thể như vậy. `sim=0.7049; han=0; modern=0; quote=True; digits=True`

## 32. [reference_60] number_negation

- ZH: 迟疑了一下，莱茵哈特本来想要说自己其实已经从哈洛克斯和艾尔维克那里学习了很强大的技能，只是自己的神力并不足以发挥这些技能的力量罢了。可是一想到，梅林告诫过自己这些事情是绝对的机密，因此这些话终究没有出口。莱茵哈特只是朝着哈尔行礼后，恭敬的说道：“是的，哈尔导师，我明白……那么，在半年的奥义学习后，我申请试炼。相信到那个时候，我应该有资格走出神巢。”
- Tham chiếu: Reinhardt do dự một lát. Vốn hắn định nói bản thân đã học được những kỹ năng vô cùng mạnh mẽ từ Harlos và Elvic, chỉ là thần lực hiện tại chưa đủ để phát huy uy lực của chúng. Nhưng nhớ Merlin từng cảnh cáo rằng đây là cơ mật tuyệt đối, cuối cùng hắn vẫn không nói ra. Reinhardt chỉ hành lễ với Harl rồi cung kính thưa: “Vâng, đạo sư Harl, ta đã hiểu... Vậy sau nửa năm học áo nghĩa, ta xin được tham gia thí luyện. Tin rằng đến lúc ấy, ta sẽ đủ tư cách rời khỏi Thần Sào.”
- base: Do dự một chút, Rhine Hart vốn định nói rằng mình thực ra đã học được kỹ năng rất mạnh từ Harlos và Elvic, chỉ là thần lực của mình không đủ để phát huy sức mạnh của những kỹ năng này mà thôi. Nhưng vừa nghĩ đến việc Mai Lâm đã dặn dò mình những chuyện này là cơ mật tuyệt đối, nên những lời này rốt cuộc vẫn không thốt ra. Lai Ân Cáp Đặc chỉ hành lễ với Cáp Nhĩ, sau đó cung kính nói: "Đúng vậy, Cáp Nhĩ đạo sư, ta hiểu... Như vậy, sau nửa năm Áo Nghĩa học tập, ta xin thí luyện. Tin tưởng đến lúc đó, ta hẳn là có tư cách đi ra khỏi Thần Sào." `sim=0.6152; han=0; modern=3; quote=True; digits=True`
- current: Do dự một chút, Rhine Harter vốn định nói rằng mình thực ra đã học được kỹ năng rất mạnh từ Harlock và Alveyk, chỉ là thần lực của mình không đủ để phát huy sức mạnh của những kỹ năng này mà thôi. Nhưng vừa nghĩ đến, Mai Lâm đã cảnh cáo mình những chuyện này là bí mật tuyệt đối, vì vậy những lời này rốt cuộc vẫn không thốt ra. Lai Ân Ha Đặc chỉ hành lễ với Cáp Nhĩ rồi cung kính nói: "Đúng vậy, Cáp Nhĩ đạo sư, ta hiểu... Như vậy, sau nửa năm Áo Nghĩa học tập, ta xin thí luyện. Tin rằng đến lúc đó, ta hẳn là có tư cách đi ra khỏi Thần Sào." `sim=0.6253; han=0; modern=3; quote=True; digits=True`
- teacher_v2: Do dự một chút, Rhine Hart vốn định nói rằng mình thực ra đã học được kỹ năng rất mạnh từ Harlos và Elvic, chỉ là thần lực của mình không đủ để phát huy sức mạnh của những kỹ năng này mà thôi. Nhưng vừa nghĩ đến việc Mai Lâm đã dặn dò mình những chuyện này là cơ mật tuyệt đối, vì vậy những lời này rốt cuộc vẫn không thốt ra. Rhine Hart chỉ hành lễ với Harl rồi cung kính nói: “Đúng vậy, Harl đạo sư, ta hiểu... Vậy thì, sau nửa năm học tập Áo Nghĩa, ta xin thí luyện. Tin rằng đến lúc đó, ta có tư cách rời khỏi Thần Sào.” `sim=0.6753; han=0; modern=3; quote=True; digits=True`

## 33. [reference_60] number_negation

- ZH: “莫凡，哈哈哈，你的事情解决啦，我打电话给我一个老朋友，原来他现在可牛b了，是天澜高中的教导处主任，他说只要你好好修炼，他可以让你进天澜魔法高中，让你觉醒你命中的那一系魔法，这种机会可是一辈子才一次，这次你一定要努力，知道吗？”脸色蜡黄莫家兴满脸笑容的走了进来，手掌拍在莫凡的肩膀上。
- Tham chiếu: “Mạc Phàm, ha ha ha, chuyện của con giải quyết xong rồi! Cha đã gọi cho một người bằng hữu cũ. Không ngờ giờ ông ấy ghê gớm lắm, đã làm chủ nhiệm phòng giáo vụ của trường trung học Thiên Lan. Ông ấy nói chỉ cần con chăm chỉ tu luyện, ông ấy có thể cho con vào trường trung học Ma pháp Thiên Lan, để con thức tỉnh hệ ma pháp thuộc về số mệnh. Cơ hội thế này cả đời chỉ có một lần, lần này con nhất định phải cố gắng, biết chưa?” Mạc Gia Hưng với gương mặt vàng vọt tươi cười bước vào, đặt bàn tay lên vai Mạc Phàm.
- base: "Mạc Phàm, Ha ha ha, Chuyện của ngươi đã giải quyết xong rồi Ta gọi điện cho ta một người bạn cũ, Thì ra bây giờ hắn rất lợi hại, Chủ nhiệm phòng giáo dục của trường trung học Thiên Lan Hắn nói chỉ cần ngươi chăm chỉ tu luyện, Hắn có thể cho ngươi vào Thiên Lan ma pháp trung học Để ngươi thức tỉnh một hệ ma pháp trong mệnh của ngươi, Cơ hội này cả đời mới có một lần, Lần này ngươi nhất định phải cố gắng Sắc mặt vàng vọt Mạc Gia Hưng tươi cười đi vào, Bàn tay vỗ lên vai Mạc Phàm. `sim=0.7089; han=0; modern=1; quote=False; digits=True`
- current: "Mạc Phàm, Ha ha ha, Chuyện của ngươi giải quyết xong rồi, Ta gọi điện cho ta một người bạn cũ, Hóa ra bây giờ hắn lợi hại lắm, Chủ nhiệm phòng giáo vụ trường trung học Thiên Lan, Hắn nói chỉ cần ngươi chăm chỉ tu luyện, Hắn có thể cho ngươi vào trường trung học ma pháp Thiên Lan, 【Để ngươi thức tỉnh hệ ma pháp mà ngươi trúng đích,】 Cơ hội này cả đời mới có một lần, Lần này ngươi nhất định phải nỗ lực, "Biết chưa?" Mạc Gia Hưng mặt mày vàng vọt tươi cười bước vào, Bàn tay vỗ lên vai Mạc Phàm. `sim=0.7827; han=0; modern=1; quote=False; digits=True`
- teacher_v2: “Mạc Phàm, Ha ha ha, Chuyện của ngươi đã giải quyết rồi, Tôi gọi điện cho tôi một người bạn cũ, Thì ra bây giờ hắn quá đỉnh rồi, Chủ nhiệm phòng giáo vụ trường trung học Thiên Lan, Hắn nói chỉ cần ngươi chăm chỉ tu luyện, Hắn có thể cho ngươi vào trường trung học ma pháp Thiên Lan, Để ngươi thức tỉnh hệ ma pháp mà ngươi đã trúng, Cơ hội này cả đời mới có một lần, Lần này ngươi nhất định phải cố gắng, Có biết không?” Mạc Gia Hưng với vẻ mặt vàng vọt, mặt mày tươi cười bước vào, Bàn tay vỗ lên vai Mạc Phàm. `sim=0.7714; han=0; modern=3; quote=True; digits=True`

## 34. [reference_60] number_negation

- ZH: “进行救援这项工作，官方人员肯定是有得赚，但玩家们也非常乐意。毕竟，绝大多数玩家没得选择，倘若没有官方救援他们性命都保不住，而只要官方力量介入，玩家就可以摆脱生死危机且依旧保留着玩家资格，这完全不亏。”
- Tham chiếu: “Trong việc cứu viện, phía chính phủ chắc chắn thu được lợi ích, nhưng người chơi cũng vô cùng sẵn lòng hợp tác. Dù sao phần lớn người chơi không còn lựa chọn nào khác; không có cứu viện của chính phủ thì đến tính mạng cũng chẳng giữ nổi. Chỉ cần lực lượng chính phủ can thiệp, họ vừa thoát khỏi nguy cơ tử vong, vừa giữ được tư cách người chơi. Giao dịch này hoàn toàn không thiệt.”
- base: “Tiến hành công việc cứu viện này, nhân viên chính thức chắc chắn có lời, nhưng các người chơi cũng rất sẵn lòng. Dù sao, tuyệt đại đa số người chơi không có lựa chọn nào khác, nếu không có sự cứu viện chính thức thì tính mạng họ cũng không giữ được, mà chỉ cần lực lượng chính thức can thiệp, người chơi có thể thoát khỏi nguy cơ sinh tử và vẫn giữ được tư cách người chơi, điều này hoàn toàn không lỗ.” `sim=0.7255; han=0; modern=0; quote=True; digits=True`
- current: “Công việc cứu viện này, nhân viên chính thức chắc chắn có lời, nhưng người chơi cũng rất vui lòng. Suy cho cùng, tuyệt đại đa số người chơi không có lựa chọn nào khác, nếu không có sự cứu viện chính thức thì tính mạng họ cũng không giữ được, mà chỉ cần lực lượng chính thức can thiệp, người chơi có thể thoát khỏi nguy cơ sinh tử và vẫn giữ lại tư cách người chơi, điều này hoàn toàn không lỗ.” `sim=0.6948; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Công việc cứu viện này, nhân viên chính thức chắc chắn có lời, nhưng các người chơi cũng rất sẵn lòng. Dù sao, tuyệt đại đa số người chơi không còn lựa chọn nào khác, nếu không có sự cứu viện chính thức thì họ cũng không giữ được mạng, mà chỉ cần lực lượng chính thức can thiệp, người chơi có thể thoát khỏi nguy cơ sinh tử và vẫn giữ lại tư cách người chơi, điều này hoàn toàn không lỗ.” `sim=0.7103; han=0; modern=0; quote=True; digits=True`

## 35. [reference_60] number_negation

- ZH: 长生仙尊残魂苍老沙哑的声音响起，道：“想当年，本尊只是被测试出不入品的五行灵根，就轰动了整个远古修仙界，被各大顶级修仙圣地，抢得头破血流……。”
- Tham chiếu: Giọng già nua khàn khàn của tàn hồn Trường Sinh Tiên Tôn vang lên: “Nhớ năm xưa, bản tôn chỉ được kiểm tra ra Ngũ Hành Linh Căn không nhập phẩm mà đã làm chấn động toàn bộ giới tu tiên viễn cổ. Các thánh địa tu tiên đỉnh cấp tranh giành bản tôn đến sứt đầu mẻ trán...”
- base: Giọng nói già nua khàn khàn của tàn hồn Trường Sinh Tiên Tôn vang lên, nói: "Nhớ năm đó, bản tôn chỉ bị kiểm tra ra Ngũ Hành Linh Căn không nhập phẩm, đã oanh động toàn bộ tu tiên giới viễn cổ, bị các thánh địa tu tiên đỉnh cấp cướp đến sứt đầu mẻ trán..." `sim=0.8390; han=0; modern=0; quote=True; digits=True`
- current: Giọng nói già nua khàn đặc của tàn hồn Trường Sinh Tiên Tôn vang lên, nói: "Nhớ năm đó, bản tôn chỉ bị kiểm tra ra Ngũ Hành Linh Căn không nhập phẩm, đã chấn động toàn bộ Tu Tiên Giới Viễn Cổ, bị các thánh địa tu tiên đỉnh cấp tranh giành đến đầu rơi máu chảy..." `sim=0.8365; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Giọng nói già nua khàn đặc của tàn hồn Trường Sinh Tiên Tôn vang lên, nói: “Nhớ năm đó, bản tôn chỉ bị kiểm tra ra Ngũ Hành Linh Căn không nhập phẩm, đã làm chấn động toàn bộ giới tu tiên viễn cổ, bị các thánh địa tu tiên hàng đầu cướp đến sứt đầu mẻ trán...” `sim=0.8544; han=0; modern=0; quote=True; digits=True`

## 36. [reference_60] number_negation

- ZH: 涂山玥玥：“对呀对呀！江辰小哥哥不带兵种，不带图纸，甚至不带生活物资，几乎全部空间用来携带募民令来搏这亿分之一的机会。小妹万分佩服！”
- Tham chiếu: Đồ Sơn Nguyệt Nguyệt: “Đúng vậy, đúng vậy! Giang Thần tiểu ca ca không mang binh chủng, không mang bản vẽ, thậm chí không mang vật tư sinh hoạt, gần như dùng toàn bộ không gian để chứa Lệnh Chiêu Mộ Dân, đánh cược vào cơ hội một trên trăm triệu này. Tiểu muội vô cùng khâm phục!”
- base: Đồ Sơn Nguyệt Nguyệt: "Đúng vậy! Tiểu ca ca Giang Thần không mang binh chủng, không mang bản vẽ, thậm chí không mang theo vật tư sinh hoạt, hầu như toàn bộ không gian dùng để mang theo lệnh chiêu mộ dân chúng để đánh cược một phần trăm triệu này. Tiểu muội vô cùng khâm phục!" `sim=0.8281; han=0; modern=0; quote=True; digits=True`
- current: Đồ Sơn Nguyệt Nguyệt: "Đúng vậy! Giang Thần tiểu ca ca không mang binh chủng, không mang bản vẽ, thậm chí không mang theo vật tư sinh hoạt, gần như toàn bộ không gian dùng để mang theo lệnh chiêu mộ dân tộc để tranh thủ một phần trăm triệu cơ hội này. Tiểu muội vô cùng khâm phục!" `sim=0.8494; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Đồ Sơn Nguyệt Nguyệt: “Đúng vậy! Tiểu ca ca Giang Thần không mang binh chủng, không mang theo bản vẽ, thậm chí không mang theo vật tư sinh hoạt, gần như toàn bộ không gian dùng để mang theo lệnh chiêu mộ dân chúng để đánh cược một phần trăm triệu này. Tiểu muội vô cùng khâm phục!” `sim=0.8386; han=0; modern=0; quote=True; digits=True`

## 37. [reference_60] number_negation

- ZH: “叮，恭喜宿主完成新手任务，成功完成强盗行为，掠夺了对方的战舰。奖励t2重型攻击护卫舰一艘，双联电磁炮两门。获得积分100点。”
- Tham chiếu: “Đinh! Chúc mừng chủ nhân hoàn thành nhiệm vụ tân thủ: thực hiện thành công hành vi cướp bóc và đoạt chiến hạm của đối phương. Phần thưởng: một tàu hộ vệ tấn công hạng nặng T2, hai khẩu pháo điện từ nòng đôi. Nhận một trăm điểm tích lũy.”
- base: "Đinh, chúc mừng ký chủ hoàn thành nhiệm vụ tân thủ, hoàn thành thành công hành vi cướp bóc, cướp đoạt chiến hạm của đối phương. Phần thưởng một chiếc tàu hộ vệ tấn công hạng nặng T2, hai khẩu pháo điện từ song liên. Nhận được 100 điểm tích lũy." `sim=0.8416; han=0; modern=0; quote=True; digits=True`
- current: “Đinh, chúc mừng ký chủ hoàn thành nhiệm vụ tân thủ, hoàn thành thành công hành vi cướp bóc, cướp đoạt chiến hạm của đối phương. Phần thưởng một chiếc tàu hộ vệ tấn công hạng nặng T2, hai khẩu pháo điện từ song liên. Nhận được 100 điểm tích lũy.” `sim=0.8519; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Đinh, chúc mừng ký chủ hoàn thành nhiệm vụ tân thủ, hoàn thành thành công hành vi cướp bóc, cướp đoạt chiến hạm của đối phương. Phần thưởng một chiếc tàu hộ vệ tấn công hạng nặng T2, hai khẩu pháo điện từ song liên. Nhận được 100 điểm tích lũy.” `sim=0.8519; han=0; modern=0; quote=True; digits=True`

## 38. [reference_60] number_negation

- ZH: “这是一个可以容纳十只妖兽的御兽袋，如果以后碰到血脉珍稀的妖兽，记得给我逮回来，家族不会亏待你的！”
- Tham chiếu: “Đây là Túi Ngự Thú có thể chứa mười con yêu thú. Sau này nếu gặp yêu thú mang huyết mạch quý hiếm, nhớ bắt về cho ta. Gia tộc sẽ không bạc đãi ngươi!”
- base: "Đây là một cái Ngự Thú Đại có thể chứa mười con yêu thú, nếu sau này gặp phải yêu thú có huyết mạch trân quý, nhớ bắt về cho ta, gia tộc sẽ không bạc đãi ngươi đâu!" `sim=0.8245; han=0; modern=0; quote=True; digits=True`
- current: "Đây là một cái Ngự Thú Đại có thể chứa mười con yêu thú, nếu sau này gặp phải yêu thú có huyết mạch trân quý, nhớ bắt về cho ta, gia tộc sẽ không bạc đãi ngươi đâu!" `sim=0.8245; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Đây là một cái túi Ngự Thú có thể chứa mười con yêu thú, nếu sau này gặp phải yêu thú có huyết mạch quý hiếm, nhớ bắt về cho ta, gia tộc sẽ không bạc đãi ngươi đâu!” `sim=0.8816; han=0; modern=0; quote=True; digits=True`

## 39. [reference_60] number_negation

- ZH: “但是呢，就因为那个婊子，就因为这该死的末日游戏，害得老子没能及时将信息发出去。”
- Tham chiếu: “Nhưng chỉ vì con tiện nhân đó, chỉ vì trò chơi tận thế chết tiệt này mà lão tử không thể kịp thời truyền tin ra ngoài.”
- base: “Nhưng mà, chỉ vì con đĩ đó, chỉ vì tên Mạt Nhật Du hí đáng chết này, khiến lão tử không kịp thời gửi tin nhắn đi.” `sim=0.6230; han=0; modern=0; quote=True; digits=True`
- current: “Nhưng mà, chỉ vì con đĩ đó, chỉ vì cái tên Mạt Nhật Du hí chết tiệt này, khiến lão tử không kịp thời gửi tin nhắn đi.” `sim=0.6774; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Nhưng mà, chỉ vì con đĩ đó, chỉ vì cái tên Mạt Nhật Du hí chết tiệt này, khiến lão tử không kịp gửi tin nhắn đi.” `sim=0.6593; han=0; modern=0; quote=True; digits=True`

## 40. [reference_60] number_negation

- ZH: 罗森原本力量属性是0.62，加上“强壮”技能增加的0.5，他的力量几乎翻倍。
- Tham chiếu: Thuộc tính sức mạnh ban đầu của Rosen là 0,62. Cộng thêm 0,5 do kỹ năng “Cường Tráng” gia tăng, sức mạnh của hắn gần như tăng gấp đôi.
- base: La Sâm nguyên bản thuộc tính sức mạnh là 0.62, cộng thêm 0.5 do kỹ năng "Cường tráng" tăng lên, sức mạnh của hắn gần như tăng gấp đôi. `sim=0.7925; han=0; modern=0; quote=True; digits=True`
- current: La Sâm vốn có thuộc tính sức mạnh là 0.62, cộng thêm kỹ năng "Cường Tráng" tăng 0.5, sức mạnh của hắn gần như tăng gấp đôi. `sim=0.7882; han=0; modern=0; quote=True; digits=True`
- teacher_v2: La Sâm thuộc tính sức mạnh ban đầu là 0.62, cộng thêm 0.5 do kỹ năng "Cường tráng" tăng lên, sức mạnh của hắn gần như tăng gấp đôi. `sim=0.8612; han=0; modern=0; quote=True; digits=True`

## 41. [reference_60] quote_author

- ZH: 席然走到了枪店的边上，看了一下枪店中的武器，直接购买了一把手枪花去了20个单位黄金10个单位的木材，再花费了25黄金跟木材购买了35发手枪子弹。看到这情况，席席然也是郁闷了，对这地图的作者真心无语，这年头子弹都差不多要比枪贵了。不过35发子弹，若是顺利的话大型恐龙都能够杀掉两只，小型恐龙一般不超过三枪，毕竟这个世界中，手枪的威力还是蛮大的。护甲再高，也禁不住一颗子弹固定75点的伤害呀，看到了手枪的属xing与游戏中一样，席然心中稍稍欣慰了些。
- Tham chiếu: Tịch Nhiên đến bên tiệm súng xem qua các loại vũ khí, rồi mua thẳng một khẩu súng lục với giá hai mươi đơn vị vàng và mười đơn vị gỗ. Sau đó hắn tiêu thêm hai mươi lăm vàng cùng một lượng gỗ để mua ba mươi lăm viên đạn. Thấy giá cả như vậy, Tịch Nhiên vô cùng buồn bực, thật sự cạn lời với tác giả bản đồ; thời buổi này đạn gần như còn đắt hơn cả súng. Tuy nhiên, nếu mọi việc thuận lợi, ba mươi lăm viên đạn đủ giết hai con khủng long cỡ lớn, còn khủng long cỡ nhỏ thường chẳng chịu nổi ba phát. Dù sao trong thế giới này, uy lực súng lục vẫn khá lớn. Hộ giáp cao đến đâu cũng khó chịu nổi bảy mươi lăm điểm sát thương cố định của mỗi viên đạn. Thấy thuộc tính súng lục vẫn giống trong trò chơi, hắn mới cảm thấy an tâm đôi chút.
- base: Tịch Nhiên đi đến bên cạnh tiệm súng, xem qua vũ khí trong tiệm súng, trực tiếp mua một khẩu súng ngắn tiêu tốn 20 đơn vị vàng 10 đơn vị, lại tốn 25 vàng và gỗ để mua 35 viên đạn súng lục. Nhìn thấy tình huống này, Tịch Tịch Nhiên cũng buồn bực, đối với tác giả bản đồ này thật sự cạn lời, thời buổi này đạn dược cũng gần như đắt hơn súng. Tuy nhiên 35 viên đạn, nếu thuận lợi thì khủng long cỡ lớn cũng có thể giết chết hai con, khủng long cỡ nhỏ thường không quá ba phát, dù sao trong thế giới này, uy lực của súng lục vẫn khá lớn. Dù giáp có cao đến đâu, cũng không chịu nổi sát thương do một viên đạn cố định 75 điểm, thấy thuộc tính của súng lục giống như trong game, Tịch Nhiên trong lòng hơi an ủi đôi chút. `sim=0.6399; han=0; modern=0; quote=True; digits=True`
- current: Tịch Nhiên đi đến bên cạnh cửa hàng súng, xem qua vũ khí trong tiệm súng, trực tiếp mua một khẩu súng lục tiêu tốn 20 đơn vị vàng 10 đơn vị gỗ, lại tốn thêm 25 vàng và gỗ để mua 35 viên đạn súng lục. Nhìn thấy tình huống này, Tịch Tịch Nhiên cũng buồn bực, đối với tác giả bản đồ này thật sự cạn lời, thời buổi này đạn dược gần như đắt hơn súng. Tuy nhiên 35 viên đạn, nếu thuận lợi thì khủng long cỡ lớn cũng có thể giết chết hai viên, khủng long cỡ nhỏ thường không quá ba phát, dù sao trong thế giới này, uy lực của súng lục vẫn khá lớn. Dù giáp có cao đến đâu, cũng không chịu nổi một viên đạn cố định 75 điểm sát thương, nhìn thấy thuộc tính súng lục giống như trong game, Tịch Nhiên trong lòng hơi an ủi một chút. `sim=0.6306; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Tịch Nhiên đi đến bên cạnh tiệm súng, xem qua vũ khí trong tiệm súng, rồi trực tiếp mua một khẩu súng ngắn tiêu tốn 20 đơn vị vàng 10 đơn vị, sau đó tốn 25 vàng và gỗ để mua 35 viên đạn súng lục. Thấy tình hình này, Tịch Tịch Nhiên cũng thấy buồn bực, thật sự không nói nên lời với tác giả bản đồ này, thời buổi này đạn dược cũng gần như đắt hơn súng. Nhưng 35 viên đạn, nếu thuận lợi thì khủng long cỡ lớn cũng có thể giết được hai viên, khủng long cỡ nhỏ thường không quá ba phát, dù sao trong thế giới này, uy lực của súng lục vẫn khá lớn. Dù giáp có cao đến đâu, cũng không chịu nổi sát thương do một viên đạn cố định 75 điểm, thấy thuộc tính của súng lục cũng giống như trong game, Tịch Nhiên trong lòng hơi an ủi đôi chút. `sim=0.6567; han=0; modern=0; quote=True; digits=True`

## 42. [reference_60] quote_author

- ZH: 今天晚上的章节更新要晚一些，因为周日了，点击榜与推荐榜凌晨换榜，要更新的章节推迟到晚间十二点。如果那时还有在线的兄弟姐妹，请过来帮忙，登陆下帐号，点击、投票支持下完美世界，这对冲榜的新书来说太重要了，也请收藏下本书。感谢所有兄弟姐妹！
- Tham chiếu: Chương tối nay sẽ cập nhật muộn một chút. Vì hôm nay là Chủ nhật, bảng lượt đọc và bảng đề cử sẽ đổi thứ hạng vào lúc nửa đêm, nên chương mới được lùi đến mười hai giờ tối. Nếu lúc ấy vẫn còn huynh đệ tỷ muội nào trực tuyến, xin hãy ghé qua giúp đỡ: đăng nhập tài khoản, nhấn đọc và bỏ phiếu ủng hộ 《Thế Giới Hoàn Mỹ》. Điều này vô cùng quan trọng đối với một truyện mới đang tranh bảng, cũng mong mọi người lưu truyện. Cảm ơn tất cả huynh đệ tỷ muội!
- base: Chương tối nay cập nhật muộn hơn một chút, vì Chủ nhật đã nhấn vào bảng đề cử và đổi bảng đề cử vào lúc rạng sáng, chương cập nhật sẽ bị hoãn đến mười hai giờ tối. Nếu lúc đó còn có anh chị em trực tuyến, xin mời qua giúp đỡ, đăng nhập tài khoản, nhấn vào, bỏ phiếu hỗ trợ thế giới hoàn mỹ, điều này đối với cuốn sách mới lọt vào bảng xếp hạng mà nói thì quá quan trọng, cũng xin hãy lưu lại cuốn sách này. Cảm ơn tất cả anh chị em! `sim=0.6208; han=0; modern=0; quote=True; digits=True`
- current: Chương tối nay cập nhật muộn hơn một chút, vì Chủ nhật đã nhấn vào bảng đề cử và đổi bảng đề cử vào lúc rạng sáng, chương cập nhật sẽ bị hoãn đến mười hai giờ tối. Nếu lúc đó còn có anh chị em trực tuyến, mời đến giúp đỡ, đăng nhập vào tài khoản, nhấn vào, bỏ phiếu ủng hộ thế giới hoàn mỹ, điều này đối với sách mới vượt bảng mà nói thì quá quan trọng, cũng xin hãy lưu lại cuốn sách này. Cảm ơn tất cả huynh đệ tỷ muội! `sim=0.6578; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Chương tối nay cập nhật muộn hơn một chút, vì Chủ nhật đã nhấn vào bảng đề cử và đổi bảng đề cử vào lúc rạng sáng, chương cập nhật sẽ bị hoãn đến mười hai giờ tối. Nếu lúc đó còn có anh chị em đang online, mời đến giúp, đăng nhập tài khoản, nhấn vào, bỏ phiếu hỗ trợ thế giới hoàn mỹ, điều này quá quan trọng đối với cuốn sách mới lọt bảng xếp hạng, cũng xin hãy cất giữ cuốn sách này. Cảm ơn tất cả anh chị em! `sim=0.6257; han=0; modern=0; quote=True; digits=True`

## 43. [reference_60] quote_author

- ZH: “嗨，头儿，这里就是我们特别调查局最机密的电子监控中心。三十台巨型母机级服务器，监控了除了中国大陆本土外几乎世界上所有的电子信息……看，这就是我们特别调查局在情报系统内部都受人排挤的最大原因，没有人愿意自己的隐私一天到晚被我们盯着的。尤其，上次我们军情系统的头儿，他给情妇打的电话不小心被我们偷听到后，我们的经费都缩水了百分之三十！”
- Tham chiếu: “Này, sếp, đây là trung tâm giám sát điện tử tuyệt mật của Cục Điều tra Đặc biệt chúng ta. Ba mươi siêu máy chủ cấp máy mẹ giám sát gần như mọi thông tin điện tử trên toàn thế giới, ngoại trừ nội địa Trung Quốc... Thấy chưa, đây chính là nguyên nhân lớn nhất khiến Cục Điều tra Đặc biệt bị cả hệ thống tình báo xa lánh. Chẳng ai muốn đời tư của họ bị chúng ta theo dõi suốt ngày đêm. Nhất là lần trước, chúng ta vô tình nghe lén được cuộc gọi của người đứng đầu hệ thống quân tình với tình nhân; sau vụ đó, kinh phí của chúng ta bị cắt hẳn ba mươi phần trăm!”
- base: “Hi, Đầu lĩnh, Đây chính là trung tâm giám sát điện tử cơ mật nhất của Cục Điều tra Đặc biệt chúng ta. Ba mươi chiếc máy chủ cấp máy chủ khổng lồ, Giám sát toàn bộ thông tin điện tử gần như trên thế giới ngoại trừ đại lục Trung Quốc... Nhìn kìa, Đây chính là nguyên nhân lớn nhất khiến Cục Điều tra Đặc biệt chúng ta bị người ta chèn ép trong nội bộ hệ thống tình báo, Không ai muốn sự riêng tư của mình bị chúng ta theo dõi suốt ngày suốt đêm. Đặc biệt là, Lần trước chúng ta đứng đầu hệ thống quân tình, Hắn gọi điện cho tình nhân vô tình bị chúng ta nghe lén, Kinh phí của chúng ta đã bị rút mất ba mươi phần trăm rồi!" `sim=0.7210; han=0; modern=1; quote=False; digits=True`
- current: "Này, Đầu lĩnh, Đây chính là trung tâm giám sát điện tử cơ mật nhất của Cục Điều tra Đặc biệt chúng ta. Ba mươi chiếc máy chủ cấp cơ giáp mẹ khổng lồ, Giám sát toàn bộ thông tin điện tử trên thế giới gần như toàn bộ đại lục Trung Quốc... Xem kìa, Đây chính là nguyên nhân lớn nhất khiến Cục Điều tra Đặc biệt chúng ta bị người ta chèn ép trong hệ thống tình báo, Không ai muốn sự riêng tư của mình suốt ngày bị chúng ta theo dõi suốt ngày. Đặc biệt, Lần trước chúng ta đứng đầu hệ thống quân sự, Hắn gọi điện cho tình nhân vô tình bị chúng ta nghe lén, "Kinh phí của chúng ta đều bị thu hẹp ba mươi phần trăm!" `sim=0.7039; han=0; modern=1; quote=False; digits=True`
- teacher_v2: “Hi, Đầu lĩnh, Đây chính là trung tâm giám sát điện tử cơ mật nhất của Cục Điều tra Đặc biệt chúng ta. Ba mươi chiếc máy chủ cấp máy chủ khổng lồ, Giám sát toàn bộ thông tin điện tử gần như trên thế giới bên ngoài lục địa Trung Quốc... Xem kìa, Đây chính là lý do lớn nhất khiến Cục Điều tra Đặc biệt chúng ta bị người khác chèn ép trong nội bộ hệ thống tình báo, Không ai muốn sự riêng tư của mình bị chúng ta theo dõi suốt ngày suốt đêm. Đặc biệt là, Lần trước đứng đầu hệ thống quân tình của chúng ta, Sau khi hắn gọi điện cho tình nhân vô tình bị chúng ta nghe lén, Kinh phí của chúng ta đã bị rút mất ba mươi phần trăm rồi!” `sim=0.6768; han=0; modern=1; quote=True; digits=True`

## 44. [reference_60] quote_author

- ZH: “好，大家打开妖魔之书，今天我将继续给大家讲述比较常见的妖魔。众所周知，妖魔分布在我们人类栖息的城市之外，对人类拥有绝对的攻击性，它们四处游荡，相互厮杀……那么一旦有魔法师要踏入野外，遇到一只独眼魔狼时该怎么做呢？”张建国已经开始眉飞色舞的讲述着课程。
- Tham chiếu: “Được rồi, mọi người mở 《Sách Yêu Ma》 ra. Hôm nay ta sẽ tiếp tục giảng về một số yêu ma thường gặp. Như mọi người đều biết, yêu ma phân bố bên ngoài các thành phố nơi nhân loại cư trú và có tính công kích cực mạnh với con người. Chúng lang thang khắp nơi, chém giết lẫn nhau... Vậy khi một ma pháp sư bước vào vùng hoang dã và gặp phải Độc Nhãn Ma Lang, người ấy nên làm gì?” Trương Kiến Quốc đã bắt đầu say sưa giảng bài.
- base: "Được, mọi người mở cuốn sách yêu ma ra, hôm nay ta sẽ tiếp tục kể cho mọi người nghe những yêu ma khá phổ biến. Ai cũng biết, yêu ma phân bố bên ngoài thành phố nơi con người chúng ta cư ngụ, có tính công kích tuyệt đối đối đối với con người, chúng lang thang khắp nơi, chém giết lẫn nhau... Vậy thì một khi có ma pháp sư muốn bước vào dã ngoại, gặp phải một con ma lang độc nhãn thì phải làm thế nào?" Trương Kiến Quốc đã bắt đầu hớn hở kể lại các khóa học. `sim=0.6560; han=0; modern=0; quote=True; digits=True`
- current: "Được, mọi người mở sách yêu ma ra, hôm nay ta sẽ tiếp tục kể cho mọi người nghe những yêu ma khá phổ biến. Ai cũng biết, yêu ma phân bố bên ngoài thành phố nơi loài người chúng ta cư ngụ, có tính công kích tuyệt đối đối đối với con người, chúng lang thang khắp nơi, chém giết lẫn nhau... Vậy thì một khi có ma pháp sư muốn bước chân vào hoang dã, gặp phải một con ma lang độc nhãn thì phải làm thế nào?" Trương Kiến Quốc đã bắt đầu hớn hở kể lại các khóa học. `sim=0.6667; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Được, mọi người mở cuốn sách yêu ma ra, hôm nay ta sẽ tiếp tục kể cho mọi người nghe những yêu ma tương đối phổ biến. Ai cũng biết, yêu ma phân bố bên ngoài thành phố nơi con người chúng ta cư ngụ, có tính công kích tuyệt đối đối với con người, chúng lang thang khắp nơi, chém giết lẫn nhau... Vậy một khi có ma pháp sư muốn bước vào hoang dã, gặp phải một con ma lang độc nhãn thì phải làm thế nào?” Trương Kiến Quốc đã bắt đầu hớn hở kể lại các khóa học. `sim=0.6745; han=0; modern=0; quote=True; digits=True`

## 45. [reference_60] quote_author

- ZH: “咳咳，你不用担心情报问题，现在这个论坛只是个引导性论坛，资料不多还鱼龙混杂，对于真正的游戏玩家我们玄国也搭建了一个交流平台——太玄论坛，待会我将邀请码发给你，绝大多数情报都能在太玄论坛内找到。”
- Tham chiếu: “Khụ khụ, ngươi không cần lo về tình báo. Diễn đàn hiện tại chỉ dùng để dẫn đường, tư liệu vừa ít vừa thật giả lẫn lộn. Với những người chơi thực sự, Huyền Quốc đã dựng một nền tảng trao đổi riêng — diễn đàn Thái Huyền. Lát nữa ta sẽ gửi mã mời cho ngươi. Phần lớn tình báo đều có thể tìm thấy trong đó.”
- base: “Khụ khụ, ngươi không cần lo lắng về vấn đề tình báo, hiện tại diễn đàn này chỉ là một diễn đàn dẫn dắt, tư liệu không nhiều mà còn tạp nham lẫn lộn, đối với người chơi game thực sự Huyền Quốc chúng ta cũng dựng một nền tảng giao lưu - diễn đàn Thái Huyền, lát nữa ta sẽ gửi mã mời cho ngươi, tuyệt đại đa số tình báo đều có thể tìm thấy trong diễn đàn Thái Huyền.” `sim=0.6833; han=0; modern=0; quote=True; digits=True`
- current: “Khụ khụ, ngươi không cần lo lắng về vấn đề tình báo, hiện tại diễn đàn này chỉ là một diễn đàn dẫn dắt, tư liệu không nhiều mà còn tạp nham lẫn lộn, đối với người chơi game thật sự Huyền Quốc chúng ta cũng dựng một nền tảng giao lưu — diễn đàn Thái Huyền, lát nữa ta sẽ gửi mã mời cho ngươi, tuyệt đại đa số tình báo đều có thể tìm thấy trong diễn đàn Thái Huyền.” `sim=0.6795; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Khụ khụ, ngươi không cần lo lắng về vấn đề tình báo, hiện tại diễn đàn này chỉ là một diễn đàn dẫn dắt, tư liệu không nhiều mà còn tạp nham lẫn lộn, đối với người chơi game thực thụ, Huyền Quốc chúng ta cũng dựng một nền tảng giao lưu - diễn đàn Thái Huyền, lát nữa ta sẽ gửi mã mời cho ngươi, đại đa số tình báo đều có thể tìm thấy trong diễn đàn Thái Huyền.” `sim=0.6834; han=0; modern=0; quote=True; digits=True`

## 46. [reference_60] quote_author

- ZH: 还未等林浩说完，赤云子就连连大喊，气得拳头都握了起来：“此灵果一定是火属性的至宝，竟然被一个资质只是五行灵根的人吃了，唉……暴殄天物……。”
- Tham chiếu: Lâm Hạo còn chưa nói xong, Xích Vân Tử đã liên tục kêu lớn, tức đến siết chặt nắm tay: “Linh quả này nhất định là chí bảo thuộc tính Hỏa, vậy mà lại bị một kẻ chỉ có tư chất Ngũ Hành Linh Căn ăn mất. Ôi... đúng là phung phí của trời...”
- base: Còn chưa đợi Lâm Hạo nói xong, Xích Vân Tử đã hét lớn, tức giận đến mức nắm chặt nắm đấm: "Linh quả này nhất định là chí bảo thuộc tính hỏa, vậy mà lại bị một người tư chất chỉ là ngũ hành linh căn ăn mất, ai... thật là phí phạm của trời..." `sim=0.7676; han=0; modern=0; quote=True; digits=True`
- current: Còn chưa đợi Lâm Hạo nói xong, Xích Vân Tử đã liên tục hét lớn, tức giận đến mức nắm chặt nắm đấm: "Linh quả này nhất định là chí bảo thuộc tính Hỏa, vậy mà lại bị một người tư chất chỉ là Ngũ Hành linh căn ăn mất, ai... phí phạm của trời..." `sim=0.7817; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Còn chưa đợi Lâm Hạo nói xong, Xích Vân Tử đã hét lớn liên tiếp, tức đến mức nắm chặt tay lại: “Linh quả này nhất định là chí bảo thuộc tính Hỏa, vậy mà lại bị một người có tư chất chỉ là Ngũ Hành Linh Căn ăn mất, ai... phí của trời...” `sim=0.7869; han=0; modern=0; quote=True; digits=True`

## 47. [reference_60] quote_author

- ZH: “领主大人，本来家里就有不少工作需要人处理。我建议留下一部分。至于那些愿意去做皮肉生意的。可以直接送去我们在红海城的会所。”
- Tham chiếu: “Lãnh chúa đại nhân, trong nhà vốn có không ít công việc cần người xử lý, ta đề nghị giữ lại một phần. Còn những kẻ tự nguyện làm nghề bán thân, có thể đưa thẳng đến hội quán của chúng ta tại thành Hồng Hải.”
- base: “Lãnh chúa đại nhân, vốn dĩ trong nhà đã có không ít công việc cần người xử lý. Ta đề nghị để lại một phần. Còn những người nguyện ý đi làm ăn buôn bán da thịt, có thể trực tiếp đưa đến hội sở của chúng ta ở Hồng Hải thành.” `sim=0.7738; han=0; modern=0; quote=True; digits=True`
- current: “Lãnh chúa đại nhân, vốn dĩ trong nhà đã có không ít công việc cần người xử lý. Ta đề nghị để lại một phần. Còn những kẻ nguyện ý làm ăn buôn bán da thịt, có thể trực tiếp đưa đến hội sở của chúng ta ở thành Hồng Hải.” `sim=0.8278; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Lãnh chúa đại nhân, vốn dĩ trong nhà đã có không ít công việc cần người xử lý. Ta đề nghị để lại một phần. Còn những người nguyện ý đi làm ăn buôn bán da thịt, có thể trực tiếp gửi đến hội sở của chúng ta ở thành Hồng Hải.” `sim=0.7976; han=0; modern=0; quote=True; digits=True`

## 48. [reference_60] quote_author

- ZH: “远的不说。千年前，朱元璋前辈凭借白板领主之心，F级天赋【乞讨】，都能逆伐神圣，成为蓝星最大的域主之一——明域之主！”
- Tham chiếu: “Không nói chuyện quá xa. Một ngàn năm trước, tiền bối Chu Nguyên Chương chỉ dựa vào Lãnh Chủ Chi Tâm cấp trắng và thiên phú cấp F 【Ăn Xin】 mà vẫn có thể nghịch phạt cấp Thần Thánh, trở thành một trong những vực chủ lớn nhất Lam Tinh — Minh Vực Chi Chủ!”
- base: "Không nói xa. Ngàn năm trước, tiền bối Chu Nguyên Chương dựa vào tấm lòng Bạch Bản Lĩnh Chủ, thiên phú cấp F [Khất Thảo], đều có thể nghịch phạt thần thánh, trở thành một trong những vực chủ lớn nhất Lam Tinh - Minh Vực Chi Chủ!" `sim=0.7833; han=0; modern=0; quote=True; digits=True`
- current: “Không nói xa. Ngàn năm trước, tiền bối Chu Nguyên Chương dựa vào tấm lòng lãnh chúa trắng, thiên phú cấp F [Khất Thảo], đều có thể nghịch phạt thần thánh, trở thành một trong những vực chủ lớn nhất Lam Tinh — Minh Vực Chi Chủ!” `sim=0.8272; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Không nói xa. Ngàn năm trước, tiền bối Chu Nguyên Chương dựa vào tấm lòng Bạch Bản Lĩnh Chủ, thiên phú cấp F [Khất Thảo], đều có thể nghịch phạt Thần Thánh, trở thành một trong những vực chủ lớn nhất Lam Tinh - Minh Vực Chi Chủ!” `sim=0.7937; han=0; modern=0; quote=True; digits=True`

## 49. [reference_60] quote_author

- ZH: 守卫面色微微一变，“少爷，您的战兽才是青石三阶的实力，想要挑战青石五阶的妖兽，会不会有什么风险？”
- Tham chiếu: Sắc mặt thủ vệ khẽ thay đổi: “Thiếu gia, chiến thú của ngài mới có thực lực Thanh Thạch tam giai. Khiêu chiến yêu thú Thanh Thạch ngũ giai e rằng quá nguy hiểm?”
- base: Thủ vệ sắc mặt hơi thay đổi, "Thiếu gia, chiến thú của ngài mới có thực lực Thanh Thạch tam giai, muốn khiêu chiến yêu thú Thanh Thạch ngũ giai, liệu có rủi ro gì không?" `sim=0.7909; han=0; modern=0; quote=True; digits=True`
- current: Thủ vệ sắc mặt khẽ biến, "Thiếu gia, chiến thú của ngài mới có thực lực Thanh Thạch tam giai, muốn khiêu chiến yêu thú Thanh Thạch ngũ giai, liệu có rủi ro gì không?" `sim=0.7692; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Sắc mặt thủ vệ hơi thay đổi, “Thiếu gia, chiến thú của ngài mới là thực lực cấp ba Thanh Thạch, muốn khiêu chiến yêu thú cấp năm Thanh Thạch, liệu có rủi ro gì không?” `sim=0.7308; han=0; modern=0; quote=True; digits=True`

## 50. [reference_60] quote_author

- ZH: “叮，绝对爆率：将玩家游戏过程中所有斩杀的丧尸物品爆率由1%提高至100%。”
- Tham chiếu: “Đinh! Tỷ lệ rơi tuyệt đối: tăng tỷ lệ rơi vật phẩm của tất cả xác sống bị người chơi tiêu diệt trong quá trình chơi từ một phần trăm lên một trăm phần trăm.”
- base: "Đinh, Tỷ lệ Bạo suất Tối thượng: Tỷ lệ rơi tất cả các vật phẩm zombie bị chém giết trong quá trình game của người chơi từ 1% tăng lên 100%." `sim=0.4340; han=0; modern=0; quote=True; digits=True`
- current: "Đinh, Tỷ lệ Bạo suất Tối thượng: Tỷ lệ rơi của tất cả vật phẩm zombie bị tiêu diệt trong quá trình game của người chơi từ 1% tăng lên 100%." `sim=0.4596; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Đinh, Tỷ lệ Bạo suất Tối thượng: Tỷ lệ rơi tất cả các vật phẩm zombie bị chém giết trong quá trình game của người chơi đã tăng từ 1% lên 100%.” `sim=0.4304; han=0; modern=0; quote=True; digits=True`

## 51. [reference_60] natural_vi

- ZH: “我对超凡游戏、永恒世界的了解，还是太少太少了，其他人的兵种能否进化、兵种的品阶怎么划分、玩家前期的主要敌人是什么、兵种除了升级是否还存在其它变强之法……等等等等，我一无所知。”
- Tham chiếu: “Hiểu biết của ta về trò chơi siêu phàm và thế giới Vĩnh Hằng vẫn còn quá ít. Binh chủng của người khác có thể tiến hóa hay không? Phẩm cấp binh chủng được phân chia thế nào? Kẻ địch chủ yếu của người chơi ở giai đoạn đầu là gì? Ngoài thăng cấp, binh chủng còn có cách nào khác để mạnh lên không... Bao nhiêu chuyện như vậy, ta hoàn toàn chẳng biết gì.”
- base: "Sự hiểu biết của ta về trò chơi siêu phàm, thế giới vĩnh hằng vẫn là quá ít, quá ít, binh chủng của những người khác có thể tiến hóa hay không, phân chia phẩm cấp của binh chủng ra sao, kẻ địch chính thời kỳ đầu của người chơi là gì, binh chủng ngoài việc nâng cấp ra còn tồn tại phương pháp trở nên mạnh mẽ khác hay không... vân vân, ta hoàn toàn không biết gì cả." `sim=0.6643; han=0; modern=0; quote=True; digits=True`
- current: "Ta hiểu biết về trò chơi siêu phàm, thế giới vĩnh hằng vẫn còn quá ít, quá ít, binh chủng của những người khác có thể tiến hóa hay không, phân chia phẩm giai của binh chủng ra sao, kẻ địch chính thời kỳ đầu của người chơi là gì, binh chủng ngoài việc nâng cấp ra còn tồn tại phương pháp trở nên mạnh mẽ khác hay không... vân vân, ta hoàn toàn không biết gì cả." `sim=0.6536; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Ta hiểu biết về trò chơi siêu phàm, thế giới vĩnh hằng vẫn còn quá ít, quá ít, binh chủng của những người khác có thể tiến hóa hay không, phân chia phẩm cấp của binh chủng ra sao, kẻ địch chính của người chơi thời kỳ đầu là gì, binh chủng ngoài việc nâng cấp ra còn tồn tại phương pháp trở nên mạnh mẽ khác hay không... vân vân, ta hoàn toàn không biết gì cả.” `sim=0.6797; han=0; modern=0; quote=True; digits=True`

## 52. [reference_60] natural_vi

- ZH: 现在很多信息莫凡要自动转换，但转换的过程中就让莫凡特别无语，比如说莫凡记得有一天历史老师告诉同学们：光系的魔法鼻祖是“爱迪生”，当时莫凡内心就有亿万草泥马在奔腾！
- Tham chiếu: Hiện giờ Mạc Phàm phải tự chuyển đổi rất nhiều thông tin, nhưng quá trình ấy thường khiến hắn cạn lời. Chẳng hạn, hắn nhớ có lần giáo viên lịch sử nói với cả lớp rằng người khai sáng Quang hệ ma pháp là “Edison”. Khi ấy, trong lòng Mạc Phàm như có hàng trăm triệu con “thảo nê mã” đang phi nước đại!
- base: Hiện tại rất nhiều thông tin Mạc Phàm muốn tự động chuyển đổi, nhưng trong quá trình chuyển đổi lại khiến Mạc Phàm đặc biệt cạn lời, ví dụ như Mạc Phàm nhớ có một ngày giáo viên lịch sử nói với các bạn học: Ma pháp Tị Tổ hệ Quang là "Ái Địch Sinh", lúc đó trong lòng Mạc Phàm đã có hàng tỷ thảo nê mã đang phi nước đại! `sim=0.5785; han=0; modern=1; quote=True; digits=True`
- current: Hiện tại rất nhiều thông tin Mạc Phàm muốn tự động chuyển đổi, nhưng trong quá trình chuyển đổi lại khiến Mạc Phàm đặc biệt cạn lời, ví dụ như Mạc Phàm nhớ có một ngày giáo viên lịch sử nói với các bạn học: Ma pháp Tị Tổ hệ Quang là "Ái Địch Sinh", lúc đó trong lòng Mạc Phàm đã có hàng tỷ thảo nê mã đang phi nước đại! `sim=0.5785; han=0; modern=1; quote=True; digits=True`
- teacher_v2: Hiện tại rất nhiều thông tin Mạc Phàm muốn tự động chuyển đổi, nhưng trong quá trình chuyển đổi lại khiến Mạc Phàm đặc biệt cạn lời, ví dụ như Mạc Phàm nhớ có một ngày giáo viên lịch sử nói với các bạn học: Ma pháp Tị Tổ hệ Quang là “Ái Địch Sinh”, lúc đó trong lòng Mạc Phàm đã có hàng tỷ thảo nê mã đang phi nước đại! `sim=0.5826; han=0; modern=1; quote=True; digits=True`

## 53. [reference_60] natural_vi

- ZH: “恐怕帮你伪装出来骗那个小丫头的六品火属性单灵根，在玄岳宗隐瞒不了多久，你是一品五行灵根的事情，应该要不了多久就会暴露，你要有心理准备。”
- Tham chiếu: “E rằng Lục phẩm Hỏa thuộc tính đơn linh căn mà ta giúp ngươi ngụy trang để lừa cô bé kia sẽ không giấu được bao lâu tại Huyền Nhạc Tông. Chuyện ngươi thật sự mang Nhất phẩm Ngũ Hành Linh Căn chẳng mấy chốc sẽ bại lộ. Ngươi phải chuẩn bị tâm lý.”
- base: "E rằng giúp ngươi ngụy trang ra để lừa gạt đơn linh căn thuộc tính hỏa lục phẩm của tiểu nha đầu kia, ở Huyền Nhạc Tông không giấu được bao lâu, chuyện ngươi là ngũ hành linh căn nhất phẩm, chắc không bao lâu nữa sẽ bị lộ, ngươi phải chuẩn bị tâm lý." `sim=0.5473; han=0; modern=0; quote=True; digits=True`
- current: "E rằng giúp ngươi ngụy trang ra để lừa gạt đơn linh căn thuộc tính hỏa lục phẩm của tiểu nha đầu kia, ở Huyền Nhạc Tông không giấu được bao lâu, chuyện ngươi là Ngũ Hành linh căn nhất phẩm, chắc không bao lâu nữa sẽ bị bại lộ, ngươi phải chuẩn bị tâm lý." `sim=0.5533; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “E rằng giúp ngươi ngụy trang ra để lừa gạt đơn linh căn thuộc tính Hỏa lục phẩm của tiểu nha đầu kia, ở Huyền Nhạc Tông không giấu được bao lâu, chuyện ngươi là Ngũ Hành linh căn nhất phẩm, chắc không bao lâu nữa sẽ bị lộ, ngươi phải chuẩn bị tâm lý.” `sim=0.5575; han=0; modern=0; quote=True; digits=True`

## 54. [reference_60] natural_vi

- ZH: “领主大人。咱们的资产一共也就只有一千三百多星币。你要是把这一千星币拿去下赌注，那咱们可是连下个月的工资都要发不出来的！”
- Tham chiếu: “Lãnh chúa đại nhân, tổng tài sản của chúng ta chỉ có hơn một ngàn ba trăm tinh tệ. Nếu ngài lấy một ngàn tinh tệ đi đặt cược, tháng sau chúng ta sẽ không còn tiền trả lương!”
- base: “Lãnh chúa đại nhân. Tài sản của chúng ta tổng cộng chỉ có hơn một ngàn ba trăm tinh tệ. Nếu ngươi đem một ngàn tinh tệ này đi đặt cược, thì chúng ta ngay cả lương tháng sau cũng không phát ra được!” `sim=0.7509; han=0; modern=0; quote=True; digits=True`
- current: “Lãnh chúa đại nhân. Tài sản của chúng ta tổng cộng cũng chỉ có hơn một ngàn ba trăm tinh tệ. Nếu ngươi đem một ngàn tinh tệ này đi đặt cược, vậy chúng ta ngay cả lương tháng sau cũng không phát ra được!” `sim=0.7407; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Lãnh chúa đại nhân. Tài sản của chúng ta tổng cộng chỉ có hơn một ngàn ba trăm tinh tệ. Nếu ngài đem một ngàn tinh tệ này đi đặt cược, thì chúng ta ngay cả lương tháng sau cũng không phát ra được!” `sim=0.7603; han=0; modern=0; quote=True; digits=True`

## 55. [reference_60] natural_vi

- ZH: “我是神河市的林默！林家大量招收附庸领主，无论种田领主还是战争领主，待遇优厚，至少比军方优厚。对了，不要娱乐领主。”
- Tham chiếu: “Ta là Lâm Mặc đến từ thành Thần Hà! Lâm gia đang chiêu mộ số lượng lớn lãnh chúa chư hầu. Bất kể lãnh chúa nông nghiệp hay lãnh chúa chiến tranh đều được đãi ngộ hậu hĩnh, ít nhất tốt hơn phía quân đội. À phải, không nhận lãnh chúa giải trí.”
- base: "Ta là Lâm Mặc của thành phố Thần Hà! Lâm gia chiêu mộ số lượng lớn lãnh chúa phụ thuộc, dù là lãnh chúa trồng trọt hay lãnh chúa chiến tranh, đãi ngộ hậu hĩnh ít nhất cũng ưu đãi hơn quân đội. Đúng rồi, không cần lãnh chúa giải trí." `sim=0.7413; han=0; modern=0; quote=True; digits=True`
- current: "Ta là Lâm Mặc của thành phố Thần Hà! Lâm gia chiêu mộ số lượng lớn lãnh chúa phụ thuộc, bất kể là lãnh chúa trồng trọt hay lãnh chúa chiến tranh, đãi ngộ hậu hĩnh, ít nhất ưu đãi hơn quân đội. À, đừng giải trí lãnh chúa.” `sim=0.7342; han=0; modern=0; quote=False; digits=True`
- teacher_v2: “Ta là Lâm Mặc của thành phố Thần Hà! Nhà họ Lâm chiêu mộ rất nhiều lãnh chúa phụ thuộc, bất kể là lãnh chúa trồng trọt hay lãnh chúa chiến tranh, đãi ngộ hậu hĩnh, ít nhất cũng ưu đãi hơn quân đội. Đúng rồi, không cần lãnh chúa giải trí.” `sim=0.7124; han=0; modern=0; quote=True; digits=True`

## 56. [reference_60] natural_vi

- ZH: “你要是有心仪的，爷爷去给你找一只！当然，像银月天狼这么珍稀的妖兽，我可找不到！”
- Tham chiếu: “Nếu có loại nào vừa ý, gia gia sẽ đi tìm cho con một con! Đương nhiên, yêu thú quý hiếm như Ngân Nguyệt Thiên Lang thì gia gia không tìm nổi.”
- base: "Nếu con có tâm ý, ông nội đi tìm cho con một con! Tất nhiên, yêu thú trân quý như Ngân Nguyệt Thiên Lang thì con không tìm được đâu!" `sim=0.6912; han=0; modern=0; quote=True; digits=True`
- current: "Nếu con có lòng thích, ông nội đi tìm cho con một con! Tất nhiên, yêu thú quý hiếm như Ngân Nguyệt Thiên Lang, con không tìm thấy đâu!" `sim=0.6727; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Nếu con có tâm thích, ông nội sẽ đi tìm cho con một con! Đương nhiên, yêu thú quý hiếm như Ngân Nguyệt Thiên Lang thì con không tìm được đâu!” `sim=0.7556; han=0; modern=0; quote=True; digits=True`

## 57. [reference_60] natural_vi

- ZH: 【成功装备“冥想项链”，温馨提示：同一类型首饰装备同时装备仅能够生效一件。】
- Tham chiếu: 【Trang bị thành công “Dây Chuyền Minh Tưởng”. Nhắc nhở: khi đồng thời đeo nhiều trang sức cùng loại, chỉ một món có hiệu lực.】
- base: [Trang bị thành công "dây chuyền Thiền Định", gợi ý ấm áp: Cùng loại trang bị, đồng thời trang bị chỉ có thể phát huy tác dụng một món. ] `sim=0.5143; han=0; modern=0; quote=True; digits=True`
- current: 【Trang bị thành công "dây chuyền Thiền Định", gợi ý ấm áp: Cùng loại trang bị, đồng thời trang bị chỉ có thể hiệu lực một món.】 ] `sim=0.5784; han=0; modern=0; quote=True; digits=True`
- teacher_v2: [Trang bị thành công “dây chuyền Thiền Định”, nhắc nhở ấm áp: Cùng loại trang bị, đồng thời trang bị chỉ có thể phát huy tác dụng một món. ] `sim=0.5822; han=0; modern=0; quote=True; digits=True`

## 58. [reference_60] natural_vi

- ZH: “大叔，你不会是什么妖兽变得吧，鼻子这么灵？”林轩心喜道。
- Tham chiếu: “Đại thúc, chẳng lẽ ngươi do yêu thú biến thành sao? Sao mũi lại thính như vậy?” Lâm Hiên mừng rỡ nói.
- base: "Đại thúc, chẳng lẽ ngươi là yêu thú gì biến thành, mũi thính thế?" Lâm Hiên vui mừng hỏi. `sim=0.7582; han=0; modern=0; quote=True; digits=True`
- current: "Đại thúc, chẳng lẽ ngươi là yêu thú gì biến thành, mũi thính thế?" Lâm Hiên vui mừng nói. `sim=0.7843; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Chú ơi, chú không phải là yêu thú nào đó biến thành sao, mũi thính thế?” Lâm Hiên vui mừng nói. `sim=0.6752; han=0; modern=0; quote=True; digits=True`

## 59. [reference_60] natural_vi

- ZH: “事不关己，咱们没必要吵闹。”陈青源说出了内心的想法：“该急的应该是天玉宗，而非我玄青宗。退一万步来说，魔窟真要爆发了，先将天玉宗给毁了，到时候咱们联合同道修士去处理也来得及。”
- Tham chiếu: “Chuyện không liên quan đến chúng ta, chẳng cần phải ầm ĩ.” Trần Thanh Nguyên nói ra suy nghĩ trong lòng: “Kẻ nên sốt ruột là Thiên Ngọc Tông, không phải Huyền Thanh Tông. Dù lùi một vạn bước mà nói, nếu Ma Quật thật sự bộc phát thì Thiên Ngọc Tông cũng sẽ bị hủy diệt trước. Đến lúc ấy, chúng ta liên thủ với tu sĩ đồng đạo xử lý vẫn chưa muộn.”
- base: "Chuyện không liên quan đến mình, chúng ta không cần phải ồn ào." Trần Thanh Nguyên nói ra suy nghĩ trong lòng: "Người cần gấp phải là Thiên Ngọc Tông, chứ không phải Huyền Thanh Tông ta. Lùi một vạn bước mà nói, Ma Quật thật sự muốn bộc phát, trước tiên hủy Thiên Ngọc Tông, đến lúc đó chúng ta liên hợp với đồng đạo tu sĩ đi xử lý cũng kịp." `sim=0.7587; han=0; modern=1; quote=True; digits=True`
- current: "Chuyện không liên quan đến mình, chúng ta không cần phải ồn ào." Trần Thanh Nguyên nói ra suy nghĩ trong lòng: "Người cần vội chắc là Thiên Ngọc Tông, chứ không phải Huyền Thanh Tông ta. Lùi một vạn bước mà nói, Ma Quật thực sự bùng nổ, trước tiên phá hủy Thiên Ngọc Tông, đến lúc đó chúng ta liên hợp với đồng đạo tu sĩ đi xử lý cũng còn kịp." `sim=0.7500; han=0; modern=1; quote=True; digits=True`
- teacher_v2: “Chuyện không liên quan đến mình, chúng ta không cần phải ồn ào.” Trần Thanh Nguyên nói ra suy nghĩ trong lòng: “Người cần vội chắc là Thiên Ngọc Tông, chứ không phải Huyền Thanh Tông ta. Lùi một vạn bước mà nói, Ma Quật thật sự bùng nổ, trước tiên hủy diệt Thiên Ngọc Tông, đến lúc đó chúng ta liên kết với đồng đạo tu sĩ đi xử lý cũng kịp.” `sim=0.7601; han=0; modern=1; quote=True; digits=True`

## 60. [reference_60] natural_vi

- ZH: “真强大呀，青鳞鹰是太古魔禽的后裔，血脉即便早已不纯净，但生命印记中也还有部分破碎的符文传承。”小不点每日都学习骨文，此时看出了端倪，扑闪着大眼，小大人般，清脆的说道。
- Tham chiếu: “Thật mạnh! Thanh Lân Ưng là hậu duệ của Thái Cổ Ma Cầm. Dù huyết mạch từ lâu đã không còn thuần khiết, trong ấn ký sinh mệnh vẫn lưu giữ một phần truyền thừa phù văn đã vỡ vụn.” Nhóc tỳ ngày nào cũng học cốt văn nên lập tức nhìn ra manh mối. Nó chớp đôi mắt to, ra vẻ tiểu đại nhân, cất giọng trong trẻo nói.
- base: "Thật cường đại nha, Thanh Lân Ưng là hậu duệ của Thái Cổ Ma Cầm, huyết mạch mặc dù sớm đã không thuần khiết, nhưng trong Sinh Mệnh Ấn Ký cũng còn có một phần phù văn truyền thừa vỡ nát." Nhóc tỳ mỗi ngày đều học cốt văn, lúc này nhìn ra manh mối, chớp chớp mắt to, thanh thúy nói. `sim=0.6696; han=0; modern=0; quote=True; digits=True`
- current: "Thật cường đại nha, Thanh Lân Ưng là hậu duệ của Thái Cổ Ma Cầm, huyết mạch cho dù sớm đã không thuần khiết, nhưng trong Sinh Mệnh Ấn Ký cũng còn có một phần truyền thừa phù văn vỡ nát." Tiểu tỳ mỗi ngày đều học cốt văn, lúc này nhìn ra manh mối, chớp chớp mắt to, giống như người lớn, thanh thúy nói. `sim=0.6709; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Thật mạnh mẽ, Thanh Lân Ưng là hậu duệ của Thái Cổ Ma Cầm, dù huyết mạch đã không còn thuần khiết, nhưng trong dấu ấn sinh mệnh vẫn còn một phần truyền thừa phù văn vỡ vụn.” Nhóc tỳ ngày nào cũng học cốt văn, lúc này nhìn ra manh mối, đôi mắt to chớp chớp, thanh thúy nói. `sim=0.7885; han=0; modern=0; quote=True; digits=True`

## 61. [game_english] game_english

- ZH: 在绝大多数副本里，NPC和Boss是绝对不占玩家名额的。
- Tham chiếu: Trong phần lớn phó bản, NPC và Boss tuyệt đối không chiếm chỉ tiêu người chơi.
- base: Trong tuyệt đại đa số phó bản, NPC và Boss tuyệt đối không chiếm suất người chơi. `sim=0.7812; han=0; modern=0; quote=True; digits=True`
- current: Trong tuyệt đại đa số phó bản, NPC và Boss tuyệt đối không chiếm suất người chơi. `sim=0.7812; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Trong tuyệt đại đa số phó bản, NPC và Boss tuyệt đối không chiếm suất người chơi. `sim=0.7812; han=0; modern=0; quote=True; digits=True`

## 62. [game_english] game_english

- ZH: 他死死盯着ID冷月清泉，这才反应过来，这是林锋以前的一个小号，那些大号都打不上去的时候，他就会搞一堆这种号，半夜偷偷上分。
- Tham chiếu: Hắn nhìn chằm chằm ID Lãnh Nguyệt Thanh Tuyền rồi mới nhận ra đây là một tài khoản phụ cũ của Lâm Phong. Khi các tài khoản chính không leo rank được, hắn sẽ lập một loạt tài khoản như vậy để lén lên điểm vào ban đêm.
- base: Hắn gắt gao nhìn chằm chằm vào Lãnh Nguyệt Thanh Tuyền của ID, lúc này mới phản ứng lại, đây là một tài khoản nhỏ trước đây của Lâm Phong, khi những tài khoản lớn đó không đánh lên được, hắn đã bày ra một đống tài khoản này, nửa đêm lén lút tăng điểm. `sim=0.6612; han=0; modern=0; quote=True; digits=True`
- current: Hắn chằm chằm nhìn ID Lãnh Nguyệt Thanh Tuyền, lúc này mới phản ứng lại, đây là một tài khoản nhỏ trước đây của Lâm Phong, khi những tài khoản lớn đó còn không đánh lên được, hắn đã bày ra một đống tài khoản này, nửa đêm lén lên điểm. `sim=0.6799; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Hắn nhìn chằm chằm vào Lãnh Nguyệt Thanh Tuyền của ID, lúc này mới phản ứng lại, đây là một tài khoản nhỏ trước đây của Lâm Phong. Khi những tài khoản lớn đó không đánh lên được, hắn đã bày ra một đống tài khoản này, nửa đêm lén lút tăng điểm. `sim=0.6778; han=0; modern=0; quote=True; digits=True`

## 63. [game_english] game_english

- ZH: 手握大龙Buff的RNG继续采用四一分推战术。
- Tham chiếu: RNG cầm Buff Rồng, tiếp tục triển khai chiến thuật đẩy lẻ 4-1.
- base: Cặp vật cứng trong tay Đại Long BUF tiếp tục áp dụng chiến thuật đẩy bốn một phần. `sim=0.4696; han=0; modern=0; quote=True; digits=True`
- current: Tay nắm chặt vật cứng của Đại Long BUF tiếp tục áp dụng chiến thuật đẩy bốn phần. `sim=0.4912; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Tay cầm vật cứng của Đại Long BUF tiếp tục áp dụng chiến thuật đẩy bốn một phần. `sim=0.4956; han=0; modern=0; quote=True; digits=True`

## 64. [game_english] game_english

- ZH: 这时大舅子正在和新人AD对点，周曦臣现在三件套加多兰剑、CD鞋，Mystic的霞现在两件半多。
- Tham chiếu: Lúc này Mystic đang đấu tay đôi với AD tân binh. Chu Hi Thần đã có ba món lớn, thêm Kiếm Doran và giày CD; Xayah của Mystic mới có hai món rưỡi.
- base: Lúc này đại cữu tử đang đối đầu với AD tân binh, Chu Hi Thần hiện tại có ba món cộng thêm kiếm Đa Lan, giày CD, Hà của Mystic hiện tại đã hơn hai món. `sim=0.6784; han=0; modern=0; quote=True; digits=True`
- current: Lúc này cậu vợ đang đối điểm với AD tân binh, Chu Hi Thần hiện tại có ba bộ game cộng thêm Doland kiếm, Giày CD, Hà của Mystic hiện tại đã hơn hai bộ rưỡi. `sim=0.6379; han=0; modern=1; quote=True; digits=True`
- teacher_v2: Lúc này đại cữu tử đang đối đầu với AD tân binh, Chu Hi Thần hiện đang ba món gộp thêm kiếm Đa Lan, giày CD, Hà của Mystic hiện đã hơn hai món. `sim=0.6757; han=0; modern=0; quote=True; digits=True`

## 65. [game_english] game_english

- ZH: 参赛队伍分两个小组，分别是A组CyberZen、MVP.Karnal、Chiefs、RiskyGaming，B组Renegades、TyLoo、MongolZ、EatYouAlive。
- Tham chiếu: Các đội dự thi chia làm hai bảng: bảng A gồm CyberZen, MVP.Karnal, Chiefs, RiskyGaming; bảng B gồm Renegades, TyLoo, MongolZ, EatYouAlive.
- base: Đội tham gia chia làm hai nhóm, lần lượt là nhóm A CyberZen, MVP. Karnal, Jiefs, Risky Gaming, nhóm B Renegades, Ty Loo, MongolZ, EatYouAlive. `sim=0.7830; han=0; modern=0; quote=True; digits=True`
- current: Đội dự thi chia làm hai nhóm, lần lượt là nhóm A CyberZen, MVP.Karnal, Jiefs, RiskyGaming, nhóm B Renegades, Ty Loo, MongolouAlive. `sim=0.7753; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Đội tham gia chia làm hai nhóm, lần lượt là nhóm A CyberZen, MVP. Karnal, Jiefs, Risky Gaming, nhóm B Renegades, Ty Loo, MonolZ, EatYouAlive. `sim=0.7778; han=0; modern=0; quote=True; digits=True`

## 66. [game_english] game_english

- ZH: 这是天赋吗，这是Debuff啊！
- Tham chiếu: Đây mà là thiên phú sao? Rõ ràng là Debuff!
- base: Đây là thiên phú sao, đây là De buff đấy! `sim=0.7576; han=0; modern=0; quote=True; digits=True`
- current: Đây là thiên phú sao, đây là De buff a! `sim=0.7812; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Đây là thiên phú sao, đây là De buff đấy! `sim=0.7576; han=0; modern=0; quote=True; digits=True`

## 67. [game_english] game_english

- ZH: 国内有八只队伍同台角逐，分别是tyloo、wings、AG、BOF、Gank、Rstar、RS、eFuture，通过双败淘汰制，最终冠军会获得IEM台北站的参赛资格。
- Tham chiếu: Có tám đội trong nước tranh tài: tyloo, wings, AG, BOF, Gank, Rstar, RS và eFuture. Qua thể thức loại kép, đội vô địch sẽ giành suất dự IEM Đài Bắc.
- base: Trong nước có tám đội ngũ cùng tranh đấu, lần lượt là Tyloo, wings, AG, BOF, Gank, RStar, RS, RS, EFuture, thông qua chế độ loại bỏ song bại, quán quân cuối cùng sẽ giành được tư cách tham gia của Trạm phía bắc đài IEM. `sim=0.5342; han=0; modern=0; quote=True; digits=True`
- current: Trong nước có tám đội ngũ cùng nhau tranh đấu, lần lượt là Tyloo,wings, AG, BOF, Gank, RStar, RS, RS, EFuture, thông qua chế độ loại bỏ song bại, cuối cùng quán quân sẽ giành được tư cách tham gia của Trạm Bắc IEM Đài. `sim=0.5548; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Trong nước có tám đội tranh đấu cùng đài, lần lượt là Tyloo, wings, AG, BOF, Gank, RStar, RS, EFuture, thông qua chế độ loại bỏ song bại, quán quân cuối cùng sẽ giành được tư cách tham gia của Trạm phía bắc đài IEM. `sim=0.5329; han=0; modern=0; quote=True; digits=True`

## 68. [game_english] game_english

- ZH: 下半年，是快到令人发指的狙神KennyS，他所在的EnvyUs战队成为了DreamHack 克卢日-纳波卡 major冠军，他们战胜了拥有瓜皇的NAVI。
- Tham chiếu: Nửa cuối năm, tay bắn tỉa KennyS nhanh đến mức đáng sợ; đội EnvyUs của hắn vô địch DreamHack Cluj-Napoca major sau khi đánh bại NAVI có Qua Hoàng.
- base: Nửa cuối năm, là thần bắn tỉa KennyS nhanh đến mức đáng sợ, đội EnyUS nơi hắn đang ở đã trở thành quán quân Dream Triều Kuck Nhật - Napakeljor, bọn họ đã đánh bại NAVI sở hữu Qua Hoàng. `sim=0.6818; han=0; modern=0; quote=True; digits=True`
- current: Nửa cuối năm, là thần bắn tỉa KennyS nhanh đến mức đáng sợ, đội EnvyUS nơi hắn đang ở đã trở thành quán quân Dream Triềuck Clumi-Nanabarjor, họ đã đánh bại NAVI sở hữu Qua Hoàng. `sim=0.7203; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Nửa cuối năm, là thần bắn tỉa KennyS sắp đến mức đáng sợ, đội EnyUS nơi hắn đang ở đã trở thành quán quân DreamS, ngày Clu-Nabaca-Jor, bọn họ đã đánh bại NAVI sở hữu Qua Hoàng. `sim=0.6667; han=0; modern=0; quote=True; digits=True`

## 69. [game_english] game_english

- ZH: 主教练菲尔·马特尔利以“高位挡拆+快速攻防转换”为核心，打造全美效率第3的进攻体系，荣获奈史密斯年度最佳教练（Naismith College Coach of the Year）。
- Tham chiếu: Huấn luyện viên trưởng Phil Martelli lấy chiến thuật pick-and-roll ở vị trí cao kết hợp chuyển đổi công thủ nhanh làm cốt lõi, xây dựng hệ thống tấn công hiệu quả thứ ba nước Mỹ và giành giải Naismith College Coach of the Year.
- base: Huấn luyện viên Phil Matelley lấy "Chuyển hóa công thủ cấp cao + chuyển đổi công thủ nhanh chóng" làm cốt lõi, tạo ra hệ thống tấn công thứ 3 toàn nước Mỹ, vinh dự giành được huấn luyện viên xuất sắc nhất năm Naismith (Naismith Walge Coach of theYear). `sim=0.6321; han=0; modern=0; quote=True; digits=True`
- current: Huấn luyện viên Phil Martelli lấy "cấp độ cao + chuyển đổi công thủ nhanh" làm cốt lõi, tạo ra hệ thống tấn công hiệu suất thứ 3 toàn nước Mỹ, giành được huấn luyện viên xuất sắc nhất năm của Naismith (Naismithlge Coach of the Year). `sim=0.6703; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Huấn luyện viên Phil Mateli lấy “Đổi đổi chống đỡ vị trí cao + chuyển đổi công thủ nhanh” làm cốt lõi, xây dựng hệ thống tấn công thứ 3 toàn nước Mỹ, vinh dự được huấn luyện viên xuất sắc nhất năm Naismith Coach of the YeYear). `sim=0.6942; han=0; modern=0; quote=True; digits=True`

## 70. [game_english] game_english

- ZH: 公告显示，qz因为曾经使用的关联账号，在2013年MSI beat it比赛后被VAC封禁。所以ESL官方决定对Tyloo队员qz终身禁赛，这个处罚不可谓不重。
- Tham chiếu: Thông báo cho biết tài khoản liên quan qz từng dùng đã bị VAC cấm sau giải MSI Beat It năm 2013. Vì vậy ESL quyết định cấm qz của Tyloo thi đấu vĩnh viễn; đây là án phạt rất nặng.
- base: Thông báo cho thấy, vì tài khoản liên quan từng được sử dụng, Qz đã bị VAC phong tỏa sau cuộc thi 2013. Vì vậy, chính quyền ESL quyết định thi đấu cấm chung thân với đội viên Tyloo, hình phạt này không thể nói là không nặng. `sim=0.5506; han=0; modern=0; quote=True; digits=True`
- current: Thông báo cho thấy, Qz vì tài khoản liên quan từng sử dụng, năm 2013 MSI beat bị VAC phong tỏa sau trận đấu it. Vì vậy, chính quyền ESL quyết định thi đấu cấm chung thân với thành viên Tylooqz, hình phạt này không thể nói là không nặng. `sim=0.5399; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Thông báo cho thấy, vì tài khoản liên quan từng được sử dụng, Qz đã bị VAC phong tỏa sau trận 2013. Vì vậy, chính quyền ESL quyết định cấm thi đấu quanh năm với đội viên Tyloo, hình phạt này không thể nói là không nặng. `sim=0.6154; han=0; modern=0; quote=True; digits=True`

## 71. [game_english] game_english

- ZH: 对面的Fofo确实不负S10赛季LPL顶尖中单之名，个人能力强，大局观、团战能力等都非常出色，带动了整个BLG的节奏。
- Tham chiếu: Fofo phía đối diện quả không phụ danh xưng đường giữa hàng đầu LPL mùa S10: năng lực cá nhân, tầm nhìn đại cục và giao tranh đều rất xuất sắc, kéo nhịp độ cho cả BLG.
- base: Fofo đối diện quả thực không phụ danh tiếng trung bình hàng đầu của LPL trong mùa giải S10, năng lực cá nhân mạnh, tầm nhìn đại cục, năng lực đoàn chiến... đều rất xuất sắc, kéo theo nhịp điệu của toàn bộ BLG. `sim=0.6959; han=0; modern=0; quote=True; digits=True`
- current: Fofo đối diện quả thực không phụ danh tiếng đường giữa hàng đầu LPL trong mùa giải S10, năng lực cá nhân mạnh, tầm nhìn đại cục, năng lực đoàn chiến v.v., đều rất xuất sắc, kéo theo nhịp điệu của toàn bộ BLG. `sim=0.7322; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Fofo đối diện quả thực không phụ danh tiếng trung bình hàng đầu của LPL trong mùa giải S10, năng lực cá nhân mạnh, tầm nhìn đại cục, năng lực đoàn chiến đều rất xuất sắc, thúc đẩy nhịp độ của toàn bộ BLG. `sim=0.7010; han=0; modern=0; quote=True; digits=True`

## 72. [game_english] game_english

- ZH: “尘埃战队也不错啊，两个韩国外援上单flu和adc位置的mote，那个mote还是上届世界总冠军战队韩国ssk的冠军adc好么！”
- Tham chiếu: “Đội Dust cũng không tệ: ngoại binh Hàn Quốc đường trên flu và mote ở vị trí ADC. mote từng là ADC vô địch thế giới mùa trước của đội ssk Hàn Quốc đấy!”
- base: “Chiến đội Trần Bạch cũng không tệ, hai người ngoại viện Hàn Quốc lên Mote ở vị trí đơn lẻ và Adc, Mote đó còn là quán quân SSK của Hàn Quốc, chiến đội tổng quán quân thế giới lần trước đấy nhé!” `sim=0.5074; han=0; modern=0; quote=True; digits=True`
- current: “Chiến đội Bụi Trần cũng không tệ, hai người ngoại viện Hàn Quốc lên Mote ở vị trí flu và Adc, Mote đó còn là nhà vô địch của Hàn Quốc SK, được không!” `sim=0.5992; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Chiến đội Trần Tinh cũng không tệ, hai người ngoại viện Hàn Quốc lên Mote ở vị trí đơn lẻ và Adc, Mote đó còn là quán quân SSK của đội quán quân thế giới lần trước đấy nhé!” `sim=0.5569; han=0; modern=0; quote=True; digits=True`

## 73. [game_english] game_english

- ZH: captainMO熟练地导入播放……很快看完了demo，明显也是震惊加一脑袋问号。他打开steam消息栏，找到advent，在键盘上敲道。
- Tham chiếu: captainMO thuần thục mở bản phát lại. Xem xong demo, hắn cũng sững sờ đầy dấu hỏi. Hắn mở khung tin nhắn steam, tìm advent rồi gõ trên bàn phím.
- base: aptainMO thành thạo dẫn vào phát... Rất nhanh sau khi xem xong Demo, rõ ràng cũng là kinh ngạc cộng thêm một đầu dấu chấm hỏi. Hắn mở bảng tin nhắn Steam, tìm thấy Advent, gõ bàn phím. `sim=0.6565; han=0; modern=0; quote=True; digits=True`
- current: CaptainMO thành thạo dẫn vào phát... Rất nhanh xem xong Demo, rõ ràng cũng là kinh ngạc cộng thêm một đầu dấu chấm hỏi. Hắn mở bảng thông tin Steam, tìm thấy Advent, gõ bàn phím. `sim=0.6512; han=0; modern=0; quote=True; digits=True`
- teacher_v2: aptainMO thành thạo dẫn vào phát... Rất nhanh sau khi xem xong Demo, rõ ràng cũng là kinh ngạc xen lẫn một đầu dấu chấm hỏi. Hắn mở bảng tin nhắn Steam, tìm thấy Advent, gõ bàn phím. `sim=0.6615; han=0; modern=0; quote=True; digits=True`

## 74. [game_english] game_english

- ZH: 最后，匹配了很久，终于匹配到了。对面是AG战队的三名选手加diyy，AG三名选手分别是forget、ED101、wjw。他们最近刚刚入驻B5对战平台。
- Tham chiếu: Sau khi ghép trận rất lâu, cuối cùng cũng vào được. Phía đối diện là ba tuyển thủ AG cùng diyy: forget, ED101 và wjw. Gần đây họ vừa vào nền tảng đối chiến B5.
- base: Cuối cùng, đã ghép xong rất lâu, cuối cùng cũng khớp được. Đối diện là ba tuyển thủ của chiến đội AG, ba tuyển thủ AG lần lượt là Forget, ED101, wjw. Bọn hắn gần đây vừa mới đặt chân vào nền tảng đối chiến B5. `sim=0.6920; han=0; modern=0; quote=True; digits=True`
- current: Cuối cùng, ghép rất lâu, cuối cùng cũng ghép được. Đối diện là ba tuyển thủ của chiến đội AG G, ba tuyển thủ AG lần lượt là Forget, ED101, wjw. Bọn hắn gần đây vừa mới tiến vào nền tảng đối chiến B5. `sim=0.7046; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Cuối cùng, sau khi ghép lại rất lâu, cuối cùng cũng khớp được. Đối diện là ba tuyển thủ của đội AG là Gia Diyy, ba tuyển thủ của AG lần lượt là Forget, ED101, wjw. Gần đây họ vừa mới đặt chân vào nền tảng đối chiến B5. `sim=0.7322; han=0; modern=0; quote=True; digits=True`

## 75. [game_english] game_english

- ZH: “让我们！欢迎这次代表LPL赛区，出征2017年英雄联盟世界总决赛的三支队伍！第一支种子战队，EDward——Gaming！EDG！G！G！”
- Tham chiếu: “Hãy chào đón ba đội đại diện LPL chinh chiến Chung kết Thế giới Liên Minh Huyền Thoại 2017! Đội hạt giống số một: EDward——Gaming! EDG! G! G!!!!!”
- base: "Chúng ta! Hoan nghênh lần này đại diện cho khu vực LPL, xuất chinh ba đội chung kết thế giới Liên minh Anh hùng năm 2017! Đội hạt giống đầu tiên, EDward - Gaming! EDG! G! G!" `sim=0.6357; han=0; modern=0; quote=True; digits=True`
- current: "Chúng ta! Hoan nghênh lần này đại diện cho khu vực LPL, xuất chinh ba đội chung kết thế giới Liên minh Anh hùng năm 2017! Đội hạt giống đầu tiên, EDward - Gaming! EDG! G! G!" `sim=0.6357; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Chúng ta! Hoan nghênh lần này đại diện cho khu vực LPL, xuất chinh ba đội chung kết Thế giới Liên minh Anh hùng năm 2017! Đội hạt giống đầu tiên, EDward - Gaming! EDG! G! G!” `sim=0.6512; han=0; modern=0; quote=True; digits=True`

## 76. [game_english] game_english

- ZH: Kindy看到Jason边聆听边点头，知道他也认同自己的看法，又继续说道：“我这边还有一个想法，跟Wings俱乐部那边深谈一下，把DD和Attacker对调，我们两个俱乐部都做一个探索，也给这两个职业选手换一下环境，也许能有不一样的化学反应。这样Wings俱乐部损失也不大，甚至还有好处，如果我们从那边硬要Attacker，肯定要花不少钱。”
- Tham chiếu: Kindy thấy Jason vừa nghe vừa gật đầu, biết hắn cũng đồng ý nên nói tiếp: “Ta còn một ý, hãy bàn kỹ với Wings về việc trao đổi DD và Attacker. Hai câu lạc bộ cùng thử một lần, cũng cho hai tuyển thủ đổi môi trường; biết đâu tạo ra phản ứng khác. Wings thiệt hại không lớn, thậm chí còn có lợi; nếu ta cứ đòi Attacker thì chắc phải tốn không ít tiền.”
- base: Kindy nhìn thấy Jason vừa nghe vừa gật đầu, Biết hắn cũng đồng ý với cách nhìn của mình, Lại tiếp tục nói: “Bên ta còn một ý tưởng nữa, Nói chuyện sâu với câu lạc bộ Wings, Đem DD và Attacker đối đầu, Hai câu lạc bộ chúng ta đều tiến hành khám phá, Cũng thay đổi môi trường cho hai tuyển thủ chuyên nghiệp này, Có lẽ sẽ có phản ứng hóa học khác biệt. Như vậy câu lạc bộ Wings cũng tổn thất không lớn, Thậm chí còn có lợi ích, Nếu chúng ta cứ khăng khăng đòi Attacker từ phía đó, Chắc chắn phải tốn không ít tiền." `sim=0.6361; han=0; modern=1; quote=False; digits=True`
- current: Kindy nhìn thấy Jason vừa lắng nghe vừa gật đầu, Biết hắn cũng tán thành quan điểm của mình, Lại tiếp tục nói: "Bên ta còn một ý tưởng nữa, Nói chuyện sâu với câu lạc bộ Wings, Đem DD và Attacker đối đầu, Hai câu lạc bộ chúng ta đều tiến hành khám phá, Cũng thay đổi môi trường cho hai tuyển thủ chuyên nghiệp này, Có lẽ sẽ có phản ứng hóa học khác biệt. Như vậy câu lạc bộ Wings tổn thất cũng không lớn, Thậm chí còn có lợi ích, Nếu chúng ta cứ khăng khăng đòi Attacker từ phía đó, "Chắc chắn phải tốn không ít tiền." `sim=0.6109; han=0; modern=1; quote=False; digits=True`
- teacher_v2: Kindy nhìn Jason vừa lắng nghe vừa gật đầu, Biết hắn cũng đồng ý với cách nhìn của mình, Lại tiếp tục nói: “Bên ta còn một ý tưởng nữa, Nói chuyện sâu với câu lạc bộ Wings, Đem DD và Attacker đối đầu, Hai câu lạc bộ chúng ta đều tiến hành thăm dò, Cũng thay đổi môi trường cho hai tuyển thủ chuyên nghiệp này, Có lẽ sẽ có phản ứng hóa học khác biệt. Như vậy câu lạc bộ Wings cũng tổn thất không lớn, Thậm chí còn có lợi ích, Nếu chúng ta cứ khăng khăng đòi Attacker từ bên kia, Chắc chắn phải tốn không ít tiền.” `sim=0.6281; han=0; modern=1; quote=True; digits=True`

## 77. [game_english] game_english

- ZH: “Game,Set,Match 有栖澪 6:4！”
- Tham chiếu: “Game, Set, Match — Arisu Mio, 6:4!”
- base: “Game, Set, Match có Tê Miêu 6:4!” `sim=0.7586; han=0; modern=0; quote=True; digits=True`
- current: "Game, Set, Match có Tê Linh 6:4!" `sim=0.6552; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Game, Set, Match có Tê Miêu 6:4!” `sim=0.7586; han=0; modern=0; quote=True; digits=True`

## 78. [game_english] game_english

- ZH: “cao，真会抓timing”zhoking有点破防。
- Tham chiếu: “Mẹ kiếp, bắt timing chuẩn thật.” zhoking hơi mất bình tĩnh.
- base: "Cao, thật biết bắt timing" Zhoking có chút mất bình tĩnh. `sim=0.6327; han=0; modern=0; quote=True; digits=True`
- current: "Cao, thật biết bắt Timing"zhoking có chút mất bình tĩnh. `sim=0.6327; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Caoao, thật biết bắt Timing” Zhoking có chút mất bình tĩnh. `sim=0.6600; han=0; modern=0; quote=True; digits=True`

## 79. [game_english] game_english

- ZH: 曼联这边自然是不甘示弱的，“Glory Glory Man United”的声音响彻现场。
- Tham chiếu: Phía Man United dĩ nhiên không chịu lép vế, tiếng hô “Glory Glory Man United” vang khắp sân.
- base: Bên phía Liên Xô đương nhiên không cam chịu yếu thế, tiếng nói của "Glory glory Amnited" vang vọng khắp hiện trường. `sim=0.6235; han=0; modern=0; quote=True; digits=True`
- current: Bên phía Mancent đương nhiên không cam chịu yếu thế, tiếng nói "Glory Glory Amnited" vang vọng khắp hiện trường. `sim=0.6667; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Bên phía Liên Xan đương nhiên không cam chịu yếu thế, tiếng nói của “Glory gloryam United” vang vọng khắp hiện trường. `sim=0.6628; han=0; modern=0; quote=True; digits=True`

## 80. [game_english] game_english

- ZH: 手枪局，刘风没有起P250或者FN57等加强型枪械，只是起了防弹衣，使用用默认的USP手枪。
- Tham chiếu: Ở round súng lục, Lưu Phong không mua P250 hay FN57 mà chỉ mua giáp chống đạn, dùng khẩu USP mặc định.
- base: Trong cục súng lục, Lưu Phong không khởi động các loại súng tăng cường như P250 hoặc FN57, chỉ cầm áo chống đạn, sử dụng súng lục USP mặc định. `sim=0.6256; han=0; modern=0; quote=True; digits=True`
- current: Súng lục, Lưu Phong không khởi động các loại súng tăng cường như P250 hay FN57, chỉ dựng áo chống đạn, sử dụng súng lục USP mặc định. `sim=0.6417; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Súng lục, Lưu Phong không khởi động các loại súng tăng cường như P250 hay FN57, chỉ cầm áo chống đạn lên, sử dụng khẩu súng lục USP mặc định. `sim=0.6632; han=0; modern=0; quote=True; digits=True`

## 81. [game_english] game_english

- ZH: S级的转盘的抽奖范围在[S-A-B-C]，SSS等级的转盘抽奖范围在[SSS-SS-S-A]。
- Tham chiếu: Phạm vi rút thưởng của vòng quay cấp S là [S-A-B-C], còn vòng quay cấp SSS là [SSS-SS-S-A].
- base: Phạm vi rút thưởng của vòng quay cấp S nằm ở [S-A-B-C], phạm vi rút thưởng vòng quay cấp SSS nằm ở [SS-S-A]. `sim=0.8000; han=0; modern=0; quote=True; digits=True`
- current: Vòng quay cấp S có phạm vi rút thưởng ở [S-A-B-C], vòng quay cấp SSS rút thưởng nằm trong [SS-SS-A]. `sim=0.6323; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Phạm vi rút thưởng vòng quay cấp S nằm ở [S-A-B-C], phạm vi rút thưởng vòng quay cấp SSS nằm ở [SS-S-S-A]. `sim=0.7925; han=0; modern=0; quote=True; digits=True`

## 82. [game_english] game_english

- ZH: QG（红色方）：凯（Fly）、盘古（giao）、周瑜（mojo）、李元芳（妖刀）、盾山（770）
- Tham chiếu: QG (phía đỏ): Khải (Fly), Bàn Cổ (giao), Chu Du (mojo), Lý Nguyên Phương (Yêu Đao), Thuẫn Sơn (770).
- base: QG (Phương Đỏ): Khải (Fly), Bàn Cổ (thuao), Chu Du (mojo), Lý Nguyên Phương (Yêu Đao), Thuẫn Sơn (770) `sim=0.9277; han=0; modern=0; quote=True; digits=True`
- current: QG (phe Đỏ): Khải (Fly), Bàn Cổ (tao), Chu Du (mojo)), Lý Nguyên Phương (Yêu Đao), Thuẫn Sơn (770) `sim=0.9506; han=0; modern=0; quote=True; digits=True`
- teacher_v2: QG (Phan Đỏ): Khải (Fly), Bàn Cổ (thuao), Chu Du (mojo), Lý Nguyên Phương (Yêu Đao), Thuẫn Sơn (770) `sim=0.9512; han=0; modern=0; quote=True; digits=True`

## 83. [game_english] game_english

- ZH: 谢无争往上翻了翻聊天记录，找到了那个待完成的订单信息，是他以前一直玩的FPS游戏《Endless Fire》。
- Tham chiếu: Tạ Vô Tranh lướt lại lịch sử chat, tìm thấy thông tin đơn hàng chưa hoàn tất: đó là game FPS hắn từng chơi, 《Endless Fire》.
- base: Tạ Vô Tranh lật xem lịch sử trò chuyện, tìm thấy thông tin đơn hàng đang chờ hoàn thành, đó là trò chơi FPS mà hắn từng chơi trước đây. `sim=0.6765; han=0; modern=0; quote=True; digits=True`
- current: Tạ Vô Tranh lật xem lịch sử trò chuyện, tìm thấy thông tin đơn hàng chờ hoàn thành kia, là trò chơi FPS mà hắn vẫn luôn chơi trước đây "Ends Fire". `sim=0.6075; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Tạ Vô Tranh lật xem lịch sử trò chuyện, tìm thấy thông tin đơn hàng đã hoàn thành, đó là trò chơi FPS mà hắn từng chơi trước đây. `sim=0.6734; han=0; modern=0; quote=True; digits=True`

## 84. [game_english] game_english

- ZH: 心思回到新装备上，刘风发现都是一些大名鼎鼎的装备，有卓威的EC2鼠标，有赛睿的机械键盘和QCK+鼠标垫，有icemat的西伯利亚耳机。
- Tham chiếu: Nghĩ lại dàn trang bị mới, Lưu Phong nhận ra toàn đồ nổi tiếng: chuột EC2 của Zowie, bàn phím cơ và lót chuột QCK+ của SteelSeries, tai nghe Siberia của icemat.
- base: Tâm tư trở lại trang bị mới, Lưu Phong phát hiện toàn là những trang bị lừng danh, có chuột EC2 nổi tiếng, có bàn phím cơ khí của Tái Duệ và đệm chuột QCK+, tai nghe Siberia của Kemat. `sim=0.5766; han=0; modern=0; quote=True; digits=True`
- current: Tâm tư quay về trang bị mới, Lưu Phong phát hiện toàn là những trang bị lừng danh, có chuột EC2 của Trác Uy, có bàn phím cơ khí của Tái Duệ và đệm chuột QCK+, tai nghe Siberia của Kemat. `sim=0.5964; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Tâm trí quay lại trang bị mới, Lưu Phong phát hiện toàn là những trang bị lừng danh, có chuột EC2 nổi tiếng, có bàn phím máy móc của Tái Duệ và đệm chuột QCK+, tai nghe Siberia của Kemat. `sim=0.5632; han=0; modern=0; quote=True; digits=True`

## 85. [game_english] game_english

- ZH: 【收服厉鬼奖励：积分x300，经验值x300，随机道具x1。击杀厉鬼奖励：积分x150，经验值x100，无道具掉落。建议优先选择收服。】
- Tham chiếu: 【Thu phục lệ quỷ: điểm x300, kinh nghiệm x300, đạo cụ ngẫu nhiên x1. Tiêu diệt lệ quỷ: điểm x150, kinh nghiệm x100, không rơi đạo cụ. Khuyến nghị ưu tiên thu phục.】
- base: 【Phần thưởng thu phục lệ quỷ: Điểm tích lũy x300, điểm kinh nghiệm x300, đạo cụ ngẫu nhiên x1. Phần thưởng tiêu diệt lệ quỷ: Điểm tích lũy x150, điểm kinh nghiệm x100, vô đạo cụ rơi xuống. Đề nghị ưu tiên chọn thu phục. ] `sim=0.7662; han=0; modern=0; quote=True; digits=True`
- current: 【Phần thưởng thu phục lệ quỷ: Điểm tích lũy x300, điểm kinh nghiệm x300, đạo cụ ngẫu nhiên x1.】 Phần thưởng tiêu diệt lệ quỷ: Điểm tích lũy x150, điểm kinh nghiệm x100, vô đạo cụ rơi xuống. Đề nghị ưu tiên chọn thu phục. ] `sim=0.7638; han=0; modern=0; quote=True; digits=True`
- teacher_v2: 【Phần thưởng thu phục lệ quỷ: Điểm tích lũy x300, điểm kinh nghiệm x300, đạo cụ ngẫu nhiên x1. Phần thưởng tiêu diệt lệ quỷ: Điểm tích lũy x150, điểm kinh nghiệm x100, vô đạo cụ rơi xuống. Đề nghị ưu tiên chọn thu phục. ] `sim=0.7662; han=0; modern=0; quote=True; digits=True`

## 86. [game_english] game_english

- ZH: “backflow,你是个外挂狗，以后不要再来我们服务器了，你自己滚吧，以后来一次我们踢一次。”Crazy少爷气急败坏地在公共语音频道说道。
- Tham chiếu: “backflow, ngươi đúng là thằng chó dùng hack. Sau này đừng quay lại server của bọn ta; tự cút đi. Còn tới lần nào, bọn ta đá lần ấy.” Crazy thiếu gia tức tối nói trên kênh thoại công cộng.
- base: "Backflow, ngươi là chó ngoại quải, sau này đừng đến máy chủ của chúng ta nữa, ngươi tự cút đi, sau này đến một lần chúng ta đá một lần." Thiếu gia Crazy tức giận nói trên kênh tiếng công cộng. `sim=0.6159; han=0; modern=0; quote=True; digits=True`
- current: “Backflow, ngươi là chó ngoại quải, sau này đừng đến máy chủ của chúng ta nữa, ngươi tự cút đi, sau này đến một lần chúng ta đá một lần.” Thiếu gia Crazy tức giận nói trên kênh tiếng công cộng. `sim=0.6291; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Backflow, ngươi là chó ngoại quải, sau này đừng đến máy chủ của chúng ta nữa, ngươi tự cút đi, sau này đến một lần chúng ta đá một lần.” Thiếu gia Crazy tức giận nói trong kênh tiếng công cộng. `sim=0.6205; han=0; modern=0; quote=True; digits=True`

## 87. [game_english] game_english

- ZH: 在2015年底，刘风在网络上观看了SL i-League StarSeries XIV 中国区总决赛的实况直播。在前世刘风并没有关注这场大赛。
- Tham chiếu: Cuối năm 2015, Lưu Phong xem trực tiếp trận chung kết khu vực Trung Quốc của SL i-League StarSeries XIV trên mạng. Ở kiếp trước, hắn không để ý giải đấu này.
- base: Cuối năm 2015, Lưu Phong đã xem trực tiếp cuộc thi chung kết khu Trung Quốc trên mạng SL. i-Leagague Starseries XIV trên mạng. Ở kiếp trước, Lưu Phong cũng không chú ý đến trận đại hội này. `sim=0.7842; han=0; modern=0; quote=True; digits=True`
- current: Cuối năm 2015, Lưu Phong đã xem trực tiếp trận chung kết khu vực Trung Quốc trên mạng SL i-Leagague Starseries XIV. Ở kiếp trước, Lưu Phong cũng không để ý đến trận đại hội này. `sim=0.8134; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Cuối năm 2015, Lưu Phong đã xem trực tiếp về trận chung kết khu Trung Quốc trên mạng SLi-Leagague Starseries XIV. Ở kiếp trước, Lưu Phong không hề chú ý đến cuộc thi lớn này. `sim=0.7744; han=0; modern=0; quote=True; digits=True`

## 88. [game_english] game_english

- ZH: 而且不止是战队队员阵容实力无比强悍，在之前的季中邀请赛上，也正是god战队在决赛中击败了韩国ogn联赛的顶尖队伍fate战队，拿下了那座世界冠军奖杯。
- Tham chiếu: Không chỉ đội hình cực mạnh, ở giải Mid-Season Invitational trước đó, đội god đã đánh bại đội fate hàng đầu của giải OGN Hàn Quốc trong trận chung kết để giành cúp vô địch thế giới.
- base: Hơn nữa không chỉ đội ngũ đội viên chiến đội có thực lực vô cùng mạnh mẽ, mà trong kỳ thi mời trước đó, cũng chính là đội God đã đánh bại đội ngũ đỉnh cao của giải đấu Ogn Hàn Quốc trong trận chung kết, giành được chiếc cúp vô địch thế giới đó. `sim=0.6567; han=0; modern=0; quote=True; digits=True`
- current: Hơn nữa, không chỉ đội hình của đội tuyển có thực lực vô cùng mạnh mẽ, mà trong kỳ thi mời trước đó, cũng chính là đội God đã đánh bại đội ngũ đỉnh cao của giải đấu Ogn Hàn Quốc trong trận chung kết, giành được chiếc cúp vô địch thế giới đó. `sim=0.6727; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Hơn nữa, không chỉ đội ngũ đội viên trong đội có thực lực vô cùng mạnh mẽ, mà ngay cả đội God cũng đã đánh bại đội ngũ đỉnh cao của giải đấu Ogn Hàn Quốc trong trận chung kết, giành được chiếc cúp quán quân thế giới đó. `sim=0.5823; han=0; modern=0; quote=True; digits=True`

## 89. [game_english] game_english

- ZH: 声称“我的使命才刚开始”的月光背锅出走，管理层把宝都押在赛训总监张角上，期望他在来年的春季赛能够扛起大旗，Make AG Great Again（让AG再度伟大）。
- Tham chiếu: Nguyệt Quang, người từng nói “Sứ mệnh của ta mới bắt đầu”, đã gánh tiếng xấu rồi rời đi. Ban lãnh đạo dồn mọi hy vọng vào tổng giám sát huấn luyện Trương Giác, mong hắn gánh vác trọng trách ở mùa xuân năm sau: Make AG Great Again — để AG lại vĩ đại.
- base: Ánh trăng tuyên bố "Sứ mệnh của tôi mới chỉ bắt đầu" đã đổ sông đổ bể, ban quản lý đặt cược tất cả vào giám đốc huấn luyện thi đấu Trương Giác, hy vọng anh ta có thể dựng được lá cờ lớn trong giải mùa xuân năm sau, Make AGGreat Again (để AG lại vĩ đại). `sim=0.5473; han=0; modern=1; quote=True; digits=True`
- current: Nàng tuyên bố "Sứ mệnh của ta mới chỉ bắt đầu" đã gánh nồi bỏ đi, ban quản lý đặt tất cả bảo bối lên giám đốc huấn luyện Trương Giác, hy vọng hắn có thể gánh vác đại kỳ trong giải mùa xuân năm sau, Make AGGreat Again (Để AG lại vĩ đại). `sim=0.6508; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Ánh trăng tuyên bố “Sứ mệnh của ta vừa mới bắt đầu” đã đổ sông đổ bể, ban quản lý đặt cược tất cả vào giám đốc huấn luyện thi đấu Trương Giác, hy vọng hắn có thể dựng được lá cờ lớn trong giải mùa xuân năm sau, Make AGreat Again (để AG một lần nữa vĩ đại). `sim=0.5852; han=0; modern=0; quote=True; digits=True`

## 90. [game_english] game_english

- ZH: Mafa教练点了点头，他开局除了看Ning王刷野速度和Theshy的一级上线的落位，补眼情况，其他时间都和助理教练一直盯着看下路，这可是这一局训练赛进行的关键他这个，IG的痛点问题也是这个。
- Tham chiếu: Huấn luyện viên Mafa gật đầu. Từ đầu trận, ngoài việc quan sát tốc độ đi rừng của Ning và vị trí lên đường cấp một cùng tình hình cắm mắt của TheShy, ông cùng trợ lý luôn theo dõi đường dưới. Đây là then chốt của ván đấu tập này, cũng là điểm yếu của IG.
- base: Huấn luyện viên Mafa gật đầu, ngoài việc xem tốc độ quét dã của Ning Vương và vị trí hạ cánh cấp một của Theshy, để bù mắt, thời gian còn lại đều đang theo dõi và huấn luyện viên trợ lý nhìn đường phía dưới, đây là mấu chốt của vòng huấn luyện này. Vấn đề đau của IG cũng là như vậy. `sim=0.5455; han=0; modern=0; quote=True; digits=True`
- current: Huấn luyện viên Mafa gật đầu, ngoài việc xem tốc độ quét dã của Ning Vương và vị trí hạ cánh cấp một của Theshy, để bù mắt, thời gian còn lại đều luôn theo dõi và huấn luyện viên trợ lý nhìn đường dưới, đây chính là mấu chốt của vòng huấn luyện này. Vấn đề đau của IG cũng là như vậy. `sim=0.5728; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Huấn luyện viên Mafa gật đầu, ngoài việc xem tốc độ cày dã của Ning và vị trí hạ cánh của Theshy, để bù mắt, thời gian còn lại hắn vẫn luôn theo dõi và huấn luyện viên trợ lý theo dõi đường lui, đây là mấu chốt của vòng huấn luyện này. Vấn đề đau của IG cũng là như vậy. `sim=0.5553; han=0; modern=0; quote=True; digits=True`

## 91. [game_english] game_english

- ZH: 张龙大步而来，眼中绽放喜色：“Very Good！虽然没有找到，但找到一头Boss也不错，哪个小队发现的？”
- Tham chiếu: Trương Long sải bước tới, mắt ánh lên niềm vui: “Very Good! Tuy chưa tìm được thứ cần tìm, nhưng gặp được một Boss cũng không tệ. Đội nào phát hiện ra?”
- base: Trương Long bước nhanh tới, trong mắt bừng sáng vui mừng: "Very Good! Tuy không tìm thấy, nhưng tìm được một Boss cũng tốt, tiểu đội nào phát hiện vậy?" `sim=0.6721; han=0; modern=0; quote=True; digits=True`
- current: Trương Long bước nhanh tới, trong mắt bừng sáng vui mừng: "Very Good! Tuy không tìm thấy, nhưng tìm được một con Boss cũng không tệ, đội nào phát hiện?" `sim=0.6639; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Trương Long sải bước đi tới, trong mắt bừng lên vẻ vui mừng: “Very Good! Tuy không tìm thấy, nhưng tìm được một Boss cũng không tệ, đội nào phát hiện ra vậy?” `sim=0.7854; han=0; modern=0; quote=True; digits=True`

## 92. [game_english] game_english

- ZH: Gala接过小狗的接力棒成为AD，将是RNG在明年S11赛季的最大王牌，只是目前还需磨练。
- Tham chiếu: Gala tiếp nhận vị trí AD từ Tiểu Cẩu, sẽ là quân bài lớn nhất của RNG ở mùa S11 năm sau, chỉ là hiện giờ vẫn cần rèn giũa thêm.
- base: Gala nhận lấy gậy tiếp sức của chú cún để trở thành AD, sẽ là át chủ bài lớn nhất của RNG trong mùa S11 năm sau, chỉ là hiện tại vẫn cần rèn luyện. `sim=0.6286; han=0; modern=0; quote=True; digits=True`
- current: Gala nhận lấy gậy tiếp sức của chú chó nhỏ để trở thành AD, sẽ là át chủ bài lớn nhất của RNG trong mùa giải S11 năm sau, chỉ là hiện tại vẫn cần rèn luyện. `sim=0.6267; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Gala nhận lấy gậy tiếp sức của chú chó nhỏ để trở thành AD, sẽ là át chủ bài lớn nhất của RNG trong mùa S11 năm sau, chỉ là hiện tại vẫn cần rèn luyện. `sim=0.6385; han=0; modern=0; quote=True; digits=True`

## 93. [game_english] game_english

- ZH: GG-Captain，替补狙击手，以精准的长距离压制着称，在次级联赛的 MVP 榜上常年排名前三。
- Tham chiếu: GG-Captain, tay bắn tỉa dự bị, nổi tiếng nhờ khả năng áp chế tầm xa chính xác; ở giải hạng dưới, hắn thường xuyên nằm trong top ba bảng MVP.
- base: GG-Captain, tay bắn tỉa dự bị, nổi tiếng với mức độ dài chính xác, xếp hạng top 3 trên bảng MVP của giải đấu cấp hai. `sim=0.5616; han=0; modern=0; quote=True; digits=False`
- current: GG-Cptain, xạ thủ dự bị, nổi tiếng với khả năng áp chế khoảng cách dài chính xác, trong top 3 bảng xếp hạng MVP của giải thứ cấp. `sim=0.5728; han=0; modern=0; quote=True; digits=False`
- teacher_v2: GG-Captain, tay bắn tỉa dự bị, nổi tiếng với mức độ dài chính xác, xếp hạng top 3 trên bảng MVP của giải đấu cấp hai. `sim=0.5616; han=0; modern=0; quote=True; digits=False`

## 94. [game_english] game_english

- ZH: 最后peek 击杀Uki，跃上二楼击杀zhoking的操作，就是放到现在的职业赛场，也是极为罕见的。
- Tham chiếu: Pha peek cuối cùng hạ Uki rồi nhảy lên tầng hai hạ zhoking, đến cả ở đấu trường chuyên nghiệp hiện nay cũng cực kỳ hiếm thấy.
- base: Cuối cùng, thao tác Peeek tiêu diệt Uke, nhảy lên lầu hai tiêu diệt Zhoking, dù đặt ở sân thi đấu chuyên nghiệp hiện nay cũng cực kỳ hiếm thấy. `sim=0.6761; han=0; modern=0; quote=True; digits=True`
- current: Cuối cùng Peeek tiêu diệt Uki, nhảy lên tầng hai tiêu diệt Zhoking, ngay cả khi đặt ở sân thi đấu chuyên nghiệp hiện tại cũng cực kỳ hiếm thấy. `sim=0.6948; han=0; modern=0; quote=True; digits=True`
- teacher_v2: Cuối cùng, thao tác Peeek giết Uke, nhảy lên lầu hai tiêu diệt Zhoking, dù đặt ở sàn đấu chuyên nghiệp hiện nay cũng cực kỳ hiếm thấy. `sim=0.6990; han=0; modern=0; quote=True; digits=True`

## 95. [game_english] game_english

- ZH: “你好啊，江苏NIKO，名字不能白叫，一会要carry起来哦。”captainMo不失亲和力的说道。
- Tham chiếu: “Chào nhé, Giang Tô NIKO. Đã mang tên ấy thì đừng để uổng, lát nữa phải carry lên đấy.” captainMo vẫn thân thiện nói.
- base: "Chào cậu, Giang Tô NIKO, tên không thể gọi vô ích, lát nữa phải carry lên nhé." Captain Mo nói với giọng không mất đi sự thân thiện. `sim=0.6200; han=0; modern=1; quote=True; digits=True`
- current: "Chào ngươi, Giang Tô NIKO, tên không thể gọi vô ích, lát nữa phải Carry dậy nhé." `sim=0.5000; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Chào anh, Giang Tô NIKO, tên không thể gọi vô ích, lát nữa phải carry lên nhé.” Captain Mo nói một cách không mất đi sự thân thiện. `sim=0.6533; han=0; modern=0; quote=True; digits=True`

## 96. [game_english] game_english

- ZH: “请IG.Rookie选手和IG.K'aiVen选手两分钟后，前往后台接受赛后采访。采访之后还需要进行咱们LPL赛区的出征仪式，请所有的参赛选手和主教练做好准备哈。”
- Tham chiếu: “Hai phút nữa, mời tuyển thủ IG.Rookie và IG.K'aiVen tới hậu trường nhận phỏng vấn sau trận. Sau phỏng vấn còn lễ xuất chinh của LPL, mời toàn bộ tuyển thủ và huấn luyện viên trưởng chuẩn bị.”
- base: "Xin mời thí sinh IG.Rookie và thí sinh IG.K'aiVen hai phút sau, sẽ đến hậu đài để phỏng vấn sau trận đấu. Sau khi phỏng vấn còn cần tiến hành nghi thức xuất chinh khu vực LPL của chúng ta, xin tất cả thí sinh và giám mục hãy chuẩn bị sẵn sàng nhé." `sim=0.5242; han=0; modern=0; quote=True; digits=True`
- current: "Mời tuyển thủ IG.Rookie và tuyển thủ IG.K'aiVen hai phút nữa sẽ đến hậu trường để phỏng vấn sau trận đấu. Sau khi phỏng vấn còn phải tiến hành nghi thức xuất chinh của khu vực LPL của chúng ta, xin tất cả tuyển thủ và huấn luyện viên giám đốc chuẩn bị sẵn sàng nhé." `sim=0.6649; han=0; modern=0; quote=True; digits=True`
- teacher_v2: “Xin mời thí sinh IG.Rookie và thí sinh IG.K'aiVen hai phút sau sẽ đến hậu đài để phỏng vấn sau trận đấu. Sau khi phỏng vấn còn phải tiến hành nghi thức xuất chinh khu vực LPL của chúng ta, xin mời tất cả thí sinh và giám mục tập luyện chuẩn bị sẵn sàng nhé.” `sim=0.5571; han=0; modern=0; quote=True; digits=True`

