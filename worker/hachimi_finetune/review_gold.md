# Review gold cổ phong — vòng 1

`review_gold.jsonl` là bản máy đọc tương ứng. Các mục 1–11 chỉ được train sau
khi được đổi sang `approved`; mục 12 chỉ là test tiền xử lý.

## 1. 古帛

**ZH:** `唯一的解释，就是这个黑洞，需要特定的方式才能打开！至于方式，应该是当初二叔提到的古帛!`

**Hiện tại:** `... hẳn là cổ bạch mà nhị thúc đã nhắc tới!`

**Đề xuất:** `Lời giải thích duy nhất là hố đen này cần một phương thức đặc biệt mới mở được! Còn phương thức ấy, hẳn là mảnh lụa cổ mà nhị thúc từng nhắc tới!`

## 2. 古帛 trong ngữ cảnh dài

**ZH:** `二叔口中提到的古帛，王长生根本就没有见过，父亲和二叔只留下了长生功，根本就没有其他的物件了！`

**Đề xuất:** `Mảnh lụa cổ mà nhị thúc nhắc tới, Vương Trường Sinh căn bản chưa từng thấy. Phụ thân và nhị thúc chỉ để lại Trường Sinh Công, ngoài ra không còn vật gì khác!`

## 3. Tagline game

**ZH:** `真实游戏世界+超级天赋+独狼+金融体系不崩溃+打怪升级+boss巨难杀`

**Hiện tại:** bỏ `独狼`, lặp “Siêu”.

**Đề xuất:** `Thế giới game chân thực + thiên phú siêu cấp + độc hành + hệ thống tài chính không sụp đổ + đánh quái thăng cấp + boss cực khó giết`

## 4. Tên riêng và thương hiệu

**ZH:** `罗森刚刚夜跑了10公里，他正在马路边上散步休息，右手还抓着一瓶柠檬味的脉动。`

**Đề xuất:** `La Sâm vừa chạy đêm mười cây số, đang tản bộ nghỉ ngơi bên đường, tay phải còn cầm một chai nước Mạch Động vị chanh.`

## 5. Hồi sinh

**ZH:** `这是...去复活了？罗森在心里喃喃自语。`

**Đề xuất:** `Đây là... đi hồi sinh rồi ư? La Sâm lẩm bẩm trong lòng.`

## 6. Quan hệ chủ-vị

**ZH:** `一些武功被他看一遍就能练得有模有样...`

**Đề xuất:** `Có những môn võ công, hắn chỉ cần xem qua một lượt đã luyện ra dáng ra hồn...`

## 7. Nhịp văn

**ZH:** `无尽的嘲讽、谩骂如同洪水猛兽，将林轩淹没……`

**Đề xuất:** `Vô số lời chế giễu, chửi rủa như hồng thủy mãnh thú, nhấn chìm Lâm Hiên...`

## 8. 达成约定

**ZH:** `那就与我达成九个约定，事后便放你自由，斩断与你的因果。`

**Đề xuất:** `Vậy hãy lập với ta chín điều ước định, sau khi xong việc sẽ trả lại tự do cho ngươi, chặt đứt nhân quả với ngươi.`

## 9. 一颦一笑

**ZH:** `一颦一笑尽显妩媚。`

**Đề xuất:** `Mỗi một cái cau mày, mỗi một nụ cười đều lộ rõ vẻ quyến rũ.`

## 10. Lái Tinh Sa

**ZH:** `老古董你放心，我开星槎什么时候出过事？`

**Đề xuất:** `Lão cổ hủ cứ yên tâm, ta lái Tinh Sa bao giờ xảy ra chuyện chứ?`

## 11. Tinh Sa lách thiên thạch

**ZH:** `在浩瀚无垠的星空中，一艘刚刚完成跃迁的星槎在躲避陨石中游走，只是这艘星槎快的离谱……`

**Đề xuất:** `Giữa tinh không mênh mông vô tận, một chiếc Tinh Sa vừa hoàn thành bước nhảy vọt đang lách qua các thiên thạch. Chỉ là tốc độ của nó nhanh đến mức phi lý...`

## 12. Không train — làm sạch chống crawl

`『露』` và `『色』` phải thành `露`, `色` trước khi đưa cho model. Mục này chỉ
làm regression case cho `clean_source`, không đưa vào gold train.
