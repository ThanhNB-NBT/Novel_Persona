# Khảo sát nguồn crawl truyện Trung Quốc

Khảo sát 93 nguồn do bạn cung cấp (bỏ qua `fanqie` và `qidian` — đã test riêng). Thực hiện bằng 4 đợt research song song (WebSearch tìm domain thật + WebFetch kiểm tra truy cập), ngày 2026-07-04. **Lưu ý:** kết quả dựa trên 1 lần fetch/site, không phải giám sát liên tục — site có SSL lỗi/timeout hôm nay có thể ổn định lại sau, và ngược lại.

## Tóm tắt điều hành

| Mức | Số lượng | Ý nghĩa |
|---|---|---|
| ✅ **Có** | 12 | Truy cập ổn, có metadata đầy đủ, không bị chặn rõ ràng — ưu tiên thêm trước |
| ⚠️ **Cân nhắc** | 33 | Nội dung có giá trị nhưng vướng 1 trong: chặn bot/Cloudflare, SSL lỗi, domain hay đổi, có phần VIP trả phí, hoặc nội dung nhạy cảm cần lọc |
| ❌ **Không** | 48 | Domain sập/rao bán, trùng lặp (site aggregator/reup), sai định dạng nội dung (manga, light novel Nhật), hoặc nội dung không phù hợp |

### ✅ Nên thêm trước (12 nguồn)

| Nguồn | Domain | Thể loại chính | Ghi chú |
|---|---|---|---|
| ikshu8 | m.xikshu8.com | Ngôn tình, kiếm hiệp, huyền huyễn, khoa huyễn, lịch sử | Domain đã đổi ikshu8→xikshu8, cần cập nhật base_url |
| xslou | xslou.net | Tiên hiệp, võ hiệp, đô thị, lịch sử, mạng du, khoa huyễn, ngôn tình | Đa thể loại, có metadata đầy đủ |
| faloo | faloo.com (飞卢小说网) | Hiện đại, cổ đại/lịch sử, phiêu lưu, đam mỹ, nữ tần | Site gốc lớn, có phần VIP nhưng phần free vẫn nhiều |
| uuxs | uuxs.org | Huyền huyễn, võ hiệp, đô thị, lịch sử, mạng du, khoa huyễn, ngôn tình | Metadata đầy đủ (tên/tác giả/trạng thái/ngày/bìa) |
| 521danmei | 521danmei.com (吾爱耽美网) | **Đam mỹ (BL)**, ngôn tình, kiếm hiệp, xuyên không, tu tiên | Có tag nội dung (1v1/HE/H) — cần lọc tag H trước khi crawl |
| qiushubang | xqiushubang.com (求书帮, domain gốc qiushubang.com redirect sang đây) | 24+ thể loại: huyền huyễn, đô thị, võ hiệp, khoa huyễn, tiên hiệp, lịch sử, BL/GL | Rất đa dạng thể loại |
| biqulao | www.biqulo.com (笔趣阁) | Kiếm hiệp, đô thị, khoa huyễn, lịch sử, tình cảm, huyền huyễn | 1 trong họ biqu nhưng site này bản thân truy cập ổn |
| kujiang | www.kujiang.com (酷匠网) | Huyền huyễn/xuyên không, đô thị, mạng du, võ thuật | Nội dung nguyên sáng, nhưng trang chủ thiếu mô tả/số chương |
| xsbique | www.xbiquge.com.cn (新笔趣阁) | Huyền huyễn, võ hiệp, đô thị, lịch sử, mạng du, khoa huyễn, ngôn tình | Metadata đầy đủ, đa thể loại |
| ddxs | www.dingdian-xiaoshuo.com (顶点小说) | Huyền huyễn, đô thị, tiên hiệp, võ hiệp, ngôn tình, xuyên không, mạng du | Không quảng cáo popup, thiếu số chương ở trang chủ |
| quanben5 | quanben5.com (全本小说网) | Huyền huyễn, đô thị, ngôn tình, lịch sử | Hỗ trợ song ngữ giản/phồn thể |

