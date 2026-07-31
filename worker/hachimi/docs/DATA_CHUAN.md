# Data chuẩn để finetune/train — nghiên cứu và tiêu chí nghiệm thu

Viết 31/07/2026, theo yêu cầu: **thôi đuổi theo từng lỗi, xây data cho đúng để lỗi biến mất
theo cả lớp.** Tài liệu này tổng hợp các nghiên cứu đã công bố rồi quy ra tiêu chí đo được cho
dự án. Nó thay thế cách làm cũ ("thấy lỗi → chế booster vá lỗi đó").

---

## 0. Vì sao cách cũ không đưa đi tới đâu

Ba kết quả đã đo của chính dự án, đặt cạnh nhau, chỉ về cùng một nguyên nhân:

| Đã đo | Trước đây giải thích là | Thực ra là |
|---|---|---|
| +62% gold (2.478→4.012 dòng) mà nhịp câu không nhích | "data bão hoà" | **thêm lượng mà không thêm đa dạng** → lợi ích tiệm cận 0 |
| Booster vài chục dòng không đè nổi prior | "model lì" | **tín hiệu mới quá nhỏ so với khối replay đồng nhất** |
| 开口道 → "Nàng" 36 lần / "Hắn" 14 lần | "model nhỏ nên đoán bừa" | **thầy máy có một mặc định, trò học đúng mặc định đó** |

Cả ba đều là **thuộc tính của bộ dữ liệu**, không phải của model. Vá bằng cách thêm vài trăm
dòng chữa cháy là chữa triệu chứng.

---

## 1. Bốn trục chất lượng — nghiên cứu nói gì

### Trục 1 — Nguồn gốc: máy sinh vs người dịch

Đây là trục **quan trọng nhất với dự án**, và cũng là trục dự án đang lệch nặng nhất.

Nghiên cứu về **model collapse** (sụp mô hình) cho thấy: model train đệ quy trên chính output
của model thì suy thoái không hồi phục, và **cái chết trước tiên là phần đuôi phân bố** — các
hiện tượng hiếm. Nhưng kết luận tinh hơn của các nghiên cứu sau mới đáng chú ý:
**vấn đề không nằm ở việc CÓ data máy sinh, mà ở việc data máy sinh THAY THẾ data thật.**
Giữ một "mỏ neo" data thật không co lại thì không sụp; tích luỹ thêm data máy sinh bên cạnh
mỏ neo đó thậm chí còn có lợi.

Chiếu vào dự án: `tran-vi-teacher` (Gemini), toàn bộ `chi-vi` (Gemini/Claude/DeepSeek), và
9.210 chương trong DB (chính Hachimi dịch) — **100% là data máy sinh, không có mỏ neo người
dịch nào.** Đó là mô tả chính xác của kịch bản sụp.

Và "lược chủ ngữ" đúng là **hiện tượng phần đuôi**: nó hiếm hơn câu có chủ ngữ rõ, nên là thứ
bị san phẳng trước tiên. Lỗi "Nàng mở miệng" không phải lỗi lẻ — nó là **triệu chứng của trục này**.

> **Hệ quả hành động:** mọi vòng train sau phải có **tỉ lệ data người dịch tối thiểu**, không
> phải "có thì tốt". Nguồn người dịch đã tìm được: `kaihe/chinese_vietnamese_bilingual_wangwen`
> (90 bộ truyện, bản dịch người, căn theo chương), `moa/Chinese-Vietnamese-literature` (văn học
> cổ điển). Đây là lý do thật sự khiến `kaihe` đáng giá — không phải vì nó to.

### Trục 2 — Đa dạng, không phải số lượng

**LIMA** (Less Is More for Alignment) là kết quả hay được trích nhất: model finetune trên
**1.000 mẫu chọn tay thắng chính nó finetune trên 52.000 mẫu**. Kết luận của họ: *lợi ích giảm
rất nhanh khi tăng lượng mà không tăng đa dạng; còn tăng chất lượng thì lợi ích lớn.*

