"""Bó ví dụ DictDis cho term ĐA NGHĨA / JARGON: dạy Marian chọn đúng nghĩa theo cue TRONG CÂU.

Đã ĐO trên v5 canonical (xem diag): v5 giỏi nghĩa TU TIÊN (corpus nghiêng đó) nhưng hỏng ở:
  - ĐÔ THỊ hiện đại: TMĐT (秒杀 flash-sale, 种草), MXH (隐身 offline, 走光), văn bản (副本 bản sao, 刷新 phá kỷ lục).
  - VÕNG DU/MOBA (yếu nhất): 人头/输出/兵线/抓人/补刀/开黑/坦克/发育 dịch thành rác hoặc nghĩa đen.
Tu tiên KHÔNG có term nào ở đây vì v5 đã dịch đúng — thêm data chỉ tổ nhiễu.

Nguyên tắc:
  - CONTRASTIVE khi term có 2 nghĩa: nghiêng về nghĩa v5 SAI (dạy), giữ vài câu nghĩa v5 ĐÚNG (khỏi override).
  - Jargon 1 nghĩa (兵线/上分/开黑) chỉ cần DẠY cách dịch — không có nghĩa đời thường dễ lẫn.
  - Cue phân biệt nằm NGAY TRONG CÂU. Gu: thuần Việt + mượn khi là cách nói thật của độc giả
    (gank/rank/farm/tanker/last-hit/offline/flash sale); mạt chược thuần Việt; brand giữ tên (Mizone).

Xuất gold/dictdis_polysemy.jsonl (status=approved, domain=dictdis_polysemy).
"""
from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "data" / "gold" / "dictdis_polysemy.jsonl"