*(11 nguồn — bảng gốc có 12 dòng dự kiến, xem mục "Cân nhắc" cho 168kanshu/hetushu/zongheng nếu muốn nâng cấp lên ưu tiên sau khi giải quyết được chặn bot/SSL.)*

### ⚠️ Đáng cân nhắc — cần xử lý kỹ thuật hoặc lọc nội dung

Chia theo loại vướng mắc để dễ quyết định:

**Chặn bot/Cloudflare (cần proxy hoặc headless browser):**
uukanshu, 69shu (69shuba.com), cuiweijux, qinqinxsw, hetushu, biqugexs, ptwxz, x81zw, qimao, jjwxc

**Lỗi SSL/certificate (domain còn "sống" nhưng cert hỏng — kiểm tra lại bằng công cụ khác, có thể chỉ là vấn đề tạm thời):**
168kanshu, wanbentxt, 230book, zwdu, shucw

**Domain hay đổi/trôi giạt (nội dung tốt nhưng hạ tầng không ổn định):**
shu008, xinyushuwu, 2kxs, shukw, yikanxiaoshuo, ranwenla, bxworg, youyoukanshu, yushubo, idejian

**Có nội dung VIP/trả phí đáng kể (chỉ crawl được phần free):**
ciweimao (刺猬猫), zongheng (纵横中文网), tadu (塔读文学), jjwxc (晋江— cũng chặn bot)

**Site aggregator/reup (tự nhận đăng lại từ nguồn khác — rủi ro trùng lặp với nguồn đã có, nhưng vẫn truy cập được):**
duanqingsi, oldtimescc, biqugele

**Light novel nguyên sáng TQ (khác văn phong tiểu thuyết mạng thường, nhưng vẫn là nội dung gốc hợp lệ):**
sfacg (SF轻小说)

**Khác:**
xiaoshuowa (nghi clone hệ biquge), shu05→đã sập thực ra là "kuhu168/shu05" nhóm domain rao bán (xem mục Không)

### ❌ Không nên crawl

**Domain đã sập / đang rao bán / đổi chủ hoàn toàn:**
69shuorg, xiaoqiangwx, shulinw, wuxia1, shu03, shu05, kuhu168, cn8118, kanmaoxian, kayegenet, 4gxsw, read8, wkkshu, 38kanshu, shubaow, duokan8, xingeweb, xinshuhaige, sinidan, hs313, shumizu, biquge5200, shubao45, xklxsw, kankeo

**Thuộc họ "biqu/笔趣阁" — bản mirror/clone trùng lặp nội dung gần như 100% (nhiều domain khác nhau cùng 1 nguồn):**
zwduxs + 8zwdu (trùng thương hiệu "八一中文网"), biqugeinfo, shumilou, xbiquge, biqugecom, shumiloutw, biqubu, biqugese, bique (→ bique.de không phân giải được, cùng họ)

**Sai định dạng nội dung (không phải tiểu thuyết chữ):**
kanman, acqq, cocomanga (đều là web truyện tranh/manhua), linovel, wenku8 (light novel Nhật Bản dịch Trung — khác đối tượng)

**Nội dung không phù hợp / rủi ro pháp lý:**
trxs (chuyên đồng nhân/fanfiction — rủi ro bản quyền IP), wuwuxs (nội dung erotica rõ ràng)

**Aggregator/tổng hợp lại từ nguồn khác (rủi ro trùng lặp cao, không có giá trị gia tăng):**
qiuxiaoshuo, dibaqu123, jiacuan, lsjxs2, shuchong

**Chặn bot mạnh + không đáng đầu tư thêm:**
66wx, nofff

---

## Bảng chi tiết đầy đủ (93 nguồn)