Đây đúng là kết quả "+62% gold mà không nhích" của dự án, chỉ khác là dự án tưởng đó là trần
của model. Không phải — đó là trần của **cách chọn data**.

> **Hệ quả hành động:** bỏ chỉ tiêu "bao nhiêu dòng gold". Thay bằng chỉ tiêu **phủ bao nhiêu
> KIỂU câu**. Với dự án, các kiểu cần phủ ít nhất: câu lược chủ ngữ · câu có chủ ngữ là đại từ ·
> câu có chủ ngữ là tên riêng · lời kể · thoại · độc thoại trong ngoặc vuông · câu chuỗi phẩy dài ·
> câu có số/thuật ngữ game · câu có ngoặc kép lồng.

### Trục 3 — Nhiễu sinh ra đúng loại lỗi nào

Nghiên cứu **"The Curious Case of Hallucinations in NMT"** (Microsoft) chỉ ra quan hệ nhân quả
cụ thể: **từng dạng nhiễu trong corpus sinh ra từng dạng ảo giác riêng.** Hai dạng nổi bật là
*detached* (bản dịch rời hẳn khỏi nguồn) và *oscillatory* (**lặp đi lặp lại một cụm**). Nghiên
cứu cũng cho thấy **mẫu bị model học thuộc lòng sẽ sinh ảo giác khi gặp nhiễu**, và
**undertranslation** — dịch sót hẳn một phần nguồn — là dạng riêng cần đo riêng.

Chiếu vào dự án: lỗi **lặp từ** anh báo có tên trong y văn là *oscillatory hallucination*, và
nguyên nhân đã biết là **nhiễu corpus**, không phải beam search. Nên chỉnh `repetition_penalty`
chỉ là dán băng dính; muốn hết phải dọn data.

> **Hệ quả hành động:** cổng dọn data phải bắt đúng bốn dạng nhiễu: cặp lệch căn · đích lặp cụm ·
> đích ngắn bất thường so với nguồn (undertranslation) · đích dài bất thường (thêm thắt).

### Trục 4 — Căn chỉnh: cặp có thật sự là bản dịch của nhau không

Đây là trục có sẵn công cụ chín nhất, dùng được ngay:

- **Bicleaner** — bộ phân loại cặp song ngữ sạch/bẩn, ngưỡng thường dùng ≥ 0,5.
- **LaBSE** — nhúng câu đa ngữ; lọc theo **cosine ≥ 0,7**. Trong so sánh với Bicleaner AI thì
  LaBSE tương quan với đánh giá người tốt hơn (0,59-0,68), nên hay được dùng làm thành phần
  chính trong bộ lọc tổ hợp.
- **Margin-based** (Artetxe & Schwenk) — thay vì ngưỡng cứng trên cosine, chấm theo **khoảng
  cách tới các ứng viên gần nhất**; xử lý được chuyện thang điểm không đồng nhất giữa các câu.
- **QE ref-free** (CometKiwi) — chấm chất lượng dịch khi không có bản mẫu; dùng lọc data là
  cách chuẩn hiện nay.

Lưu ý riêng cho `kaihe`: nó **căn bằng thuật toán tự chế** (thực thể + quy hoạch động), chưa
qua bất kỳ bộ lọc nào ở trên. Nên trước khi train phải **chấm lại bằng LaBSE**, đây không phải
việc tuỳ chọn.

---

## 2. Một cơ chế cần hiểu rõ: vì sao chưng cất lại NHÂN bias lên