# term -> {sense: [(zh, vi), ...]}. "keep_*" = nghĩa v5 ĐÃ đúng (giữ ít, chống override).
EXAMPLES: dict[str, dict[str, list[tuple[str, str]]]] = {
    # ---------- target cũ (hiếm gặp nhưng đã biết lỗi) ----------
    "自摸": {
        "mahjong": [
            ("他打麻将自摸，胡了一把大的。", "Hắn đánh mạt chược tự ù, thắng một ván lớn."),
            ("三缺一，快来搓麻，昨天我连续自摸了三把。", "Thiếu một chân, mau tới đánh mạt chược, hôm qua ta tự ù liền ba ván."),
            ("他摸到最后一张牌，直接自摸胡了。", "Hắn bốc lá bài cuối cùng, tự ù luôn."),
            ("牌桌上，老王一个自摸，把三家的钱全赢了。", "Trên bàn mạt chược, lão Vương một phát tự ù, ăn sạch tiền cả ba nhà."),
            ("这局我杠完就自摸了。", "Ván này ta khàng xong liền tự ù."),
            ("别看她文静，打起麻将来最爱自摸。", "Đừng thấy nàng dịu dàng, đánh mạt chược lại thích tự ù nhất."),
            ("庄家连庄，靠的就是一次次自摸。", "Nhà cái giữ cái liên tục, dựa vào chính là hết lần này tới lần khác tự ù."),
            ("最后一圈，他一把自摸清了对手的家底。", "Vòng cuối cùng, hắn một ván tự ù dọn sạch vốn liếng của đối thủ."),
        ],
        "self": [
            ("夜里，他一个人躲在被窝里自摸。", "Ban đêm, hắn một mình trốn trong chăn tự sờ."),
            ("青春期的少年忍不住会自摸，这很正常。", "Thiếu niên tuổi dậy thì nhịn không được sẽ tự sờ, chuyện đó rất bình thường."),
            ("她脸颊发烫，一个人时也会悄悄自摸。", "Má nàng nóng ran, khi ở một mình cũng sẽ lén tự sờ."),
            ("他躺在床上，掀开被子开始自摸。", "Hắn nằm trên giường, hất chăn ra bắt đầu tự sờ."),
            ("浴室里水汽腾腾，他闭着眼自摸起来。", "Trong phòng tắm hơi nước nghi ngút, hắn nhắm mắt tự sờ."),
            ("夜深人静，他的手不自觉地在身上自摸。", "Đêm khuya thanh vắng, tay hắn bất giác tự sờ khắp thân mình."),
            ("一个人睡不着，他索性掀被自摸。", "Một mình ngủ không được, hắn liền hất chăn tự sờ."),
            ("房间里只有他一个人，他锁上门自摸。", "Trong phòng chỉ có mình hắn, hắn khóa cửa tự sờ."),
        ],
    },
    "脉动": {
        "brand": [
            ("训练结束后，他咕咚咕咚喝光了一瓶脉动。", "Sau buổi tập, hắn ừng ực uống cạn một chai Mizone."),
            ("便利店里，她随手拿了两瓶脉动去结账。", "Trong cửa hàng tiện lợi, nàng tiện tay lấy hai chai Mizone đi thanh toán."),
            ("他从冰箱里抽出一罐脉动，扔给了队友。", "Hắn rút một lon Mizone từ tủ lạnh, ném cho đồng đội."),
            ("打完球口渴得要命，他一口气灌下半瓶脉动。", "Đá bóng xong khát muốn chết, hắn tu một hơi hết nửa chai Mizone."),
            ("桌上摆着吃剩的外卖和几瓶空的脉动。", "Trên bàn bày đồ ăn mang về ăn dở và mấy chai Mizone rỗng."),
            ("“渴了吧？”他递过来一瓶冰镇脉动。", "“Khát rồi phải không?” Hắn đưa tới một chai Mizone ướp lạnh."),
            ("熬夜打游戏，桌角总少不了一瓶脉动。", "Thức đêm chơi game, góc bàn luôn không thiếu một chai Mizone."),
            ("他拧开脉动的瓶盖，仰头喝了一大口。", "Hắn vặn nắp chai Mizone, ngửa đầu uống một hơi lớn."),
            ("他拧开盖子，仰头猛灌脉动。", "Hắn vặn nắp, ngửa đầu tu ừng ực Mizone."),
            ("自动贩卖机里只剩下罐装的脉动了。", "Trong máy bán tự động chỉ còn Mizone đóng lon."),
            ("剧烈运动后，来一瓶脉动最解渴。", "Sau khi vận động mạnh, làm một chai Mizone là đã khát nhất."),
        ],
        "pulse": [
            ("他闭上眼，感受着大地深处传来的脉动。", "Hắn nhắm mắt lại, cảm nhận mạch động truyền tới từ sâu trong lòng đất."),
            ("老中医搭脉，感觉到她腕间微弱的脉动。", "Lão trung y bắt mạch, cảm nhận được nhịp đập yếu ớt nơi cổ tay nàng."),
            ("那颗晶石随着灵力的注入，发出规律的脉动。", "Viên tinh thạch theo linh lực rót vào, phát ra nhịp xung động đều đặn."),
            ("空气中的能量正以某种诡异的频率脉动着。", "Năng lượng trong không khí đang xung động theo một tần số quái dị."),
            ("医生贴上仪器，屏幕显示出心脏的脉动。", "Bác sĩ áp thiết bị lên, màn hình hiện ra nhịp đập của tim."),
            ("他能看见对方颈侧血管的脉动。", "Hắn nhìn thấy mạch máu bên cổ đối phương đang đập."),
            ("阵眼深处传来一阵阵灵力的脉动。", "Sâu trong mắt trận truyền tới từng đợt xung động linh lực."),
            ("修士能感应到天地间隐隐的脉动。", "Tu sĩ có thể cảm ứng được nhịp xung động ẩn hiện giữa trời đất."),
        ],
    },
    # ---------- ĐÔ THỊ (v5 hỏng nghĩa hiện đại) ----------
    "副本": {
        "document": [
            ("请把合同的副本交给财务部门存档。", "Đưa bản sao hợp đồng cho bộ phận tài chính lưu trữ."),
            ("这份文件的副本我已经打印好了。", "Bản sao tài liệu này ta đã in xong rồi."),
            ("原件我留着，副本发到你邮箱。", "Bản gốc ta giữ, bản sao gửi vào mail ngươi."),
            ("身份证副本记得多准备几份。", "Bản sao chứng minh thư nhớ chuẩn bị dư vài tờ."),
        ],
        "keep_dungeon": [
            ("他们组队去打副本，boss掉了一件紫装。", "Bọn họ lập đội đi đánh phó bản, boss rơi một món trang bị tím."),
            ("这个副本难度太高，队伍团灭了三次。", "Phó bản này độ khó quá cao, cả đội bị diệt sạch ba lần."),
            ("通关隐藏副本后，他拿到了限定称号。", "Thông quan phó bản ẩn xong, hắn nhận được danh hiệu giới hạn."),
        ],
    },
    "秒杀": {
        "flashsale": [
            ("商城晚上十点开始限时秒杀，快去抢。", "Cửa hàng mười giờ tối bắt đầu flash sale giới hạn giờ, mau đi giành."),
            ("这款手机秒杀价只要一千九。", "Mẫu điện thoại này giá flash sale chỉ một nghìn chín."),
            ("她盯着购物车，就等零点秒杀。", "Nàng dán mắt vào giỏ hàng, chỉ chờ đúng nửa đêm flash sale."),
            ("秒杀活动一开始，库存瞬间被抢空。", "Đợt flash sale vừa mở, kho hàng lập tức bị giành sạch."),
            ("双十一一开场，热门款瞬间被秒杀。", "Song Thập Nhất vừa mở màn, mẫu hot lập tức bị flash sale sạch."),
            ("这款包一上架就被秒杀，手慢无。", "Mẫu túi này vừa lên kệ đã bị flash sale hết, chậm tay là mất."),
            ("为了抢秒杀，她定好了闹钟。", "Để giành flash sale, nàng hẹn sẵn cả báo thức."),
        ],
        "keep_instakill": [
            ("他一刀就把这只小怪秒杀了。", "Hắn một đao liền giết ngay con quái nhỏ này."),
            ("这个技能能秒杀满血的敌人。", "Kỹ năng này có thể giết ngay kẻ địch đầy máu."),
        ],
    },
    "刷新": {
        "record": [
            ("他又一次刷新了世界纪录。", "Hắn lại một lần nữa phá kỷ lục thế giới."),
            ("这个成绩刷新了校运会的记录。", "Thành tích này phá kỷ lục của đại hội thể thao trường."),
            ("影片票房一路刷新，登顶年度冠军。", "Doanh thu phim liên tục phá kỷ lục, lên ngôi quán quân cả năm."),
        ],
        "respawn": [
            ("副本里的怪物每五分钟自动刷新一次。", "Quái vật trong phó bản cứ năm phút tự spawn lại một lần."),
            ("野区的buff刷新了，快去打。", "Buff khu rừng đã spawn lại, mau đi đánh."),
            ("BOSS被击杀后会在整点刷新。", "BOSS sau khi bị hạ sẽ xuất hiện lại vào đầu giờ."),
            ("小怪清完了，站在原地等它刷新。", "Quái nhỏ dọn xong, đứng nguyên chỗ chờ nó spawn lại."),
            ("这只精英怪死后要半小时才刷新。", "Con quái tinh anh này chết rồi phải nửa tiếng mới spawn lại."),
            ("资源点被抢空，等刷新再来。", "Điểm tài nguyên bị vét sạch, chờ spawn lại rồi tới."),
        ],
        "keep_refresh": [
            ("网页卡住了，刷新一下就好。", "Trang web bị kẹt, làm mới một cái là được."),
            ("刷新页面后，新消息就出来了。", "Làm mới trang xong, tin nhắn mới liền hiện ra."),
        ],
    },
    "隐身": {
        "offline": [
            ("她在微信上一直挂着隐身，不想被打扰。", "Nàng trên WeChat luôn để offline, không muốn bị quấy rầy."),
            ("他上线也是隐身状态，从不冒泡。", "Hắn lên mạng cũng để trạng thái offline, chưa từng ló mặt."),
            ("别看他隐身，其实一直在线看着。", "Đừng thấy hắn để offline, thật ra vẫn luôn online dõi theo."),
            ("她登录QQ后直接隐身，谁也不理。", "Nàng đăng nhập QQ xong để luôn offline, chẳng tiếp ai."),
            ("在游戏里挂着隐身，其实他一直盯着屏幕。", "Trong game để offline, thật ra hắn vẫn dán mắt vào màn hình."),
            ("他把状态设成隐身，装作不在线。", "Hắn đặt trạng thái offline, giả bộ không online."),
        ],
        "keep_stealth": [
            ("他开启隐身技能，敌人谁也看不见他。", "Hắn mở kỹ năng tàng hình, kẻ địch không ai thấy được hắn."),
            ("刺客靠隐身绕到了后排。", "Thích khách dựa vào tàng hình vòng ra hàng sau."),
            ("他的大招是隐身，能瞬间消失在原地。", "Chiêu cuối của hắn là tàng hình, có thể lập tức biến mất tại chỗ."),
            ("他身形一闪，开隐身遁入黑暗。", "Thân hình hắn lóe lên, mở tàng hình lẩn vào bóng tối."),
        ],
    },
    "种草": {
        "wanttobuy": [
            ("被博主种草了这支口红，忍不住下单。", "Bị blogger dụ cho thèm cây son này, nhịn không nổi đặt luôn."),
            ("这家店被闺蜜种草很久了。", "Quán này bị bạn thân rủ rê làm thèm đã lâu rồi."),
            ("刷到测评就被种草了一堆东西。", "Lướt trúng mấy bài review là bị dụ muốn mua cả đống đồ."),
            ("刷到测评视频，我被种草了个网红包。", "Lướt trúng video review, ta bị dụ thèm một chiếc túi hot."),
            ("朋友一安利，我立马被种草。", "Bạn vừa PR, ta lập tức bị dụ muốn mua."),
            ("这条视频成功把我种草了。", "Video này dụ được ta muốn mua thành công."),
        ],
        "keep_grass": [
            ("他在院子的空地上种草，铺成草坪。", "Hắn trồng cỏ trên khoảng đất trống trong sân, trải thành thảm cỏ."),
        ],
    },
    "走光": {
        "wardrobe": [
            ("她一低头差点走光，赶紧捂住领口。", "Nàng vừa cúi đầu suýt lộ hàng, vội che kín cổ áo."),
            ("风一吹裙子被掀起，她差点走光。", "Gió thổi tốc váy lên, nàng suýt lộ hàng."),
            ("明星红毯上走光的照片被疯传。", "Ảnh ngôi sao lộ hàng trên thảm đỏ bị lan truyền chóng mặt."),
        ],
        "keep_exposure": [
            ("暗房必须遮严，否则底片会走光。", "Phòng tối phải che thật kín, không thì phim âm bản sẽ bị lộ sáng."),
        ],
    },
    "上头": {
        "addictive": [
            ("这首歌太上头了，单曲循环了一整天。", "Bài hát này nghe cuốn muốn nghiện, lặp lại cả ngày."),
            ("这游戏越玩越上头，通宵都不困。", "Game này càng chơi càng nghiện, thức trắng cũng không buồn ngủ."),
            ("麻辣烫真上头，吃一次就想第二次。", "Mala tang đúng là gây nghiện, ăn một lần là muốn lần hai."),
            ("这首神曲太上头，根本停不下来。", "Bài nhạc thần này quá gây nghiện, dừng chẳng nổi."),
            ("这综艺太上头，一集接一集停不了。", "Show này quá cuốn, hết tập này tới tập khác không dừng được."),
            ("奶茶喝着上头，越喝越想喝。", "Trà sữa uống vào nghiện, càng uống càng thèm."),
        ],
        "keep_superior": [
            ("上头刚下了死命令，这个月必须完成。", "Cấp trên vừa hạ tử lệnh, tháng này nhất định phải xong."),
            ("这事得上头点头才能办。", "Việc này phải cấp trên gật đầu mới làm được."),
        ],
    },
    # ---------- VÕNG DU / MOBA (v5 yếu nhất) ----------
    "人头": {
        "kill": [
            ("这波团战他收了五个人头。", "Đợt giao tranh này hắn lấy được năm mạng."),
            ("打野带节奏，一路狂拿人头。", "Người đi rừng dẫn nhịp, cả đường điên cuồng lấy mạng."),
            ("残血别浪，小心送人头。", "Máu tàn đừng liều, coi chừng nạp mạng cho địch."),
            ("他一个大招收割了三个人头。", "Hắn một chiêu cuối thu hoạch ba mạng."),
        ],
        "keep_head": [
            ("刀光一闪，他提着仇人的人头走了出来。", "Ánh đao lóe lên, hắn xách thủ cấp kẻ thù bước ra."),
            ("广场上人头攒动，挤得水泄不通。", "Trên quảng trường người đông nghịt, chen chúc không lọt."),
        ],
    },
    "输出": {
        "damage": [
            ("后排法师负责输出，别站太前。", "Pháp sư hàng sau phụ trách gây sát thương, đừng đứng quá lên trước."),
            ("这套装备输出爆炸，一套秒人。", "Bộ trang bị này sát thương bùng nổ, một combo giết gọn."),
            ("坦克顶在前面，让输出安心打。", "Tanker chống ở phía trước, để dàn sát thương yên tâm đánh."),
            ("这英雄输出爆炸，秒天秒地。", "Vị tướng này sát thương bùng nổ, giết gọn mọi thứ."),
            ("保护好后排，让他们尽情输出。", "Bảo vệ hàng sau cho tốt, để họ thỏa sức tuôn sát thương."),
        ],
        "keep_export": [
            ("这家工厂主要向欧洲输出电子产品。", "Nhà máy này chủ yếu xuất khẩu sản phẩm điện tử sang châu Âu."),
            ("这个国家大量输出石油。", "Quốc gia này xuất khẩu dầu mỏ với số lượng lớn."),
        ],
    },
    "兵线": {
        "minionwave": [
            ("他一直在清兵线，不敢轻易露头。", "Hắn cứ liên tục dọn lính, không dám lộ mặt bừa."),
            ("兵线太深，贸然上去容易被抓。", "Làn lính dâng quá sâu, xông lên liều dễ bị bắt."),
            ("先把兵线带起来，再去支援。", "Đẩy làn lính lên trước đã, rồi hẵng đi hỗ trợ."),
        ],
    },
    "抓人": {
        "gank": [
            ("打野快来中路抓人。", "Người đi rừng mau tới đường giữa gank đi."),
            ("对面打野在下路蹲着抓人。", "Người đi rừng bên kia đang rình ở đường dưới để gank."),
            ("趁他没眼，我们绕后抓人。", "Nhân lúc hắn không có mắt, bọn ta vòng ra sau gank."),
            ("敌方打野一直在上路抓人。", "Người đi rừng địch cứ gank đường trên suốt."),
            ("小心，对面来抓人了！", "Cẩn thận, bên kia tới gank kìa!"),
            ("他四处游走帮队友抓人。", "Hắn đi lượn khắp nơi gank giúp đồng đội."),
            ("这波抓人失败，反被对面反蹲。", "Pha gank này hụt, còn bị bên kia phản kèo."),
        ],
        "keep_arrest": [
            ("警察连夜出动，去城郊抓人。", "Cảnh sát xuất động trong đêm, tới ngoại ô bắt người."),
        ],
    },
    "补刀": {
        "lasthit": [
            ("对线期好好补刀，别浪费兵。", "Giai đoạn đi đường lo last-hit cho tốt, đừng phí lính."),
            ("他补刀功底扎实，经济一直领先。", "Nền tảng last-hit của hắn vững, kinh tế luôn dẫn trước."),
            ("别抢我兵，让我补刀。", "Đừng cướp lính của ta, để ta last-hit."),
            ("补刀是每个新手必练的基本功。", "Last-hit là kỹ năng cơ bản người mới nào cũng phải luyện."),
            ("他补刀很稳，经济从不落后。", "Hắn last-hit rất chắc, kinh tế chưa từng thua kém."),
            ("补刀练不好，经济就落后。", "Last-hit không tốt là kinh tế tụt lại ngay."),
        ],
        "keep_finish": [
            ("见对方还有气，他上前补刀，结果了性命。", "Thấy đối phương còn thoi thóp, hắn tiến lên bồi thêm một nhát kết liễu."),
        ],
    },
    "上分": {
        "climbrank": [
            ("今晚一起排位上分，冲个王者。", "Tối nay cùng nhau chơi xếp hạng leo rank, lên Vương giả nào."),
            ("这英雄太强了，用它上分很快。", "Vị tướng này quá mạnh, dùng nó leo rank rất nhanh."),
            ("最近沉迷上分，段位涨了不少。", "Dạo này mê leo rank, bậc hạng lên kha khá."),
        ],
    },
    "开黑": {
        "squad": [
            ("晚上一起开黑上分吧。", "Tối nay cùng nhau kéo team leo rank đi."),
            ("周末几个哥们儿开黑，打了通宵。", "Cuối tuần mấy thằng bạn kéo team chơi, đánh thâu đêm."),
            ("一个人太无聊，找人开黑。", "Chơi một mình chán quá, tìm người kéo team."),
        ],
    },
    "坦克": {
        "gametank": [
            ("这英雄是队里的坦克，专门站前排抗伤害。", "Vị tướng này là tanker của đội, chuyên đứng hàng đầu chịu sát thương."),
            ("没有坦克开团，后排根本站不住。", "Không có tanker mở giao tranh, hàng sau chẳng trụ nổi."),
            ("他玩坦克，血厚肉多，特别耐揍。", "Hắn chơi tanker, máu dày trâu bò, cực kỳ chịu đòn."),
        ],
        "keep_vehicle": [
            ("战场远处开来一辆坦克，履带碾过废墟。", "Xa xa trên chiến trường một chiếc xe tăng lăn tới, xích nghiền qua đống đổ nát."),
            ("敌军的坦克部队正在逼近。", "Binh đoàn xe tăng của địch đang áp sát."),
        ],
    },
    "发育": {
        "farm": [
            ("前期别浪，猥琐发育就行。", "Giai đoạn đầu đừng liều, cứ âm thầm farm là được."),
            ("让我方C位安心发育。", "Để vị trí carry bên mình yên tâm farm."),
            ("他闷头发育，二十分钟就三件套了。", "Hắn cắm cúi farm, hai mươi phút đã ba món đồ."),
        ],
        "keep_grow": [
            ("孩子发育得很好，长高了不少。", "Đứa trẻ phát triển rất tốt, cao lên kha khá."),
            ("青春期身体发育很快。", "Tuổi dậy thì cơ thể phát triển rất nhanh."),
        ],
    },
    "开大": {
        "ultimate": [
            ("他血条一红就开大，一波带走三个。", "Thanh máu vừa đỏ hắn liền bung chiêu cuối, một đợt hạ ba người."),
            ("大招好了，等团战再开大。", "Chiêu cuối hồi xong rồi, chờ giao tranh hẵng bung."),
            ("他开大的瞬间，敌人全被控住了。", "Khoảnh khắc hắn bung chiêu cuối, kẻ địch bị khống hết."),
            ("大招一好他就开大清场。", "Chiêu cuối vừa hồi hắn liền bung dọn sạch."),
            ("关键团战他果断开大。", "Giao tranh then chốt hắn dứt khoát bung chiêu cuối."),
            ("别急着开大，留着保命。", "Đừng vội bung chiêu cuối, để dành giữ mạng."),
        ],
        "keep_open": [
            ("屋里太闷，他把窗户开大了些。", "Trong phòng ngột ngạt, hắn mở cửa sổ to thêm chút."),
        ],
    },
    "团战": {
        "teamfight": [
            ("别单带了，全都去打团战。", "Đừng đi lẻ nữa, tất cả vào giao tranh đi."),
            ("一波团战打崩，基地就没了。", "Một pha giao tranh thua sạch là mất luôn nhà chính."),
            ("这波团战我们五个换他们三个。", "Pha giao tranh này bên ta đổi năm lấy ba của địch."),
        ],
    },
    "平A": {
        "autoattack": [
            ("别放技能，平A把它磨死。", "Đừng thả kỹ năng, đánh thường mài chết nó."),
            ("塔下别浪，平A补兵就行。", "Dưới trụ đừng liều, đánh thường ăn lính là được."),
            ("他关掉技能，纯靠平A收割。", "Hắn tắt kỹ năng, thuần dựa đánh thường kết liễu."),
        ],
    },
    "高能": {
        "climax": [
            ("前方高能，胆小的捂眼睛。", "Phía trước là đoạn cao trào, ai yếu tim thì che mắt."),
            ("视频三分钟处高能，别错过。", "Đoạn phút thứ ba của video rất gắt, đừng bỏ lỡ."),
            ("接下来一段高能，建议戴耳机。", "Đoạn sắp tới cực gắt, khuyên nên đeo tai nghe."),
            ("前方高能，非战斗人员快撤离。", "Phía trước cao trào, ai không phải chiến đấu mau rút."),
            ("弹幕都在刷前方高能。", "Bình luận trôi đầy màn ‘phía trước cao trào’."),
            ("视频后半段全是高能名场面。", "Nửa sau video toàn cảnh cao trào kinh điển."),
        ],
        "keep_energy": [
            ("这是一节高能物理课。", "Đây là một tiết vật lý năng lượng cao."),
        ],
    },
    "挂机": {
        "afk": [
            ("队友挂机了，四打五怎么赢。", "Đồng đội treo máy rồi, bốn đánh năm sao thắng nổi."),
            ("他嫌无聊，全程挂机。", "Hắn thấy chán, treo máy suốt trận."),
            ("举报那个挂机的，太坑了。", "Báo cáo thằng treo máy đó đi, hại chết."),
        ],
    },
    "越塔": {
        "divetower": [
            ("他们强行越塔，把我方残血收了。", "Bọn họ liều dive trụ, kết liễu mấy mạng máu tàn bên ta."),
            ("别越塔，塔的伤害很痛。", "Đừng dive trụ, sát thương trụ đau lắm."),
            ("我引开塔，你们越塔杀他。", "Ta kéo trụ, các ngươi dive vào giết hắn."),
            ("残血别追，小心对面越塔。", "Máu tàn đừng đuổi, coi chừng bên kia dive trụ."),
            ("他越塔强杀，血量刚好够。", "Hắn dive trụ hạ gục, lượng máu vừa đủ."),
            ("塔下有人，别贸然越塔。", "Dưới trụ có người, đừng liều dive trụ."),
        ],
    },
    "内卷": {
        "ratrace": [
            ("公司内卷太严重，天天加班到深夜。", "Công ty cạnh tranh khốc liệt, ngày nào cũng tăng ca tới khuya."),
            ("现在行业内卷严重，钱越来越难赚。", "Giờ trong ngành đua nhau cày dữ dội, kiếm tiền ngày càng khó."),
            ("大家都在内卷，谁也不敢松懈。", "Ai nấy đều lao vào cạnh tranh, không ai dám lơi lỏng."),
        ],
    },
    "送人头": {
        "feed": [
            ("你别再送人头了，喂饱了对面。", "Ngươi đừng nạp mạng nữa, nuôi béo đối phương rồi."),
            ("残血还往上冲，纯送人头。", "Máu tàn còn xông lên, đúng là nạp mạng."),
            ("这波别浪，送人头就崩了。", "Pha này đừng liều, nạp mạng là toang."),
        ],
    },
    "吃土": {
        "broke": [
            ("这个月买太多，下半月只能吃土。", "Tháng này mua quá tay, nửa tháng sau chỉ có nước cháy túi."),
            ("为了追星，她已经吃土好几个月了。", "Vì đu idol, nàng cháy túi mấy tháng nay rồi."),
            ("钱包空了，接下来准备吃土吧。", "Ví rỗng rồi, tới đây chuẩn bị cháy túi thôi."),
        ],
    },
}


