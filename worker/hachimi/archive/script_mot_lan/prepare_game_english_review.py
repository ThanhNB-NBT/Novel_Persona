"""Tạo hai hàng đợi duyệt game-English, không tạo dữ liệu train đã duyệt."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

from text_clean import clean_source


ROOT = Path(__file__).parent
DATASET = ROOT / "dataset"
EXPERIMENTS = ROOT.parent / "experiments"
PREPARED = ROOT / "prepared_v1" / "game_english_review.jsonl"
CORE = ROOT / "prepared_v1" / "core_gold.jsonl"
EVAL60 = DATASET / "eval_reference_60.jsonl"
SIX_CHAPTERS = EXPERIMENTS / "hachimi_vnext_e_fullchapters.jsonl"
EVAL_OUT = DATASET / "eval_game_english_review.jsonl"
TRAIN_OUT = DATASET / "train_game_english_review_200.jsonl"
SHORTLIST_OUT = DATASET / "train_game_english_review_shortlist.jsonl"
EVAL_MD = EXPERIMENTS / "hachimi_game_english_eval_review.md"
TRAIN_MD = EXPERIMENTS / "hachimi_game_english_train_review_200.md"
SHORTLIST_MD = EXPERIMENTS / "hachimi_game_english_train_review_shortlist.md"
APPROVED_TRAIN_OUT = DATASET / "train_game_english_approved.jsonl"
LOCKED_EVAL_OUT = DATASET / "eval_game_english_locked.jsonl"
EXCLUDED_PREFIXES = ("? 韵母",)
ALLOWED_UNCHANGED_PREFIXES = ("全民领主里面",)
GAME = re.compile(
    r"(?<![A-Za-z])(?:BOSS|NPC|PK|PVP|PVE|RPG|MMORPG|VIP|ID|GM|CD|EXP|HP|MP|BUFF|"
    r"DEBUFF|DPS|AOE|AFK|KDA|LOL|DOTA|FPS|MOBA|UI|APP|SERVER|RANK|TOP|ALL[- ]?IN)(?![A-Za-z])",
    re.I,
)
LATIN = re.compile(r"(?<![A-Za-z])[A-Za-z][A-Za-z0-9_-]{2,}(?![A-Za-z])")
PRIORITY_LABELS = {"BOSS", "NPC", "CD", "BUFF", "DEBUFF", "RANK", "ID"}
MANUAL_REFERENCES = {
    "在绝大多数副本里": ("Phân biệt NPC/Boss với chỉ tiêu người chơi.", "Trong phần lớn phó bản, NPC và Boss tuyệt đối không chiếm chỉ tiêu người chơi."),
    "他死死盯着ID冷月清泉": ("Tiểu/đại hiệu phải là tài khoản phụ/chính.", "Hắn nhìn chằm chằm ID Lãnh Nguyệt Thanh Tuyền rồi mới nhận ra đây là một tài khoản phụ cũ của Lâm Phong. Khi các tài khoản chính không leo rank được, hắn sẽ lập một loạt tài khoản như vậy để lén lên điểm vào ban đêm."),
    "手握大龙Buff的RNG": ("Giữ Buff Rồng và chiến thuật đẩy lẻ 4-1.", "RNG cầm Buff Rồng, tiếp tục triển khai chiến thuật đẩy lẻ 4-1."),
    "这时大舅子正在": ("大舅子 là biệt danh Mystic; đúng chủ thể và thuật ngữ trang bị.", "Lúc này Mystic đang đấu tay đôi với AD tân binh. Chu Hi Thần đã có ba món lớn, thêm Kiếm Doran và giày CD; Xayah của Mystic mới có hai món rưỡi."),
    "参赛队伍分两个小组": ("Giữ nguyên chính xác case tên đội.", "Các đội dự thi chia làm hai bảng: bảng A gồm CyberZen, MVP.Karnal, Chiefs, RiskyGaming; bảng B gồm Renegades, TyLoo, MongolZ, EatYouAlive."),
    "这是天赋吗": ("Giữ Debuff như thuật ngữ.", "Đây mà là thiên phú sao? Rõ ràng là Debuff!"),
    "国内有八只队伍": ("Giữ đúng case tên đội và thể thức.", "Có tám đội trong nước tranh tài: tyloo, wings, AG, BOF, Gank, Rstar, RS và eFuture. Qua thể thức loại kép, đội vô địch sẽ giành suất dự IEM Đài Bắc."),
    "下半年，是快到": ("狙神 là tay bắn tỉa.", "Nửa cuối năm, tay bắn tỉa KennyS nhanh đến mức đáng sợ; đội EnvyUs của hắn vô địch DreamHack Cluj-Napoca major sau khi đánh bại NAVI có Qua Hoàng."),
    "主教练菲尔": ("Giữ tên giải thưởng và ý chiến thuật.", "Huấn luyện viên trưởng Phil Martelli lấy chiến thuật pick-and-roll ở vị trí cao kết hợp chuyển đổi công thủ nhanh làm cốt lõi, xây dựng hệ thống tấn công hiệu quả thứ ba nước Mỹ và giành giải Naismith College Coach of the Year."),
    "公告显示，qz": ("Giữ tên giải/đội và quan hệ xử phạt.", "Thông báo cho biết tài khoản liên quan qz từng dùng đã bị VAC cấm sau giải MSI Beat It năm 2013. Vì vậy ESL quyết định cấm qz của Tyloo thi đấu vĩnh viễn; đây là án phạt rất nặng."),
    "对面的Fofo": ("Giữ đúng tên tuyển thủ/giải.", "Fofo phía đối diện quả không phụ danh xưng đường giữa hàng đầu LPL mùa S10: năng lực cá nhân, tầm nhìn đại cục và giao tranh đều rất xuất sắc, kéo nhịp độ cho cả BLG."),
    "“尘埃战队也不错": ("Bỏ mâu thuẫn Á quân ADC vô địch; giữ exact ID lowercase.", "“Đội Dust cũng không tệ: ngoại binh Hàn Quốc đường trên flu và mote ở vị trí ADC. mote từng là ADC vô địch thế giới mùa trước của đội ssk Hàn Quốc đấy!”"),
    "captainMO熟练地": ("Giữ case captainMO, demo, steam, advent.", "captainMO thuần thục mở bản phát lại. Xem xong demo, hắn cũng sững sờ đầy dấu hỏi. Hắn mở khung tin nhắn steam, tìm advent rồi gõ trên bàn phím."),
    "最后，匹配了很久": ("Giữ đúng case tên tuyển thủ.", "Sau khi ghép trận rất lâu, cuối cùng cũng vào được. Phía đối diện là ba tuyển thủ AG cùng diyy: forget, ED101 và wjw. Gần đây họ vừa vào nền tảng đối chiến B5."),
    "“让我们！欢迎": ("Giữ nguyên EDward——Gaming và khẩu hiệu.", "“Hãy chào đón ba đội đại diện LPL chinh chiến Chung kết Thế giới Liên Minh Huyền Thoại 2017! Đội hạt giống số một: EDward——Gaming! EDG! G! G!!!!!”"),
    "Kindy看到Jason": ("Giữ tên người/đội, dịch tự nhiên.", "Kindy thấy Jason vừa nghe vừa gật đầu, biết hắn cũng đồng ý nên nói tiếp: “Ta còn một ý, hãy bàn kỹ với Wings về việc trao đổi DD và Attacker. Hai câu lạc bộ cùng thử một lần, cũng cho hai tuyển thủ đổi môi trường; biết đâu tạo ra phản ứng khác. Wings thiệt hại không lớn, thậm chí còn có lợi; nếu ta cứ đòi Attacker thì chắc phải tốn không ít tiền.”"),
    "“Game,Set,Match": ("Giữ khẩu ngữ tennis và tỉ số.", "“Game, Set, Match — Arisu Mio, 6:4!”"),
    "“cao，真会抓timing": ("cao là chửi tục, không phải tên; 破防 là mất bình tĩnh; giữ zhoking.", "“Mẹ kiếp, bắt timing chuẩn thật.” zhoking hơi mất bình tĩnh."),
    "曼联这边自然": ("Giữ nguyên câu hát cổ vũ.", "Phía Man United dĩ nhiên không chịu lép vế, tiếng hô “Glory Glory Man United” vang khắp sân."),
    "手枪局，刘风": ("Giữ tên súng và nghĩa mua trang bị.", "Ở round súng lục, Lưu Phong không mua P250 hay FN57 mà chỉ mua giáp chống đạn, dùng khẩu USP mặc định."),
    "S级的转盘": ("Giữ dải cấp bậc.", "Phạm vi rút thưởng của vòng quay cấp S là [S-A-B-C], còn vòng quay cấp SSS là [SSS-SS-S-A]."),
    "QG（红色方）": ("妖刀=Yêu Đao, 盾山=Thuẫn Sơn.", "QG (phía đỏ): Khải (Fly), Bàn Cổ (giao), Chu Du (mojo), Lý Nguyên Phương (Yêu Đao), Thuẫn Sơn (770)."),
    "谢无争往上翻": ("FPS và tên game phải tự nhiên.", "Tạ Vô Tranh lướt lại lịch sử chat, tìm thấy thông tin đơn hàng chưa hoàn tất: đó là game FPS hắn từng chơi, 《Endless Fire》."),
    "心思回到新装备上": ("Giữ tên hãng/sản phẩm.", "Nghĩ lại dàn trang bị mới, Lưu Phong nhận ra toàn đồ nổi tiếng: chuột EC2 của Zowie, bàn phím cơ và lót chuột QCK+ của SteelSeries, tai nghe Siberia của icemat."),
    "【收服厉鬼奖励": ("Giữ hệ số xN và số lượng.", "【Thu phục lệ quỷ: điểm x300, kinh nghiệm x300, đạo cụ ngẫu nhiên x1. Tiêu diệt lệ quỷ: điểm x150, kinh nghiệm x100, không rơi đạo cụ. Khuyến nghị ưu tiên thu phục.】"),
    "“backflow,你是个外挂狗": ("Giữ tên, dịch chửi tự nhiên.", "“backflow, ngươi đúng là thằng chó dùng hack. Sau này đừng quay lại server của bọn ta; tự cút đi. Còn tới lần nào, bọn ta đá lần ấy.” Crazy thiếu gia tức tối nói trên kênh thoại công cộng."),
    "在2015年底": ("Giữ tên giải và mốc thời gian.", "Cuối năm 2015, Lưu Phong xem trực tiếp trận chung kết khu vực Trung Quốc của SL i-League StarSeries XIV trên mạng. Ở kiếp trước, hắn không để ý giải đấu này."),
    "而且不止是战队": ("Giữ tên đội/giải, làm rõ quan hệ.", "Không chỉ đội hình cực mạnh, ở giải Mid-Season Invitational trước đó, đội god đã đánh bại đội fate hàng đầu của giải OGN Hàn Quốc trong trận chung kết để giành cúp vô địch thế giới."),
    "声称“我的使命才刚开始”": ("背锅出走 là gánh tiếng xấu rồi rời đi; chủ thể là hắn.", "Nguyệt Quang, người từng nói “Sứ mệnh của ta mới bắt đầu”, đã gánh tiếng xấu rồi rời đi. Ban lãnh đạo dồn mọi hy vọng vào tổng giám sát huấn luyện Trương Giác, mong hắn gánh vác trọng trách ở mùa xuân năm sau: Make AG Great Again — để AG lại vĩ đại."),
    "Mafa教练点了点头": ("Dịch lại câu sai/cứng, rõ đau điểm IG.", "Huấn luyện viên Mafa gật đầu. Từ đầu trận, ngoài việc quan sát tốc độ đi rừng của Ning và vị trí lên đường cấp một cùng tình hình cắm mắt của TheShy, ông cùng trợ lý luôn theo dõi đường dưới. Đây là then chốt của ván đấu tập này, cũng là điểm yếu của IG."),
    "张龙大步而来": ("Giữ Very Good và Boss đúng case nguồn.", "Trương Long sải bước tới, mắt ánh lên niềm vui: “Very Good! Tuy chưa tìm được thứ cần tìm, nhưng gặp được một Boss cũng không tệ. Đội nào phát hiện ra?”"),
    "Gala接过小狗": ("Giữ tên tuyển thủ/đội.", "Gala tiếp nhận vị trí AD từ Tiểu Cẩu, sẽ là quân bài lớn nhất của RNG ở mùa S11 năm sau, chỉ là hiện giờ vẫn cần rèn giũa thêm."),
    "GG-Captain，替补狙击手": ("狙击手 là tay bắn tỉa.", "GG-Captain, tay bắn tỉa dự bị, nổi tiếng nhờ khả năng áp chế tầm xa chính xác; ở giải hạng dưới, hắn thường xuyên nằm trong top ba bảng MVP."),
    "最后peek 击杀Uki": ("Giữ đúng case zhoking.", "Pha peek cuối cùng hạ Uki rồi nhảy lên tầng hai hạ zhoking, đến cả ở đấu trường chuyên nghiệp hiện nay cũng cực kỳ hiếm thấy."),
    "“你好啊，江苏NIKO": ("Thành ngữ phải tự nhiên.", "“Chào nhé, Giang Tô NIKO. Đã mang tên ấy thì đừng để uổng, lát nữa phải carry lên đấy.” captainMo vẫn thân thiện nói."),
    "“请IG.Rookie选手": ("Giữ chính xác ID tuyển thủ và thời điểm.", "“Hai phút nữa, mời tuyển thủ IG.Rookie và IG.K'aiVen tới hậu trường nhận phỏng vấn sau trận. Sau phỏng vấn còn lễ xuất chinh của LPL, mời toàn bộ tuyển thủ và huấn luyện viên trưởng chuẩn bị.”"),
}

TRAIN_MANUAL_REFERENCES = {
    "全民领主里面": (
        "Giữ NPC/BOSS và làm rõ chỉ anh hùng cùng NPC/BOSS mới nói được.",
        "Trong toàn dân lãnh chúa, binh chủng sẽ không nói chuyện, chỉ có anh hùng, NPC hoặc BOSS mới có thể.",
    ),
    "听着周曦臣凡尔赛": (
        "凡尔赛 là khoe khoang; 肉鸡 là ID Rookie, không phải con gà con.",
        "Nghe Chu Hi Thần khoe khoang đến cực điểm, Rookie và huấn luyện viên Mafa đều sa sầm mặt. Mẹ kiếp, ngươi đúng là mê đánh rank thật đấy...",
    ),
    "一行四人浩浩荡荡": (
        "蓝buff là bùa xanh, không phải Lam buff.",
        "Bốn người hùng hổ băng qua sông, tiến thẳng vào khu vực bùa xanh của đối phương.",
    ),
    "“你好，我是战神公会": (
        "一战成名 là Nhất Chiến Thành Danh; câu giới thiệu ID phải tự nhiên.",
        "“Xin chào, ta là người phụ trách Công hội Chiến Thần tại thôn tân thủ này. ID nhân vật của ta là Nhất Chiến Thành Danh. Ngươi là Bắc Minh đúng không? Bọn ta đã chú ý ngươi từ lâu.”",
    ),
    "夜歌眼中闪过": (
        "钻1/大师/王者 là Kim Cương I, Đại Sư và Thách Đấu.",
        "Trong mắt Dạ Ca lóe lên tinh quang. Cao thủ như vậy tất nhiên không thể chỉ là người chơi Bạch Kim bình thường; ít nhất cũng phải đủ sức tung hoành ở Kim Cương I, thậm chí Đại Sư hoặc Thách Đấu tại máy chủ Điện Nhất.",
    ),
    "“卖面包了": (
        "20秒加1000血 là hồi 1.000 HP trong 20 giây; giữ PK.",
        "“Bánh mì đây! Hồi 1.000 HP trong 20 giây, vật thiết yếu khi đánh quái, PK! Mọi người mau tới mua!”",
    ),
    "一旦被晕住": (
        "Giữ KDA và quan hệ điều kiện bị hạ thêm một lần.",
        "Chỉ cần bị choáng rồi để Tô Minh hạ thêm một lần nữa, hắn sẽ lập kỷ lục KDA thấp nhất lịch sử cả liên minh!",
    ),
    "【首杀黑铁级小BOSS": (
        "Giữ BOSS và cấp Hắc Thiết.",
        "【Thưởng tiêu diệt đầu tiên BOSS nhỏ cấp Hắc Thiết: một kỹ năng ngẫu nhiên!】",
    ),
    "“是！”张岩": (
        "叫阵 là kỹ năng Khiêu Chiến; 强制仇恨 là cưỡng chế boss tập trung thù hận.",
        "“Vâng!” Trương Nham bật người lao lên, lập tức dùng 【Khiêu Chiến】 khiêu khích boss, cưỡng chế boss tập trung thù hận trong 5 giây.",
    ),
    "由于皇子打野": (
        "皇子 là Jarvan; 打一套 là dồn một bộ kỹ năng.",
        "Jarvan đi rừng đã mất một phần máu, thời gian hồi chiêu EQ đầu trận lại rất dài; trong lúc nấp bụi, hắn còn bất ngờ bị Syndra dồn cả bộ kỹ năng.",
    ),
    "【检测到女神": (
        "至死不渝 là sống chết không đổi; CD còn một lần mỗi hai giờ.",
        "【Phát hiện độ thân mật của nữ thần ‘Tô Mẫn’ đạt 90 điểm, đạt mức ‘sống chết không đổi’; CD giảm mạnh xuống 2 giờ/lần.】",
    ),
    "啥子复活CD": (
        "Giữ CD và giọng chửi khẩu ngữ, không dùng convertese.",
        "“CD hồi sinh cái quỷ gì! Năm xưa lão tử chơi Truyền Kỳ, cùng lắm chỉ rơi trang bị; thằng ranh nào bảo sẽ chết thật chứ!” Đại thúc râu ria nhổ mạnh mẩu thuốc, giọng Tứ Xuyên đặc sệt vẻ khinh thường.",
    ),
    "三号脑海中突然": (
        "Giữ BOSS và làm rõ số ba/số bảy là danh xưng.",
        "Trong đầu số ba bỗng vang lên một giọng nói: “Đinh Chí Học, ngươi nhân lúc phó hội trưởng giết BOSS, bất chấp kế hoạch mà cưỡng sát số bảy, là muốn tranh điểm với ngài ấy sao? Ngươi quên mục đích thật sự của phó hội trưởng khi tới đây rồi ư?”",
    ),
    "至于现在嘛": (
        "Giữ BOSS và sáu chìa khóa, dịch tự nhiên mạch suy luận.",
        "Còn bây giờ, tất nhiên phải lên khoang khách tầng trên xem thử. Giết BOSS nhận được sáu chìa khóa phòng mà! Những zombie đủ sức thành BOSS khi còn sống hẳn đều là nhân vật cấp cán bộ. Trời mới biết trong phòng chúng có bảo vật gì! Ha ha ha!",
    ),
    "“我今天Rank": (
        "Giữ rank/CD và dịch đúng lối lên đồ Gươm Suy Vong - Rìu Đen.",
        "“Hôm nay đánh rank, ta vừa bị kiểu lên đồ này hại thảm. Ta dọn xong đường giữa liền sang giúp, vậy mà hắn có lợi thế đi đường cũng chẳng làm nên trò trống gì. Không biết thao tác thì cút về chơi lối hiệu ứng đòn đánh Gươm Suy Vong - Rìu Đen đi! Mẹ kiếp, bị đối phương đánh như chó!”",
    ),
    "而团队这种东西": (
        "Đại Phi là người chơi đơn độc; danh vọng dùng để chiêu mộ NPC.",
        "Với người chơi đơn độc như Đại Phi, chuyện tổ đội quá xa vời; hắn chỉ có thể chiêu mộ nhân tài NPC. Muốn mời được NPC ưu tú, thậm chí anh hùng NPC, người chơi nhất định phải có danh vọng. Chẳng ai muốn đi theo một kẻ vô danh.",
    ),
    "“我玩过游戏": (
        "Giữ game/zombie/boss, dùng nhất quán ta-ngươi.",
        "“Ta từng chơi game. Đường trong thị trấn vừa hẹp vừa phức tạp, xe khó đi, zombie lại thành đàn!” Ngô Mông khuyên: “Ngươi nghĩ xem, đang đi thì cả bầy zombie gào rú lao tới... Huống chi còn có kẻ nhiễm bệnh và boss nhỏ...”",
    ),
    "估计自己这个试炼BOSS": (
        "Giữ BOSS và quan hệ không xông vào khoang thuyền thì không kích hoạt nó.",
        "BOSS thí luyện của mình có lẽ cũng tương tự. Bước tiếp theo phải dốc sức thăng cấp, không kích thích BOSS nữa. Từ việc bộ xương đột nhiên biến thành zombie trong lần khiêu chiến thứ hai, chỉ cần không xông vào khoang thuyền thì sẽ không kích hoạt BOSS.",
    ),
    "血海狂涛恍然大悟": (
        "Giữ BOSS và làm rõ ma pháp thư mới là nguồn sức mạnh.",
        "Huyết Hải Cuồng Đao chợt hiểu ra! Một BOSS nhỏ ở thôn tân thủ sao có thể biết nhiều pháp thuật hắc ám đến vậy? Ma pháp thư mới là mấu chốt. Chỉ cần giết BOSS, rất có thể quyển sách sẽ rơi ra. Bản thân ma pháp thư chứa lượng ma lực khổng lồ, thậm chí có sinh mệnh, còn giúp người không có nền tảng ma pháp thi triển pháp thuật ghi trong sách. Bảo vật như vậy lại xuất hiện ở thôn thí luyện tân thủ ư?",
    ),
    "“12级的话": (
        "Giữ cấp 12 và PK, dùng địa danh nhất quán.",
        "“Cấp 12 thì ra khỏi cổng thành, tới rừng Thanh Phong là được! Nhưng phải cẩn thận, bên đó có rất nhiều người PK; ngươi nên chọn chỗ vắng người một chút.”",
    ),
}


def source_hash(zh: str) -> str:
    return hashlib.sha256(clean_source(zh).encode("utf-8")).hexdigest()


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def blocked_hashes() -> set[str]:
    blocked = {source_hash(row["zh"]) for row in read_jsonl(CORE)}
    blocked |= {source_hash(row["zh"]) for row in read_jsonl(EVAL60)}
    for row in read_jsonl(SIX_CHAPTERS):
        blocked.add(source_hash(row["source_zh"]))
    return blocked


def labels(zh: str, vi: str) -> list[str]:
    found = sorted({value.upper() for value in GAME.findall(zh + " " + vi)})
    source_words = {value.casefold(): value for value in LATIN.findall(zh)}
    target_words = {value.casefold(): value for value in LATIN.findall(vi)}
    game_words = {value.casefold() for value in found}
    return [*found, *sorted((source_words.keys() & target_words.keys()) - game_words)]


def issue_and_reference(row: dict) -> tuple[str, str]:
    for prefix, (issue, reference) in MANUAL_REFERENCES.items():
        if row["zh"].startswith(prefix):
            return issue, reference
    if row.get("review_issue") and row.get("proposed_vi"):
        return row["review_issue"], row["proposed_vi"]
    tags = labels(row["zh"], row["vi"])
    checks = [f"giữ nguyên {', '.join(tags)}" if tags else "đối chiếu thuật ngữ game"]
    if re.search(r"\d", row["zh"]):
        checks.append("đối chiếu số")
    if any(char in row["zh"] for char in '"“”「」'):
        checks.append("kiểm tra dấu thoại")
    issue = "; ".join(checks) + "."
    return issue, "__MISSING_MANUAL_REFERENCE__"


def candidates() -> list[dict]:
    rows = []
    for row in read_jsonl(PREPARED):
        issue, reference = issue_and_reference(row)
        rows.append({
            "zh": row["zh"], "current_vi": row["vi"], "source": row["source"],
            "source_line": row["source_line"], "source_hash": source_hash(row["zh"]),
            "labels": labels(row["zh"], row["vi"]), "issue": issue,
            "proposed_reference_vi": reference,
        })
    edits = {}
    for path in sorted(DATASET.glob("gold_review_pack_*_edits.jsonl")):
        for row in read_jsonl(path):
            if row.get("proposed_vi"):
                edits[row["id"]] = row
    for row in read_jsonl(DATASET / "gold_candidates_vnext_1200.jsonl"):
        edit = edits.get(row["id"])
        zh, vi = row.get("zh", ""), row.get("raw_vi", "")
        if not zh or not vi or not (GAME.search(zh + " " + vi) or edit):
            continue
        issue, reference = issue_and_reference({
            "zh": zh, "vi": vi, "review_issue": (edit or {}).get("issue"),
            "proposed_vi": (edit or {}).get("proposed_vi"),
        })
        rows.append({
            "zh": zh, "current_vi": vi, "source": "review_pack" if edit else "candidate_pack",
            "source_line": row["id"], "source_hash": source_hash(zh),
            "labels": labels(zh, vi), "issue": issue, "proposed_reference_vi": reference,
        })
    unique: dict[str, dict] = {}
    for row in rows:
        old = unique.get(row["source_hash"])
        if old is None or (row["source"] == "review_pack" and old["source"] != "review_pack"):
            unique[row["source_hash"]] = row
    return [row for row in unique.values() if not row["zh"].startswith(EXCLUDED_PREFIXES)]


def choose(rows: list[dict], count: int, blocked: set[str]) -> list[dict]:
    choices = [row for row in rows if row["source_hash"] not in blocked]
    selected, covered = [], set()
    while choices and len(selected) < count:
        choices.sort(key=lambda row: (
            -sum(8 if label in PRIORITY_LABELS else 1 for label in set(row["labels"]) - covered),
            -sum(8 if label in PRIORITY_LABELS else 1 for label in row["labels"]),
            row["source"] != "review_pack", len(row["zh"]), row["source_hash"],
        ))
        row = choices.pop(0)
        selected.append({**row, "status": "needs_user_review"})
        covered.update(row["labels"])
    if len(selected) != count:
        raise RuntimeError(f"Thiếu ca holdout/review: {len(selected)}/{count}")
    return selected


def shortlist(rows: list[dict], blocked: set[str]) -> list[dict]:
    """Chỉ lấy các cặp đã được đọc nghĩa và có bản Việt thủ công."""
    pool = []
    used_prefixes: set[str] = set()
    for row in rows:
        if row["source_hash"] in blocked:
            continue
        manual = next(
            (
                (prefix, value)
                for prefix, value in TRAIN_MANUAL_REFERENCES.items()
                if prefix not in used_prefixes and row["zh"].startswith(prefix)
            ),
            None,
        )
        if manual:
            prefix, (issue, proposal) = manual
            used_prefixes.add(prefix)
            pool.append({
                **row,
                "issue": issue,
                "proposed_reference_vi": proposal,
            })
    selected = choose(pool, min(50, len(pool)), blocked)
    for row in selected:
        row["proposed_vi"] = row["proposed_reference_vi"]
    return selected


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def render(path: Path, title: str, rows: list[dict], train: bool) -> None:
    lines = [f"# {title}", "", "> Chỉ để người duyệt; không có dòng nào được approved hay đưa vào train.", ""]
    if train:
        lines += ["| # | ZH | VI hiện có | Vấn đề/cờ | VI đề xuất | Quyết định |", "|---:|---|---|---|---|---|"]
        for index, row in enumerate(rows, 1):
            compact = lambda value: value.replace("|", "\\|").replace("\n", " ")[:260]
            full = lambda value: value.replace("|", "\\|").replace("\n", " ")
            proposal = row.get("proposed_vi", "Artifact review cũ, không dùng train")
            lines.append(f"| {index} | {compact(row['zh'])} | {compact(row['current_vi'])} | {compact(row['issue'])} | {full(proposal)} | Chờ user duyệt; không train |")
    else:
        lines += ["| # | ZH | VI hiện có | Vấn đề cụ thể | Tham chiếu đề xuất |", "|---:|---|---|---|---|"]
        for index, row in enumerate(rows, 1):
            compact = lambda value: value.replace("|", "\\|").replace("\n", " ")
            lines.append(f"| {index} | {compact(row['zh'])} | {compact(row['current_vi'])} | {compact(row['issue'])} | {compact(row['proposed_reference_vi'])} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    rows = candidates()
    blocked = blocked_hashes()
    eval_rows = choose(rows, 36, blocked)
    train_rows = choose(rows, 200, blocked | {row["source_hash"] for row in eval_rows})
    shortlist_rows = shortlist(rows, blocked | {row["source_hash"] for row in eval_rows})
    assert not ({row["source_hash"] for row in eval_rows} & {row["source_hash"] for row in train_rows})
    assert all(row["status"] == "needs_user_review" for row in [*eval_rows, *train_rows])
    assert all(not row["proposed_reference_vi"].startswith("__MISSING") for row in eval_rows)
    assert all(row["status"] == "needs_user_review" and row["proposed_vi"] for row in shortlist_rows)
    assert len(shortlist_rows) == 20
    assert all(
        row["current_vi"].strip() != row["proposed_vi"].strip()
        or row["zh"].startswith(ALLOWED_UNCHANGED_PREFIXES)
        for row in shortlist_rows
    )
    write_jsonl(EVAL_OUT, eval_rows)
    write_jsonl(TRAIN_OUT, train_rows)
    write_jsonl(SHORTLIST_OUT, shortlist_rows)
    render(EVAL_MD, "Holdout game-English cần duyệt", eval_rows, train=False)
    render(TRAIN_MD, "200 ca game-English chờ duyệt train", train_rows, train=True)
    render(SHORTLIST_MD, "Shortlist game-English chờ duyệt train", shortlist_rows, train=True)
    print(f"eval={len(eval_rows)} train_review={len(train_rows)} shortlist={len(shortlist_rows)}")


def lock_user_approval() -> None:
    """Khóa đúng hai gói người dùng vừa duyệt; không lấy hàng đợi 200 câu."""
    train_rows = read_jsonl(SHORTLIST_OUT)
    eval_rows = read_jsonl(EVAL_OUT)
    if len(train_rows) != 20 or len(eval_rows) != 36:
        raise RuntimeError(f"Sai số dòng đã duyệt: train={len(train_rows)}, eval={len(eval_rows)}")
    write_jsonl(APPROVED_TRAIN_OUT, [
        {
            "zh": row["zh"],
            "vi": row["proposed_vi"],
            "status": "approved",
            "source": "user_review_game_english",
            "source_hash": row["source_hash"],
        }
        for row in train_rows
    ])
    write_jsonl(LOCKED_EVAL_OUT, [
        {
            "zh": row["zh"],
            "reference_vi": row["proposed_reference_vi"],
            "status": "locked_eval_reference",
            "eval_category": "game_english",
            "source_hash": row["source_hash"],
        }
        for row in eval_rows
    ])
    print(f"locked train={len(train_rows)} eval={len(eval_rows)}")


def self_check() -> None:
    assert len(TRAIN_MANUAL_REFERENCES) == 20
    assert ALLOWED_UNCHANGED_PREFIXES == ("全民领主里面",)
    assert labels("NPC的ID是zhoKing", "NPC có ID zhoKing") == ["ID", "NPC", "zhoking"]
    picked = choose([{"zh": "甲", "vi": "Ất", "source_hash": "a", "labels": ["NPC"], "source": "x"}], 1, set())
    assert picked[0]["status"] == "needs_user_review"
    print("prepare_game_english_review OK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--lock-user-approval", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
    else:
        main()
        if args.lock_user_approval:
            lock_user_approval()
