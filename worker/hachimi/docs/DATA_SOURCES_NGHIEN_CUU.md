# Nghiên cứu nguồn data dịch Trung-Việt và phương án train model mới (2026-07-24)

Rà nguồn public (Hugging Face, Kaggle, GitHub, academic) cho bài toán finetune/train model dịch
Trung→Việt cho truyện web. Có hai nguồn đáng nghiên cứu thêm là **VnAPE** và
**VietPhrase/QuickTranslator**, nhưng sau khi đọc paper và kiểm giấy phép, **không nguồn nào là corpus
Trung→Việt sạch có thể đổ thẳng vào một lần train mới**:

- VnAPE là **Việt thô → Việt đã sửa**, không có câu nguồn Trung.
- VietPhrase là từ điển/luật convert, không phải cặp câu song ngữ; repo dữ liệu không có giấy phép.

Vì vậy chúng phù hợp với APE, glossary hoặc sinh ca thử nghiệm hơn là làm nền cho model dịch mới.

**Đính chính sau khi đọc toàn văn paper:** các số “5.028.749 cặp câu”, “283→183 tiểu thuyết” và
“99,5 nghìn chương” đều có thật trong mục Dataset construction của
[paper VnAPE](https://ar5iv.labs.arxiv.org/html/2104.12128). Kết luận cũ cho rằng các số này bị bịa
là sai. Sai sót thật sự là đã hiểu hai file tải in-domain/out-of-domain thành hai corpus độc lập và
đã đánh giá quá cao khả năng dùng VnAPE để train trực tiếp Trung→Việt.

## Có thật và đúng domain, nhưng phải dùng đúng vai trò

- **VnAPE** — https://github.com/tienthanhdhcn/VnAPE (Thanh Vu & Dai Quoc Nguyen/Oracle Labs, đi kèm
  paper "Automatic Post-Editing for Vietnamese", arXiv [2104.12128](https://arxiv.org/abs/2104.12128),
  ALTA 2021).
  - Paper xác nhận đúng **5.028.749 cặp câu**, căn từ **99,5 nghìn cặp chương của 183 truyện** được
    chọn từ 283 truyện có cả bản convert và bản sửa.
  - Hai file tải “in-domain” và “out-of-domain” là **hai cách chia cùng kho 5 triệu cặp**; không phải
    10 triệu cặp độc lập.
  - Cả đầu vào lẫn đầu ra đều là tiếng Việt: **bản convert bằng phần mềm → bản người sửa**. Tác giả
    nói rõ họ không truy cập được nguyên tác Trung, nên VnAPE **không thể train trực tiếp ZH→VI**.
  - Về kỹ thuật, nó hợp để thử một model hậu biên tập riêng hoặc mine quy tắc sửa văn convert. Nó
    không khớp trực tiếp phân bố lỗi của Hachimi hiện nay nếu chưa đo trên mẫu thật.
  - Về pháp lý, repo có file MIT nhưng paper và README ghi phát hành dataset/model cho
    **research-only purpose**. Hai tín hiệu mâu thuẫn; không đưa vào model production hoặc phát hành
    lại trước khi tác giả xác nhận quyền sử dụng.
  - Do thêm một model APE sẽ tạo lượt suy luận thứ hai trên VPS 2 nhân, đây không phải ưu tiên trước
    khi pipeline dịch một lượt hiện tại được tối ưu xong.

- **VietPhrase / QuickTranslator (kho quy ước dịch cộng đồng "convert" VN)** — nguồn cộng đồng, KHÔNG
  phải academic/HF, đã 10+ năm tích luỹ qua hàng vạn truyện. Repo:
  [truyencuatui/VietPhrase](https://github.com/truyencuatui/VietPhrase) (data),
  [dynamotn/QuickTranslator](https://github.com/dynamotn/QuickTranslator) (app Windows đọc data này),
  [duxonem/Vietphrase-Extension](https://github.com/duxonem/Vietphrase-Extension) (bản extension,
  bổ sung cơ chế "Structphrase" mới hơn cho luật câu). App: https://vietphrase.app/
  - `VietPhrase.txt` — **878,8K mục**, cụm Hán→Việt/Hán-Việt. Cùng vai trò với `hanviet.tsv` của dự
    án nhưng lớn hơn nhiều lần và ở mức CỤM TỪ (không chỉ từng chữ) — đáng đối chiếu bổ sung
    `hanviet.tsv`/glossary cho các cụm chưa phủ.
  - `Names.txt` — **158,8K mục** tên riêng nhân vật/tông phái/địa danh quét từ hàng vạn truyện — trực
    tiếp giải quyết đúng vấn đề "chữ Hán hiếm model đoán bừa tên" đã note trong
    [[hachimi-game-finetune]] — đáng đối chiếu bổ sung glossary auto-fill.
  - `LuatNhan.txt` — **~24K quy tắc** pattern cú pháp dạng `不比{0}强=không mạnh bằng {0}` (chuyển đổi
    theo khuôn mẫu, không phải dịch từng chữ) — **đúng vào điểm yếu "đảo mệnh đề/câu dài" của Hachimi
    57M** đã ghi nhận là chấp nhận-vì-giới-hạn-model. Có thể dùng làm khuôn sinh data booster tổng hợp
    kiểu đã làm ở `04_make_booster.py`, nhưng nhắm vào cấu trúc câu thay vì đại từ.
  - `LacViet.txt` (~66,4K), `ChinesePhienAmWords.txt` (~12,6K phiên âm Hán-Việt từng chữ) — bổ trợ,
    giá trị thấp hơn 3 file trên, trùng lặp nhiều với chức năng `hanviet.tsv` đã có.
  - **Giấy phép:** README của repo dữ liệu chỉ có tiêu đề và repo không có file `LICENSE`. Public trên
    GitHub không đồng nghĩa được phép dùng để train/phát hành model. Chỉ dùng để benchmark nội bộ
    cho tới khi xác minh được nguồn và quyền sử dụng.
  - `LuatNhan.txt` có thể gợi ý ca kiểm thử cấu trúc, nhưng không được coi mỗi luật là một cặp dịch
    tự nhiên đã duyệt. Không trộn thẳng vào gold.

## Đã dùng / họ hàng với model đang có

- **`ngocdang83/tran-vi-teacher`** (HF dataset) — 350.751 dòng, teacher Gemini 2.5/3.0/3.1, chuyên
  webnovel. Đây LÀ data gốc pretrain Hachimi, không phải nguồn mới.
- **`chi-vi/hirashiba-mt-zh2vi-b-filtered`** — đã nằm trong base Hachimi theo model card.
  Không được suy ra bản unfiltered `hirashiba-mt-zh2vi` cũng đã được dùng.

## Đáng thử — tổ chức `chi-vi` (Chivi)

Non-profit NLP tiếng Việt, chuyên đúng mảng dịch truyện Trung-Việt. https://huggingface.co/chi-vi

| Tên | Loại | Quy mô | Ghi chú |
|---|---|---|---|
| `chi-vi/hirashiba-mt-zh2vi-b-filtered` | dataset | 5,98GB; chưa công bố số dòng | Bản lọc đã dùng trong Hachimi base. Trang gated không có dataset card. Con số 15.132.501 thuộc bản `hirashiba-mt-zh2vi` không lọc, không được tự gán sang bản `b-filtered`. |
| `chi-vi/novel_ner_v2` | model NER | 0.3B | NER chuyên nhận diện tên riêng TRONG TRUYỆN. **Đáng thử thay LLM `_analyze_names`** cho auto-điền glossary (rẻ hơn gọi LLM/chương) — lưu ý dự án từng thử jieba NER và loại (sai trên tiên hiệp), nhưng NER train riêng cho truyện có thể khác, cần đo lại chứ không suy luận. |
| `chi-vi/hirashiba-mt-tiny-zh-vi` | model dịch | 14,8M tham số | Nhỏ hơn cả Hachimi (57M), cùng dòng họ. Ứng viên so sánh nếu nghi ngờ trần chất lượng. |
| `chi-vi/gemma-3-1b-novels` | model | 1B | Gemma finetune cho truyện — ứng viên benchmark thêm (nhưng nhớ bài học "base to hơn đã thử hết, thua Hachimi + chậm" — đo trước khi đầu tư). |
| `chi-vi/chivi-modern-bert`, `chivi-lert-base` | model | 0.1B | Fill-mask tiếng Việt, không phải dịch — có thể hữu ích cho QC/phân loại, không liên quan trực tiếp finetune dịch. |
| `chi-vi/hirashiba-mt-jp-names` | dataset | 378k | Nhật-Việt, không áp dụng (dự án chỉ Trung-Việt). |
| `chi-vi/cachua-zh2vi` | dataset | ~115MB, cập nhật liên tục | **ĐÃ ĐÁNH GIÁ THẤP HƠN dự kiến sau khi verify** — nội dung là bản dịch THÔ bằng Gemini Flash 2.0, tự dataset card ghi nhận lỗi "mất ngữ cảnh liên đoạn, đứt mạch hội thoại, trộn ngôn ngữ" — CHƯA hậu xử lý, bẩn hơn cả `tran-vi-teacher` đang dùng làm base. Không nên xếp cao, cần lọc nặng nếu dùng. |

## Academic khác

- **VLSP 2022 MT task** (https://vlsp.org.vn/vlsp2022/eval) — 300k cặp câu song song (train) + 1000
  câu dev/test + corpus đơn ngữ (25M câu Việt, 19M câu Trung). Domain tin tức/chung, cần đăng ký với
  ban tổ chức VLSP/VNU-UET để tải. Có paper hệ thống dự thi: [VBD-MT Chinese-Vietnamese Translation
  Systems for VLSP 2022](https://arxiv.org/abs/2308.07601).
- Nghiên cứu back-translation (arXiv [2003.02197](https://arxiv.org/pdf/2003.02197)) — sinh 211K cặp
  zh→vi bằng back-translation, chỉ là thí nghiệm nội bộ paper, không phải dataset công khai tải được.

## Hai corpus văn học Trung–Việt đã tải mẫu và chạy thật

- **`moa/Chinese-Vietnamese-literature`** (HF, `CC-BY-SA-4.0`) — 396.307 dòng. Audit local thấy
  244.105 dòng qua gate hình thức nhưng có đoạn lệch hàng thật. Pilot chỉ giữ 2.000/5.000 cặp có
  output gần Hachimi gốc nhất; model tăng similarity nhưng tăng đại từ hiện đại từ 15 lên 21 trên
  eval khóa. **Không dùng tiếp**; xem `experiments/hachimi_external_replay_pilot.md`.
- **`kaihe/chinese_vietnamese_bilingual_wangwen`** (HF, `Apache-2.0`) — đúng domain truyện mạng,
  tác giả công bố 90 truyện gốc và căn theo chương/câu. Tuy nhiên ngay sample chapter đầu đã có bản
  Việt tự thêm và bỏ thông tin so với nguồn Trung. **Không tự động dùng làm gold/replay** nếu chưa
  căn lại và duyệt từng cặp.

## Nguồn khác đã tra — domain lệch hoặc chất lượng thấp

- **Nexdata-AI** (https://www.nexdata.ai/datasets/nlu/1170) — 7,29 triệu cặp Trung-Việt, nhưng
  **trả phí**, domain du lịch/y tế/tin tức/đời thường — lệch hẳn văn phong tiên hiệp/cổ phong.
- **Kaggle `flightstar/chinese-vietnamese-dataset`** (https://www.kaggle.com/datasets/flightstar/chinese-vietnamese-dataset,
  đăng 2018, thuộc bộ "Foreign-Languages-Database" của cùng tác giả trên GitHub
  https://github.com/flightstar/Foreign-Languages-Database) — nhiều khả năng là **danh sách từ/cụm
  từ điển-cấp**, không phải câu tự nhiên dài — thấp giá trị cho finetune model dịch văn xuôi. Chưa
  tải để xác nhận cấu trúc thật, nhưng nhiều dataset cùng tác giả (Vietnamese-Korean, Vietnamese-Japanese...)
  cùng pattern → khả năng cao đều kiểu từ điển.
- **`Alsebay/Vi-Novel-Translate-Collection-Dataset`** (HF) — 3,9k dòng, **CHỈ tiếng Việt** (văn bản
  kiếm hiệp đã dịch sẵn), không phải cặp song ngữ. Có thể dùng làm corpus văn phong tiếng Việt thuần
  nếu cần, nhưng dự án đã có sẵn hàng nghìn chương production tiếng Việt rồi nên không cần thêm.
- **`haruyuu/MarianMT_zh-vi_Expanded_Vocab`** (HF model) — finetune MarianMT trên 170k dòng hội
  thoại/thông báo game MMORPG Trung-Việt — **rất giống** việc đã làm ở nhánh GameV2-V4, nhưng dataset
  gốc KHÔNG public, chỉ có model.

## Corpus webnovel song ngữ — đúng METHODOLOGY nhưng SAI cặp ngôn ngữ (zh-en, không phải zh-vi)

Không dùng trực tiếp được, nhưng đáng biết vì cho thấy cách corpus webnovel "chuẩn" được xây — có
thể tham khảo phương pháp căn dòng chapter-level nếu sau này muốn tự xây corpus zh-vi tương tự.

- **GuoFeng-Webnovel** (https://github.com/longyuewangdcu/GuoFeng-Webnovel, Tencent AI Lab + China
  Literature) — v1: 179 truyện/22.567 chương, 1,9M+ cặp câu căn dòng XML, zh→en, 14 thể loại. v2
  (5/2024): thêm zh→de (~120 truyện/19k chương) và zh→ru (~122 truyện/20k chương), chỉ căn cấp
  chương. License CC BY 4.0 phi thương mại, phải đăng ký (Google/Tencent form) lấy link Dropbox/Weiyun.
  Cấm sửa/phát tán lại.
- **BWB corpus** — 196K chương, 9,6M cặp câu, zh-en, quy mô lớn hơn GuoFeng nhưng cũng zh-en.
- **Qidian-Webnovel Corpus** (Journal of Open Humanities Data,
  https://openhumanitiesdata.metajnl.com/articles/10.5334/johd.368) — 110 truyện Qidian.com/Webnovel.com,
  chủ yếu **bình luận độc giả + metadata** (2,79M comment Trung + 238k comment Anh), KHÔNG phải cặp
  câu dịch dùng để train MT — mục đích nghiên cứu reader-response, không áp dụng.

## Ý tưởng DIY (chưa làm, ghi lại để cân nhắc sau)

Dự án đã có sẵn hạ tầng crawl tiếng Trung (shuhaige/ddxs/xsbique) + nhiều "truyện convert" tiếng Việt
do người dịch tay đã có sẵn trên các site như truyenfull.vn / metruyencv.com / bachngocsach.com. Về lý
thuyết có thể **tự xây corpus zh-vi bằng cách căn chương** (cùng truyện, cùng số chương, nguồn Trung
crawl sẵn + bản Việt người dịch tay công khai) — giống cách GuoFeng làm cho zh-en. Có sẵn tool scraper
tham khảo cấu trúc: `tinotk/thuvienbao-truyen-scraper` (hỗ trợ truyenfull.vn, truyencv.com, bachngocsach.com),
`nguyentd01/metruyencv_downloader`. **CHƯA đánh giá:** chất lượng dịch tay có đồng nhất/đủ tốt để làm
teacher không, vấn đề bản quyền khi dùng bản dịch người khác để train, và công sức căn chương/lọc rác
(quảng cáo, dịch bỏ đoạn) — chỉ là hướng mở, không phải khuyến nghị làm ngay.

## Train model mới từ số 0 hay fine-tune Hachimi?

### Trạng thái đã kiểm chứng trong repo

- Base `ngocdang83/HachimiMT-60-zh-vi` là Marian bất đối xứng **56,94M tham số**:
  8 encoder + 2 decoder, `d_model=512`, vocab SentencePiece chung 24K, context tối đa 512.
  `config.json` local khớp model card.
- Model card ghi hai nguồn train chính: 350.751 dòng strict-clean của `tran-vi-teacher` và
  `hirashiba-mt-zh2vi-b-filtered`. Nguồn thứ hai không có card, không công bố recipe train và
  không cho biết số dòng bản filtered. Vì vậy hiện **không tái lập chính xác được lần train gốc**.
- Data đã duyệt thật trong vòng hiện tại mới có **200 gold + 60 eval khóa**. Pilot fine-tune dùng
  thêm 4.949 replay local:
  - gold ×1: similarity 0,5245;
  - gold ×3: similarity 0,5384;
  - model hiện tại: 0,5270.
  Bản gold ×3 vẫn bị giảm nhóm `semantic_context` 5,2% và tăng lỗi dấu thoại, nên đã bị loại.
- Tokenizer hiện tại không phải nút thắt trên data đã duyệt. Trên 200 gold, nguồn trung bình 51,6
  token, p90=89, p99=110; trên 60 eval, trung bình 72,2, p90=143, p99=165. Không dòng nào vượt 448.
  Vấn đề thật là engine production tách nguồn ở khoảng 90 token, trong khi model và data có thể dùng
  context dài hơn.

### Thử một model 57M khác đã train từ đầu

Đã tải tạm và chạy `DanVP/MoxhiMT-60` trên đúng 60 cảnh eval khóa, cùng `_Engine`, split và
CT2 INT8; không glossary và không hậu xử lý để so raw công bằng. Model card của Moxhi ghi rõ đây là
model train từ đầu với tokenizer 24K riêng, 8 encoder + 2 decoder, khoảng 57M tham số.

| Model raw | Similarity TB | Thắng theo similarity | Thời gian 60 cảnh |
|---|---:|---:|---:|
| Hachimi base | 0,5236 | 21 | 9,97 giây |
| CT2 hiện tại | **0,5309** | **25** | 10,12 giây |
| MoxhiMT-60 train từ đầu | 0,4955 | 14 | 11,13 giây |

Moxhi còn có 22 ca đại từ hiện đại, 2 ca lệch quote và similarity nhóm `semantic_context` chỉ
0,3677, so với 0,4234 của Hachimi base. `Similarity` không thay thế đọc nghĩa, nhưng các mẫu thấp
điểm cũng lộ lỗi thật như sót mảnh Latin `xing`, gắn sai quan hệ và văn convert. Thử nghiệm này
không chứng minh mọi model train từ đầu đều thua; nó chứng minh rằng **khởi tạo mới cùng cỡ và cùng
kiến trúc không tự tạo ra bước nhảy chất lượng**.

### So sánh phương án

| Phương án | Lợi ích có thể đạt | Giá phải trả / rủi ro | Kết luận |
|---|---|---|---|
| Fine-tune Hachimi base bằng gold dài đã duyệt + replay sạch | Rẻ nhất; giữ từ vựng truyện và tốc độ đã có | Pilot 200 gold chưa đủ; phải sửa lệch đơn vị train–inference trước | **Nên làm tiếp** |
| Train lại Marian 57M từ random init bằng cùng data | Chủ động tokenizer, cách trộn và recipe | Phải học lại toàn bộ từ vựng; cùng trần năng lực 57M; recipe/data gốc thiếu; benchmark Moxhi không cho lợi thế | **Không đáng** |
| Train từ đầu model 80–150M | Thêm dung lượng cho câu phức | Chậm hơn trên VPS, cần corpus sạch lớn và nhiều GPU hơn; chưa có bằng chứng data hiện tại đủ tốt | **Chưa đáng** |
| Fine-tune model đa ngữ 300–600M như NLLB/M2M100 | Có pretrain rộng, không phải học ngôn ngữ từ đầu | Thử NLLB 600M trước đây chỉ khoảng 5 chữ/s trên CPU 2 nhân và vẫn sai thuật ngữ tu tiên | **Không hợp production** |
| Distill teacher mạnh offline vào student 60–100M | Có thể tạo model mới nhưng vẫn giữ runtime gọn; không gọi LLM trong nhánh chạy thật | Cần corpus ZH→VI được kiểm soát, eval tốt và một vòng train nghiêm túc | **Hướng mới đáng nghiên cứu nhất, nhưng sau khi data qua gate** |
| Hachimi + model APE VnAPE | Có thể sửa văn convert/register sau dịch | Input VnAPE khác Hachimi; thêm lượt model thứ hai; giấy phép research-only chưa rõ | **Không ưu tiên** |

### Khuyến nghị thực hiện

1. **Không train từ số 0 lúc này.** Cùng kiến trúc 57M chỉ tốn công để quay lại cùng trần; model
   lớn hơn lại phá ràng buộc VPS trước khi chứng minh được chất lượng.
2. Giữ `ngocdang83/HachimiMT-60-zh-vi` làm checkpoint khởi đầu, nhưng không lặp lại pilot gold ngắn.
   Trước tiên phải tạo gold đúng đơn vị suy luận: cảnh 120–180 token hoặc cơ chế đưa ngữ cảnh trước
   vào encoder nhưng chỉ sinh câu hiện tại.
3. Nâng tập duyệt từ 200 lên khoảng **1.200 cảnh thật** đã đề xuất trong
   `hachimi_base_longform_audit.md`, tập trung chủ thể, quan hệ, phủ định, số và thoại có lời dẫn.
   Tên riêng hiếm vẫn giao glossary/termguard, không bắt model học thuộc.
4. Chạy một pilot fine-tune từ base với replay sạch và eval khóa. Chỉ khi phương án này vẫn không
   vượt cổng đọc nghĩa mới mở nhánh **student mới 80–100M + distillation offline**.
5. Trước mọi lần train mới, phải chốt quyền sử dụng của `hirashiba-mt-zh2vi-b-filtered`,
   VnAPE và VietPhrase. “Tải được” không phải bằng chứng được phép đưa vào model phát hành.

## Kết luận (cập nhật)

**Train mới từ số 0 hiện không đáng giá.** Data mới tìm được không lấp khoảng trống corpus ZH→VI
sạch, benchmark một model 57M train từ đầu khác còn thua Hachimi, còn model lớn hơn không hợp CPU
2 nhân. Giá trị tốt nhất vẫn là sửa data và đơn vị ngữ cảnh rồi fine-tune từ Hachimi base.

VnAPE chỉ nên giữ như ứng viên nghiên cứu APE nội bộ sau khi làm rõ giấy phép. `LuatNhan.txt` chỉ nên
dùng gợi ý ca test/cấu trúc, không trộn thẳng thành gold. Nếu fine-tune đúng dữ liệu vẫn không vượt
trần, hướng nâng cấp hợp lý là distill offline sang student 80–100M, không phải train lại ngẫu nhiên
một Marian 57M tương tự.