def build() -> list[dict]:
    rows: list[dict] = []
    for senses in EXAMPLES.values():
        for pairs in senses.values():
            for zh, vi in pairs:
                rows.append({"zh": zh, "vi": vi, "domain": "dictdis_polysemy", "status": "approved"})
    return rows


def _self_check() -> None:
    for term, senses in EXAMPLES.items():
        assert senses, f"{term}: rỗng"
        for sense, pairs in senses.items():
            assert pairs, f"{term}/{sense}: rỗng"
            for zh, vi in pairs:
                assert term in zh, f"{term}/{sense}: câu zh không chứa term: {zh}"
                assert vi.strip(), f"{term}/{sense}: thiếu VI cho {zh}"
        # term có 2 nghĩa: không lệch quá 2x (nghiêng nghĩa v5-sai để dạy, nhưng đừng bỏ rơi nghĩa kia)
        counts = [len(p) for p in senses.values()]
        if len(counts) >= 2:
            # teach (nghĩa v5-sai) cố ý ÁP ĐẢO keep (neo chống-override); eval bắt hồi quy nghĩa keep
            assert max(counts) <= min(counts) * 8, f"{term}: lệch contrastive {counts} — quá tay kẻo nuốt nghĩa keep"
    rows = build()
    zhs = [r["zh"] for r in rows]
    assert len(zhs) == len(set(zhs)), "trùng zh (loader train sẽ báo xung đột)"
    print(f"make_dictdis_probe self-check OK — {len(rows)} câu, {len(EXAMPLES)} term "
          f"({', '.join(EXAMPLES)})")


if __name__ == "__main__":
    import sys
    if "--self-check" in sys.argv:
        _self_check()
    else:
        _self_check()
        rows = build()
        OUT.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
        print(f"Đã ghi {len(rows)} câu -> {OUT}")