| Nguồn | Domain tìm được | Truy cập? | Chặn bot? | Thể loại chính | Metadata? | Đánh giá |
|---|---|---|---|---|---|---|
| uukanshu | uukanshu.cc | Không (403) | Có | Ngôn tình/đô thị/huyền huyễn | Chưa xác nhận | Cân nhắc — cần proxy/headless |
| 69shu | 69shuba.com | Không (403) | Có, mạnh | Đô thị/huyền huyễn/ngôn tình | Không xác nhận | Cân nhắc — chặn mạnh |
| 69shuorg | Nghi trùng 69shuba | — | — | — | — | Không — trùng |
| shu008 | shu008.com | Không (ECONNREFUSED) | Nghi có | Đô thị, xuyên không, huyền huyễn | Không xác nhận | Cân nhắc — thử lại cách khác |
| xinyushuwu | xinyushuwu.com (redirect vòng) | Không ổn định | Có dấu hiệu | Huyền huyễn, tiên hiệp, đô thị, quân sự, khoa huyễn | Chưa xác nhận | Cân nhắc — SSL lỗi |
| xiaoqiangwx | .com nghi sập, .org bị chiếm | Không | — | — | Không | Không — đổi chủ/sập |
| cuiweijux | cuiweijux.com (翠微居) | Không (403) | Có | Đam mỹ/BL, ngôn tình, huyền huyễn, tiên hiệp | Chưa xác nhận | Cân nhắc — chặn bot |
| bique | bique.de (không phân giải) | Không (ENOTFOUND) | — | Huyền huyễn, võ hiệp, đô thị… (theo mô tả chung họ biqu) | — | Không — 1 trong hàng chục mirror biquge, domain không phân giải được |
| trxs | trxs.cc (同人小说网) | Không (403) | Có | Đồng nhân/fanfiction | Chưa xác nhận | Không — rủi ro bản quyền IP + bị chặn |
| ikshu8 | m.xikshu8.com | **Có** | Không | Ngôn tình, kiếm hiệp, huyền huyễn, khoa huyễn, lịch sử | Có — đầy đủ | **Có** — domain đã đổi tên |
| shulinw | shulinw.com | Không (404) | — | — | — | Không — đã sập |
| wuxia1 | wuxia1.com | Không (rao bán) | — | — | — | Không — domain hết hạn |
| xslou | xslou.net | **Có** | Không thấy rõ | Tiên hiệp, võ hiệp, đô thị, lịch sử, mạng du, khoa huyễn, ngôn tình | Có | **Có** |
| shu03 | Không tìm thấy | — | — | — | — | Không |
| shu05 | shu05.com (rao bán) | Không | — | — | — | Không |
| kuhu168 | kuhu168.com (rao bán/park) | Không | — | — | — | Không |
| 2kxs | 2kxs.cc | **Có** | Không thấy rõ | Huyền huyễn, tái sinh, đô thị, mạng du, khoa huyễn, ngôn tình | Có | Cân nhắc — tự nhận "转载" (tái đăng), nhiều domain phụ trùng |
| shukw | shukw.com | Không xác nhận (rỗng) | Nghi có | Xuyên không, đô thị, tiên hiệp/huyền huyễn | Chưa xác nhận | Cân nhắc — thử bản mobile |
| cn8118 | cn8118.com | Không (DNS lỗi) | — | — | — | Không |
| yikanxiaoshuo | yikanxiaoshuoa.com | Không (SSL lỗi) | Nghi có | Tổng hợp đa thể loại | Chưa xác nhận | Cân nhắc |
| xiaoshuowa | xiaoshuowa.com | Không (403) | Có | Đô thị, ngôn tình, huyền huyễn | Chưa xác nhận | Cân nhắc/Không — nghi clone biquge |
| zwduxs | zwduxs.com (八一中文网) | Không (ECONNREFUSED) | Nghi có | Đô thị, xuyên không, mạng du, huyền huyễn, tu chân, khoa huyễn | Chưa xác nhận | Không — trùng 8zwdu |
| 8zwdu | 8zwdu.com (八一中文网) | Không (SSL lỗi) | Nghi có | (như trên) | Chưa xác nhận | Không — trùng zwduxs |
| kanmaoxian | kanmaoxian.com | Không (park/hết hạn) | — | — | — | Không |
| kayegenet | kayege.net | Không (ECONNRESET) | — | — | — | Không |
| 4gxsw | 4gxsw.com (đổi chủ), 4gxs.cc 404 | Không | — | — | — | Không — đổi chủ |
| qinqinxsw | qinqinxsw.com | Không (403) | Có, rõ | Huyền huyễn, đô thị, ngôn tình, tổng tài văn | Không xác nhận | Cân nhắc — site thật nhưng chặn mạnh |
| read8 | Không xác định domain hoạt động | — | — | — | — | Không |
| ciweimao | ciweimao.com (刺猬猫阅读) | **Có** | Yêu cầu đăng nhập (không phải CF) | Khoa huyễn, đô thị thanh xuân, tiên hiệp võ hiệp, lịch sử quân sự | Có — đầy đủ | Cân nhắc — chủ yếu VIP/trả phí |
| wkkshu | wkkshu.com (悟空看书, đồng nhân) | Không (ECONNREFUSED) | Không rõ | Đồng nhân/fanfic, xuyên không, huyền huyễn | Chưa xác nhận | Không — kết nối kém + rủi ro bản quyền |
| 168kanshu | 168kanshu.com | Không (SSL lỗi) | Không xác định | Huyền huyễn, ngôn tình | Chưa xác nhận | Cân nhắc — domain còn traffic thật |
| wanbentxt | wanbentxt.com | Không (SSL lỗi) | Không xác định | Ngôn tình, đô thị, huyền huyễn | Chưa xác nhận | Cân nhắc |
| 38kanshu | 38kanshu.com | Có nhưng đổi nội dung | — | Đã đổi thành trang phim 18+ | — | Không — đổi mục đích |
| duanqingsi | duanqingsi.net | Có | Không thấy rõ | Huyền huyễn/tiên hiệp, đô thị, quân sự, lịch sử, kinh dị | Có — đầy đủ | Cân nhắc — tự nhận aggregator |
| faloo | faloo.com (飞卢小说网) | **Có** | Không thấy rõ | Hiện đại, cổ đại/lịch sử, phiêu lưu, đam mỹ, nữ tần | Có — đầy đủ | **Có** — có phần VIP nhưng đáng crawl |
| qiuxiaoshuo | qiuxiaoshuo.com (522 timeout) | Không | — | Huyền huyễn, đô thị, lịch sử, võ hiệp | — | Không — tự nhận aggregator, domain không ổn |
| dibaqu123 | dibaqu123.com (第八区) | Không (403) | Có | Huyền huyễn, xuyên không, đô thị, tu tiên | Chưa xác nhận | Không — chặn + đổi domain liên tục |
| jiacuan | jiacuan.com | Không | Nghi có | Nghi kho tổng hợp | — | Không |
| lsjxs2 | lsjxs2.com | Không (ECONNREFUSED) | — | Đô thị, ngôn tình | — | Không |
| shubaow | shubaow.net (nội dung lệch tên gốc) | Không (ENOTFOUND) | — | — | — | Không — DNS lỗi, đổi chủ nghi vấn |
| biqugeinfo | biquge.info | Không (ECONNREFUSED) | — | Đa thể loại | — | Không — 1 trong hàng chục mirror biquge |
| shumilou | shumilou.net/.com… (6+ mirror) | Không | — | Huyền huyễn, tu chân, đô thị, lịch sử, khoa huyễn, ngôn tình | — | Không — nhiều mirror trùng |
| xbiquge | xbiquge.so (8+ mirror) | Không (socket hang up) | Nghi có | Đa thể loại tổng hợp lớn | — | Không — ví dụ điển hình mirror biquge |
| duokan8 | duokan8.info (自认 repost) | Không trực tiếp | — | Đô thị, cung đấu, huyền huyễn, tiên hiệp, phiêu lưu | — | Không — tự nhận đăng lại |
| biqugecom | biqugecom.cc (thêm 1 mirror biqu) | Không | — | Đa thể loại tổng hợp | — | Không — mirror trùng |
| hetushu | hetushu.com (和图书) | Không (403) | Có, rõ | Huyền huyễn, tu tiên, đô thị, khoa huyễn, võ hiệp, lịch sử, xuyên không | Có vẻ đầy đủ | Cân nhắc — nội dung tốt nhưng chặn mạnh |
| nofff | nofff.com | Không (SSL hết hạn) | — | Nghi clone biquge | — | Không |
| uuxs | uuxs.org | **Có** | Không thấy | Huyền huyễn, võ hiệp, đô thị, lịch sử, mạng du, khoa huyễn, ngôn tình | Có — đầy đủ | **Có** |
| ranwenla | ranwen.la | Không (ECONNREFUSED) | Có thể | Huyền huyễn, tu chân, đô thị, lịch sử, khoa huyễn, kinh dị, ngôn tình | — | Cân nhắc — domain không ổn |
| 66wx | Không xác nhận domain | 403 | Có | — | — | Không |
| biqugexs | biqugexs.org | Có (qua search) | Có phần (403 fetch) | Huyền huyễn, tu chân, đô thị, lịch sử | Có | Cân nhắc |
| 230book | 230book.net (顶点小说) | Không (SSL tự ký) | Có khả năng | Huyền huyễn, đô thị, tổng hợp | — | Cân nhắc |
| shumiloutw | shumilou.com/.tw/.net | Không (SSL hết hạn) | — | Huyền huyễn, tu chân, đô thị, lịch sử, khoa huyễn, ngôn tình | — | Không |
| biqubu | biqubu.com → biqubu3.com | Không (403 ở đích) | Có | — | — | Không — domain đổi liên tục + chặn |
| 521danmei | 521danmei.com (吾爱耽美网) | **Có** | Không thấy rõ | Đam mỹ (BL), ngôn tình, kiếm hiệp, xuyên không, tu tiên | Có — đầy đủ + tag | **Có** — cần lọc tag H |
| bxworg | bxwxorg.com (笔下文学) | Không (ECONNRESET) | — | Huyền huyễn, ngôn tình hiện đại, khoa huyễn, kinh dị | — | Cân nhắc — thử lại |
| zwdu | zwdu.com (八一中文网) | Không (cert lỗi) | — | Tổng hợp | — | Cân nhắc — site nổi tiếng làm book-source |
| xingeweb | Không tìm thấy | — | — | — | — | Không |
| zongheng | zongheng.com (纵横中文网) | **Có** | Không thấy rõ | Huyền huyễn/kỳ huyễn, đô thị, võ hiệp/tiên hiệp, khoa huyễn, lịch sử | Có — đầy đủ | Cân nhắc — nhiều VIP |
| biqugese | Nghi biqugse.com | Không (lỗi TLS) | Có khả năng | — | — | Không |
| qiushubang | xqiushubang.com (求书帮) | **Có** | Không thấy | 24+ thể loại | Có | **Có** |
| xinshuhaige | xinshuhaige.com | Đã sập (rao bán GoDaddy) | — | — | — | Không |
| oldtimescc | oldtimescc.com (cần JS render) | Không rõ | Có khả năng | Huyền huyễn, tu chân, đô thị | — | Cân nhắc — cần crawler render JS |
| sinidan | Không tìm thấy | — | — | — | — | Không |
| wuwuxs | wuwuxs.com (cần JS) | Không rõ | Có khả năng | **Erotica** | — | Không — nội dung nhạy cảm |
| hs313 | hs313.info | Không (ENOTFOUND) | — | — | — | Không |
| shuchong | shuchongxiaoshuo.com | Không (ECONNREFUSED) | — | Aggregator | — | Không — trùng lặp + không kết nối được |
| shucw | shucw.net (书城网) | Không (SSL tự ký) | Có khả năng | Khoa huyễn, trinh thám, đô thị, võ hiệp | — | Cân nhắc |
| shumizu | Nghi shumi5.org | Không (ENOTFOUND) | — | — | — | Không |
| tadu | www.tadu.com (塔读文学) | **Có** | Không thấy | Đô thị, huyền ảo phương Đông, lịch sử giả tưởng, quân sự | Có — đầy đủ | Cân nhắc — nhiều VIP |
| ptwxz | ptwxz.com → piaotia.com | Không (403) | Có, rõ | Huyền ảo, tiên hiệp, đô thị, lịch sử quân sự, khoa huyễn | — | Cân nhắc — domain trôi giạt |
| x81zw | 81zw.net → ktshu.cc | Không (đủ loại lỗi) | Có, rõ | Huyền ảo, võ hiệp, đô thị, lịch sử | — | Cân nhắc — domain không ổn |
| linovel | linovel.net/linovelib.com | Không (403/timeout) | Có | **Light novel Nhật dịch Trung** | — | Không — sai đối tượng |
| wenku8 | www.wenku8.net | Không (403) | Có, rõ | **Light novel Nhật Bản** | — | Không — sai định dạng |
| youyoukanshu | youyoukanshu.com (redirect) | Redirect lạ | Có khả năng | Huyền ảo, tu tiên, đô thị, xuyên không | Chưa đầy đủ | Cân nhắc — domain-hopping |
| biqulao | www.biqulo.com | **Có** | Không thấy | Kiếm hiệp, đô thị, khoa huyễn, lịch sử, tình cảm, huyền ảo | Có — đầy đủ | **Có** |
| biqugele | www.biquge345.com | Có (tự nhận reup) | Không thấy | Huyễn thuyết, tiên hiệp/tu chân, đô thị/ngôn tình, game, khoa huyễn, lịch sử | Có (nhưng reup) | Cân nhắc — rủi ro trùng lặp |
| biquge5200 | biquge5200.cc (SSL hết hạn) | Không | — | — | — | Không |
| sfacg | book.sfacg.com | **Có** | Không thấy | **Light novel nguyên sáng TQ**: huyền ảo, khoa huyễn, cổ phong, đô thị, học đường | Có — đầy đủ (lượt đọc/yêu thích/đánh giá) | Cân nhắc — khác văn phong thường |
| shubao45 | www.shubao45.com | Không (lỗi PHP) | — | Ngôn tình cổ trang, nội dung H/18+, tu chân | — | Không — lỗi + nội dung nhạy cảm |
| kujiang | www.kujiang.com (酷匠网) | **Có** | Không thấy | Huyền ảo/xuyên không, đô thị, mạng du, võ thuật | Thiếu mô tả/số chương | **Có** |
| yushubo | www.yushuwuba.com (nhiều mirror) | Có | Không thấy rõ | Huyền ảo, tiên hiệp, đô thị, cổ ngôn, xuyên không, học đường (có nội dung nhạy cảm) | Có | Cân nhắc — domain trôi giạt + cần lọc |
| xklxsw | xklxsw.com/.cc | Không (ENOTFOUND) | — | Ngôn tình nữ giới, BL, huyền ảo, xuyên không, võ hiệp | — | Không (tạm thời) |
| xsbique | www.xbiquge.com.cn (新笔趣阁) | **Có** | Không thấy | Huyền ảo, võ hiệp, đô thị, lịch sử, mạng du, khoa huyễn, ngôn tình | Có — đầy đủ | **Có** |
| kanman | www.kanman.com | — | — | **Truyện tranh (manhua)** | — | Không — sai định dạng |
| acqq | ac.qq.com (Tencent) | — | — | **Truyện tranh** | — | Không — sai định dạng |
| cocomanga | www.cocomanga.com | — | — | **Truyện tranh** | — | Không — sai định dạng |
| jjwxc | www.jjwxc.net (晋江文学城) | Có (trang chủ) | Không thấy ở trang chủ | Ngôn tình, đam mỹ (BL) — nền tảng lớn | Chưa xác nhận chi tiết | Cân nhắc — nhiều VIP, nghi chống crawl mạnh ở trang chi tiết |
| kankeo | www.kankeo.cc | Không (ECONNREFUSED, server Nam Phi) | — | Khoa huyễn linh dị, đô thị ngôn tình, lịch sử quân sự, huyền ảo, võ hiệp | — | Không |
| qimao | www.qimao.com (七猫中文网) | Không (lỗi header bất thường) | Có khả năng | Đô thị, huyền ảo, ngôn tình | — | Cân nhắc — cần công cụ crawl chuyên biệt |
| ddxs | www.dingdian-xiaoshuo.com (顶点小说) | **Có** | Không thấy | Huyền ảo, đô thị, tiên hiệp, võ hiệp, ngôn tình, xuyên không, mạng du | Thiếu số chương/trạng thái | **Có** |
| quanben5 | quanben5.com (全本小说网) | **Có** | Không thấy | Huyền ảo, đô thị, ngôn tình, lịch sử (song ngữ giản/phồn) | Có | **Có** |
| idejian | www.idejian.com (得间免费小说) | Không (ECONNRESET) | — | Đô thị ngôn tình, xuyên không, huyền ảo tu chân, võ hiệp | — | Cân nhắc — thử lại, có thể lỗi tạm thời |