Nghiên cứu giải thích seq-KD (*"Explaining Sequence-Level Knowledge Distillation as
Data-Augmentation"*) cho thấy chưng cất có tác dụng vì nó **làm phân bố đích ĐƠN GIẢN hơn** —
bản dịch của thầy có entropy thấp hơn bản dịch người, nên trò nhỏ học dễ hơn. Đó chính là lý do
Hachimi 57M dịch được.

Nhưng mặt trái nằm ngay trong cơ chế đó: **cái bị vứt đi khi đơn giản hoá là các lựa chọn thay
thế.** Nếu với câu lược chủ ngữ mà thầy có thói quen chọn "Nàng", thì trò không học "có nhiều
cách", nó học **đúng một cách**. Đo được: 74% số ca trò vẫn còn giữ bản đúng trong beam, nhưng
xếp nó xuống dưới — tức trò **biết**, chỉ là **prior bị lệch**.

> **Hệ quả hành động:** với những construction mình quan tâm (lược chủ ngữ, xưng hô), **không
> được để một mình thầy máy quyết**. Hoặc trộn bản người dịch, hoặc ép cân bằng khi lấy mẫu.

---

## 3. Còn một trục nữa: quên cái cũ

Nghiên cứu EMNLP 2024 *"Domain adapted MT: what does catastrophic forgetting forget and why?"*
chỉ rõ quên biểu hiện thế nào: **dùng từ vựng của domain mới vào ngữ cảnh không thuộc domain đó.**

Chiếu vào dự án: đây đúng là rủi ro khi ép giọng cổ phong — model sẽ nhét "ta/ngươi" vào **mô tả
truyện, tên truyện, tiêu đề chương**, chỗ mà tiếng Việt hiện đại mới đúng. Dự án đã có replay để
chống quên, nhưng replay hiện **cùng một nguồn gốc** với gold nên chống được ít.

> **Hệ quả hành động:** replay phải **khác domain thật sự** (câu đời thường, mô tả, tên) và nên
> **gắn tag domain** để model biết lúc nào dùng giọng nào — thay vì trộn trần rồi mong nó tự hiểu.
> Đây là chỗ dùng đúng của `thevan2404/merged-zh-vi-sentences-clean`.

---

## 4. Bộ tiêu chí nghiệm thu data (dùng cho MỌI vòng train sau)

Một lô data chỉ được đưa vào train khi qua đủ 4 cổng. **Ngưỡng dưới đây là ĐỀ XUẤT ban đầu, phải
hiệu chỉnh từ dữ liệu tham chiếu trước khi tin** — đúng bài học đã ghi ở `hachimi_rhythm_research.md`.

| # | Cổng | Đo bằng | Ngưỡng đề xuất |
|---|---|---|---|
| 1 | **Căn đúng** | LaBSE cosine (nguồn, đích) | ≥ 0,70; lô nào có >5% dưới ngưỡng thì trả về |
| 2 | **Tỉ lệ độ dài** | ký tự đích / ký tự nguồn | nằm trong [2,0 – 4,5]; ngoài khoảng = nghi sót/thêm |
| 3 | **Không lặp** | n-gram 3-4 lặp trong dòng, **trừ điệp ngữ có trong nguồn** | 0 ca lặp không có gốc ở nguồn |
| 4 | **Nhất quán xưng hô** | **một nhân vật có bị gọi hai kiểu không** (nàng vs cô, hắn vs anh ta) — KHÔNG phải "có chứa từ hiện đại không" | ≤ 10% chương xung đột |
| 4b | **Không "anh/em" sến trong văn kể** | đếm "anh"/"em" làm xưng hô ngôi 1-2 ngoài thoại-tình-cảm | loại chương ngôn tình đầy anh/em (user chốt 31/07: hắn/cô OK, ta-ngươi OK, nhưng "anh/em" sến không hợp văn viết) |

**Gu register user đã chốt (31/07):** **hắn/cô chấp nhận được** (không bắt buộc hắn/nàng), ta-ngươi
tốt, nhưng **"anh/em" là sến, không hợp văn viết** — phải lọc. Nỗi lo chính khi finetune là **lộn
xộn giọng** (chương này hắn/cô, chương kia hắn/nàng), nên cổng 4 (nhất quán) quan trọng hơn việc
ép một quy ước duy nhất. Đây là lý do kaihe (register hắn/cô) DÙNG ĐƯỢC, chỉ cần lọc phần anh/em.

Cộng thêm **hai điều kiện về thành phần lô**, không phải về từng dòng:

| # | Điều kiện | Vì sao |
|---|---|---|
| 5 | **≥ 20% dòng đến từ bản dịch NGƯỜI** | mỏ neo chống sụp (trục 1) |
| 6 | **Phủ đủ 9 kiểu câu ở trục 2**, không kiểu nào < 5% | chống "thêm lượng không thêm đa dạng" |

Và **một cổng không thể tự động hoá**: đọc tay 50 dòng mỗi lô. Dự án đã trả giá cho bài học
"cổng đo được thì thầy tối ưu được" — bỏ bước này là mời nó quay lại.

---

## 5. Quy trình dựng data cho vòng train tới

1. **Gom nguồn** theo thứ tự ưu tiên: người dịch (`kaihe`, `moa`) → thầy máy (`tran-vi-teacher`,
   `chi-vi` nếu duyệt) → tự sinh từ kho R2 của mình.
2. **Khử trùng lặp** trước mọi bước khác (trùng lặp làm sai lệch mọi thống kê phía sau).
3. **Chạy 4 cổng** ở mục 4, ghi lại số dòng rơi ở từng cổng — con số đó cho biết nguồn nào bẩn.
4. **Phân loại theo 9 kiểu câu**, xem kiểu nào thiếu, chỉ bổ sung đúng kiểu thiếu.
5. **Cân bằng construction nhạy cảm**: với câu lược chủ ngữ, ép tỉ lệ bản-không-chủ-ngữ đủ cao
   thay vì để phân bố tự nhiên của thầy quyết.
6. **Chốt tỉ lệ trộn** rồi ghi vào manifest, không trộn tuỳ hứng mỗi lần.
7. **Đọc tay 50 dòng**, rồi mới train.

---

## 6. Những việc KHÔNG nên làm nữa

- **Chế booster vài trăm dòng để vá một lỗi cụ thể.** Đã đo là không đè nổi prior, và nó chính
  là kiểu "chạy theo từng lỗi" cần bỏ.
- **Lọc data bằng cách cấm từ.** Sai — tiêu chí là nhất quán, không phải cấm từ. Đã suýt vứt
  nhầm 80% một dataset tốt vì lỗi này.
- **Tăng số dòng gold rồi kỳ vọng chất lượng tăng theo.** Trục sai.
- **Train tiếp trên output của chính mình** (9.210 chương trong DB) mà không có mỏ neo người dịch.

---

## Nguồn

- Model collapse: [AI models collapse when trained on recursively generated data](https://www.researchgate.net/publication/382526401_AI_models_collapse_when_trained_on_recursively_generated_data) · [Preventing Model Collapse in the Synthetic-Data Era](https://cseweb.ucsd.edu/~yuxiangw/classes/AIsafety-2025Fall/Lectures/preventing_model_collapse_suraj.pdf)
- Chất > lượng: [LIMA: Less Is More for Alignment](https://arxiv.org/pdf/2305.11206) · [A Survey on Data Selection for LLM Instruction Tuning](https://www.jair.org/index.php/jair/article/download/17625/27213/48346)
- Nhiễu sinh ảo giác: [The Curious Case of Hallucinations in NMT](https://arxiv.org/pdf/2104.06683) · [Detecting Hallucinated Content in Conditional Neural Sequence Generation](https://arxiv.org/pdf/2011.02593)
- Lọc corpus: [Bicleaner](https://github.com/bitextor/bicleaner) · [Margin-based Parallel Corpus Mining](https://arxiv.org/pdf/1811.01136) · [Score Combination for Improved Parallel Corpus Filtering](https://arxiv.org/pdf/2011.07933)
- Chưng cất & quên: [Explaining Seq-KD as Data Augmentation](https://www.researchgate.net/publication/337855833_Explaining_Sequence-Level_Knowledge_Distillation_as_Data-Augmentation_for_Neural_Machine_Translation) · [What does catastrophic forgetting forget and why](https://aclanthology.org/2024.emnlp-main.704.pdf) · [KD4MT: A Survey of Knowledge Distillation for MT](https://arxiv.org/pdf/2602.15845)