---

## Nhận xét kỹ thuật chung

1. **Họ "biqu/笔趣阁" chiếm gần 1/4 danh sách** (bique, xbiquge, biqugeinfo, biqugecom, biqugexs, biqubu, biqugese, biqulao, biqugele, xsbique, zwduxs/8zwdu…) — đây là một "thương hiệu" bị nhân bản hàng chục lần trên nhiều domain khác nhau, gần như chắc chắn trùng nội dung với nhau và với `shuhaige` đã có. **Chỉ nên giữ 1–2 domain ổn định nhất** (biqulao, xsbique) thay vì crawl tất cả.
2. **SSL certificate hỏng/hết hạn xuất hiện ở rất nhiều site nhỏ** (168kanshu, wanbentxt, 230book, zwdu, shucw, shumilou, biquge5200…) — dấu hiệu hạ tầng ít được bảo trì. Có thể chỉ là vấn đề tạm thời của lần fetch này; đáng thử lại bằng công cụ khác (`curl -k`, browser thật) trước khi loại hẳn.
3. **Chặn bot/Cloudflare rất phổ biến** ở các site lớn/nổi tiếng (69shu, hetushu, qinqinxsw, ptwxz, qimao, jjwxc) — nếu muốn crawl các site này cần đầu tư headless browser (Playwright) hoặc proxy dân dụng (residential proxy), không chỉ HTTP request thường như hiện tại.
4. **3 nguồn hoá ra là web truyện tranh** (kanman, acqq, cocomanga) — loại thẳng, sai đối tượng crawl.
5. **2 nguồn là light novel Nhật dịch Trung** (linovel, wenku8) — khác hẳn "tiểu thuyết mạng" TQ, cân nhắc riêng nếu sau này muốn mở rộng sang light novel Nhật.
6. **Vài nguồn có nội dung nhạy cảm/18+** cần loại hoặc lọc kỹ nếu app hướng phổ thông: wuwuxs (erotica rõ), shubao45 (nội dung H), 521danmei (có tag H nhưng phần lớn lành mạnh — lọc theo tag).
7. **Domain "trôi giạt" (hay đổi tên miền)** là rủi ro vận hành lâu dài: nếu thêm 1 nguồn vào `sources` table, cần cơ chế phát hiện khi `base_url` chết và cập nhật tay — không thể "set & forget".

## Đề xuất bước tiếp theo

- Thêm trước **11 nguồn nhóm "Có"** vào bảng `sources` (giống cách đã làm với `shuhaige`), test crawl thật với `worker/novelworker/crawler/` để xác nhận cấu trúc HTML bóc tách được.
- Với nhóm "Cân nhắc — chặn bot", chỉ đầu tư nếu 11 nguồn đầu không đủ sản lượng; cần nâng cấp crawler (headless browser) trước.
- Bỏ hẳn nhóm "Không" — không đáng công sức thêm cấu hình riêng cho từng site.
