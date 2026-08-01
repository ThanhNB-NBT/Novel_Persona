# Nâng chất lượng dịch — nghiên cứu & kế hoạch (31/07/2026)

Viết sau khi chủ dự án đọc ~40 chương bản teacher-v4 và báo: **đa số ổn**, nhưng còn
(1) sai xưng hô/giới tính trong thoại, (2) lặp từ, (3) một số lỗi khác — nặng nhất là truyện
**"Phản phái: Bất hủ đế tộc, tông nhân toàn là lão lục"** (`novel_id=2163`), từ chương 5.

**Ràng buộc chủ dự án đã chốt (31/07):**
1. **Giữ VPS 2 vCPU, chỉ model nhỏ.** Không lên GPU, không lên API. Model ≥0,5B chỉ được dùng
   làm **thầy sinh data**, không bao giờ vào production.
2. **Tốc độ phải theo kịp crawl, KHÔNG có con số trần cố định.** *(Sửa 31/07: "trần 86 s/chương"
   ở bản trước là suy sai từ cap 1000 chương/ngày trong tài liệu bàn giao — cap thật là **10000**
   (`docker logs` xác nhận), mà 86400/10000 = 8,6 s còn thấp hơn tốc độ hiện tại 9,7 s. Nghĩa là
   cap không phải mục tiêu thông lượng, nó chỉ là chốt an toàn.)* Ràng buộc thật: bản dịch phải
   **theo kịp tốc độ crawl** — doc-level chậm 1,5-2× thì phải **đo before/after trên VPS** rồi so
   với lượng chương thực tế về mỗi ngày, không so với một con số bịa.
3. **Dịch lại kho cũ: hoãn quyết định** — train xong model mới rồi tính.
4. Bậc 1 (đổi base) **do số đo quyết định**, không do card model của tác giả nói.

---

## 1. Ngành dịch đo "đạt chuẩn" bằng cái gì

| Tầng | Là gì | Mình đang có |
|---|---|---|
| **Ref-based** | BLEU/chrF (cùn với văn học), **COMET-22** (neural, sát người) | "similarity" tự chế |
| **Ref-free (QE)** | **CometKiwi**, MetricX-QE — chấm khi không có bản mẫu; dùng chọn n-best và **lọc data train** | `_rank_penalty` viết tay |
| **Human / MQM** | Chuẩn công nghiệp: gán **span lỗi** + **loại** (accuracy/fluency/terminology/style) + **mức nặng**. Bản LLM hoá **GEMBA-MQM** đạt 96,5% khớp xếp hạng người ở WMT23 | chưa có |

Ba điều rút ra:

1. **Lỗi của mình là lỗi diễn ngôn (discourse-level).** Xưng hô sai, giới sai, tên đổi giữa
   chừng — ngành gọi là anaphora / lexical consistency / register consistency, và kết luận đã
   đóng từ lâu: **model dịch từng câu không sửa được bằng thêm dữ liệu từng câu.** Khớp đúng
   thứ mình đã đo mà chưa gọi tên ("+62% gold mà nhịp câu không nhích").
2. WMT có shared task **Discourse-Level Literary Translation** (2023/2024) trên **GuoFeng
   Webnovel Corpus** — đúng bài toán của mình. Mượn phương pháp: test chia **Simple** (chương
   mới của truyện đã train) / **Difficult** (truyện chưa từng thấy).
3. **QE-reranking** nâng chất lượng **không cần train lại**. Mình đã làm đúng ý tưởng đó
   (n-best 6 + `_rank_penalty`), chỉ là "giám khảo" đang là regex.

---

## 2. Bằng chứng đo được — 45 chương truyện 2163 (6.017 dòng)

Không đợi mai: đã kéo chương 1-45 từ DB và quét. Đây là **số thật**, không phải suy đoán.

### 2.1 Lỗi giới trong lời kể — có một thủ phạm cụ thể

| Đo | Số |
|---|---|
| Dòng mở đầu bằng **"Hắn"** | 112 |
| Dòng mở đầu bằng **"Nàng"** | **61** ← truyện này nhân vật chính là **nam** |
| Trong đó là cụm **"Nàng mở miệng…"** | **36 / 61 (59%)** |
| Đối chứng: **"Hắn mở miệng…"** | 14 |

→ Cụm nguồn **`开口道`** (lược chủ ngữ) bị model gán **"Nàng" 36 lần / "Hắn" 14 lần = 72% lệch nữ**,
trong một truyện gần như toàn nhân vật nam. Ví dụ chương 5:

```
Nhẹ nhàng xua tay.
Nàng mở miệng nói: "Không cần đâu. Hôm nay ta chỉ vì Minh Nguyệt tiểu thư mà đến…"
```

**Đây không phải "model nhỏ nên dốt ngẫu nhiên" — đây là một prior lệch, khu trú vào đúng một
cụm nguồn, đo được bằng máy.** Cả 36 ca đều là dòng mà **nguồn không có 他/她** (câu trước là
"Nhẹ nhàng xua tay." — cũng lược chủ ngữ). Nghĩa là:
- phạt lệch giới bằng đối chiếu 他/她 **không cứu được** nhóm này (nguồn không có đại từ để đối chiếu);
- **chỉ ngữ cảnh mới cứu được** → đây là bằng chứng thực nghiệm cho bậc 2, không còn là lý thuyết.

### 2.2 Lỗi giới trong THOẠI — là lỗi thuật ngữ, sửa ở glossary

```
Giang Trần tức giận lên tiếng: "Cái gì, Tiêu Vân dám nhắm vào bản thiếu nữ…"
```
`本少爷` (bản thiếu gia) → **"bản thiếu nữ"**. Đúng loại "lỗi ánh xạ cố định" mà dự án đã kết
luận là **phải sửa ở glossary, không phải data**. Cần rà cả họ: 本少爷/本公子/本座/本尊/本王.

### 2.3 Register hiện đại lọt — vì regex thiếu từ

Đếm trong 45 chương: **"người đàn ông" 24**, **"ông ta" 9**, "người phụ nữ" 3, "cô gái" 1, "anh ta" 1.

`_MODERN_VI` ([hachimi_engine.py:48](../../novelworker/translator/hachimi_engine.py:48)) hiện là
`tôi|mình|bạn|cậu|cháu|anh ta|cô ta|cô ấy|ông ta|bà ta` — **không có** "người đàn ông / người
phụ nữ / cô gái / chàng trai". Thêm vào là bịt được nhóm 28 ca. (Chú ý "ông ta" **có** trong
regex mà vẫn lọt 9 lần → khi cả 6 giả thuyết beam đều dính thì n-best không cứu được; cần
hậu xử lý, không chỉ chấm điểm.)

### 2.4 Tên riêng đổi giữa chừng

Cùng một địa điểm, trong cùng truyện: **"Thiên Hương Lâu" 7 lần / "Thiên Hương Các" 17 lần**
(chương 5 dùng cả hai, cách nhau 19 dòng). Đúng loại lỗi glossary+termguard chịu trách nhiệm.

### 2.5 Lặp từ — quét máy CHƯA xác nhận

Quét cụm 3-4 tiếng lặp trong dòng: **37/6017 dòng**, và đọc tay thì **phần lớn là điệp ngữ cố ý
của nguyên tác** ("Ba mươi năm Hà Đông ba mươi năm Hà Tây", "Người không phạm ta, ta không phạm
người"). **Chưa tìm thấy lỗi lặp máy móc trong truyện này.**
→ Cần chủ dự án chỉ đúng ca lặp đang khó chịu (chương nào), nếu không bậc 0 sẽ chỉnh
`repetition_penalty` mù và **phá điệp ngữ đúng**.

### 2.6 Lỗi dịch sai nghĩa — trần của model 57M

`Gương mặt ửng hồng như linh hồn chín muồi` (nguồn gần như chắc là 水蜜桃 — quả đào chín),
`chỉ có nhan sắc của ngươi mới có thể chống lại ta` (nam nói với nam). Loại này **không có
mẹo nào vá được** — chỉ model to hơn hoặc data tốt hơn. Đây là chỗ để đánh giá xem 57M đã là
trần chưa.

### 2.7 ĐỐI CHIẾU NGUỒN — thủ phạm thật là "model tự bịa chủ ngữ"

`content_zh` **không mất**: đã offload sang Cloudflare R2 (`blob.get_zh`), lấy về đủ **45/45
chương**, số dòng khớp 45/45. Không phải cào lại. Đối chiếu từng dòng cho kết quả sắc hơn hẳn:

| Dòng mở đầu bằng đại từ | Nguồn CÓ 他/她 (đúng) | Nguồn KHÔNG có đại từ (**model bịa**) |
|---|---|---|
| "Hắn …" | 62 | **50** |
| "Nàng …" | 21 | **33** |

Nguồn điển hình: `开口说道：“…”`, `低声道：“…”`, `当即开怀畅饮。` — **câu lược chủ ngữ, không hề
có 他/她**. Model **tự chèn thêm một chủ ngữ không có trong nguồn**, rồi đoán giới bừa.

Hai hệ quả:
1. Lỗi thật không phải "đoán sai giới" mà là **"bịa chủ ngữ"** — **104 ca / 45 chương**. Nó
   vi phạm luôn gu dịch đã chốt trong [[translation-tuning]]: *lời kể phải **lược chủ ngữ**
   khi đã rõ ai*. Tức bản đúng là "Mở miệng nói: …", không phải "Hắn mở miệng nói: …".
2. Vì bản đúng là **bỏ hẳn chủ ngữ**, không cần biết nhân vật là nam hay nữ → **không cần
   ngữ cảnh cũng sửa được**.

### 2.8 Thí nghiệm đã chạy: 74% số ca **đã có sẵn bản đúng trong beam**

Chạy chính model production trên 104 ca đó, beam 6 / n-best 6 (6,4 giây cho cả 104 dòng):

> **77/104 = 74% ca đã có ít nhất một giả thuyết KHÔNG chèn chủ ngữ nằm sẵn trong n-best 6.**

```
ZH: 开口回道：“好吧！”
   h0: Hắn mở miệng đáp: "Được thôi!"       ← đang chọn cái này
   h2: Mở miệng đáp: "Được thôi!"           ← bản ĐÚNG, đã tính sẵn, đang bị bỏ
```

Nghĩa là **3/4 số ca sửa được bằng một dòng phạt trong `_rank_penalty`** — beam đã tính sẵn
các giả thuyết đó rồi, **không tốn thêm một mili-giây nào**, không train gì cả.
27 ca còn lại (cả 6 giả thuyết đều chèn chủ ngữ) mới là phần cần bậc 2.

---

## 3. Khảo sát Hugging Face — quét toàn bộ, không chỉ vài con

Quét bằng HF API (`?filter=zh&filter=vi&pipeline_tag=translation`, cộng tra theo tác giả).
Có **cả một hệ sinh thái dịch truyện Trung-Việt** mà lần trước tôi bỏ sót:

### 3.1 Nhóm "chạy được trên CPU" — đây mới là nhóm liên quan

| Model | Kiến trúc | Ghi chú |
|---|---|---|
| **`ngocdang83/HachimiMT-60-zh-vi`** | Marian, d576, **8 enc / 2 dec**, ffn 2304, vocab 24k, **max_pos 512** | base đang dùng. Tỉ lệ 8/2 là mẹo "encoder sâu, decoder nông" — đúng cách tối ưu tốc độ decode. |
| **`ngocdang83/HachimiMT-60-QT`** ⭐ | y hệt trên | bản ra **sau**, chuẩn hoá xưng hô. Tác giả tự công bố: base đảo giọng **24%** chỗ chuyển dòng → QT **0%** (538 dòng/7 thể loại). **Chưa kiểm độc lập.** |
| `ngocdang83/HachimiMT-30-zh-vi` | 31,7M | nhỏ hơn, không lý do đổi xuống |
| **`DanVP/MoxhiMT-60` / `-30` / `-30-QT` / `-30-web`** | Marian 57M, **cùng cấu hình Hachimi** | nhánh rẽ của Hachimi, tự nhận "tuned for xianxia/web-novel". Có sẵn CT2-int8. **Đối thủ trực tiếp, phải đo.** |
| **`DanVP/moxhimt-pronoun-clf`** ⭐ | classifier | **một model phân loại ĐẠI TỪ** — đúng bài toán mục 2.1. Đáng mổ xem họ làm thế nào. |
| **`DanVP/hy-mt-xianxia-lora-vi`** | LoRA trên Hunyuan-MT | có người đã LoRA hoá Hunyuan cho tiên hiệp tiếng Việt → **dùng làm thầy sinh data** rất hợp. |
| **`Moleys/hirashiba-mt-medium`** (bản CT2: `ngungodan/hirashiba-mt-medium-ct2`) | Marian d512, 6 enc/6 dec, vocab 25k, **max_pos 128** | dòng model khác hẳn. **max_pos 128 → không doc-level được**, nhưng đáng đo để so trần chất lượng. |
| `chi-vi/hirashiba-mt-tiny-zh-vi` | d256, 4/4, max_pos 512 | nhỏ hơn, dùng để "gác cổng" theo mô tả của họ |
| `Helsinki-NLP/opus-mt-zh-vi` | Marian ~77M | **baseline trung lập** của Helsinki — nên đo một lần để biết Hachimi hơn nền chung bao nhiêu |
| `alirezamsh/small100` | 330M, đa ngữ 100 thứ tiếng | ~6× hiện tại; khả thi về tốc độ nhưng **không biết giọng tiên hiệp** → phải finetune lại từ đầu |
| `chi-vi/gemma-3-1b-novels` | decoder 1B | có người đã thử hướng decoder cho truyện; quá chậm cho VPS mình |

### 3.2 Nhóm "quá lớn cho VPS" — chỉ có giá trị làm THẦY

| Model | Cỡ | Vì sao loại khỏi production |
|---|---|---|
| `tencent/Hy-MT2-1.8B`, `HY-MT1.5-1.8B` | 1,8B (rất được ưa chuộng: 162k lượt tải, 1.157 like) | Q4 trên 2 vCPU ước ~5-10 tok/s ⇒ **300-600 s/chương**, gấp ~30-60× tốc độ hiện tại (9,7 s) |
| `tencent/Hunyuan-MT-7B` / `Hy-MT2-7B` / `Hy-MT2-30B-A3B` | 7B-30B | vô địch WMT25 (30/31 hạng mục), hơn Seed-X-PPO-7B và Tower-Plus-72B |
| `ByteDance-Seed/Seed-X-PPO-7B`, `ModelSpace/GemmaX2-28-9B`, `NiuTrans/LMT-60-4B`, `YanoljaNEXT-Rosetta-4B/12B` | 4-12B | cùng loại |
| `facebook/nllb-200-distilled-600M` (+ bản CT2 int8 có sẵn) | 600M | ~8-12× chậm hơn hiện tại; **và không biết giọng cổ phong** → vừa chậm vừa phải train lại |
| `Unbabel/wmt22-cometkiwi-da`, `wmt22-comet-da` | 580M encoder | **không phải để dịch — để CHẤM.** Chạy offline lọc data + đo, không nằm trong đường dịch |

**Kết luận:** production vẫn là encoder-decoder ~57-250M. Nhóm 1,8-7B vào dự án theo đường
**sinh data ngoại tuyến** (chạy trên Kaggle/Colab GPU miễn phí, không phải VPS).

### 3.2b Nhóm "base đa ngữ dưới 1B — CHƯA biết dịch, phải train mới dùng được"

Lần quét đầu tôi lọc theo `pipeline_tag=translation` nên **sót cả nhóm này** — chúng không được
gắn nhãn "translation" vì bản thân chúng chưa dịch được gì. Chủ dự án hỏi đúng chỗ.

| Model | Cỡ | Có tiếng Việt+Trung? | Dùng được không |
|---|---|---|---|
| `google/mt5-small` | ~300M | Có (101 ngôn ngữ) | **Ứng viên thật cho bậc 5.** Là base *pretrain*, phải finetune trên corpus song ngữ mới dịch được. Bẫy: vocab **250k** → riêng embedding đã nặng, softmax chậm trên CPU. Có kỹ thuật **cắt vocab** (giữ token zh+vi) hạ xuống ~50-80M — bắt buộc phải làm nếu chọn hướng này. |
| `google/umt5-small` / `umt5-base` | 300M / 580M | Có | bản mT5 cải tiến, cùng bẫy vocab |
| `google/mt5-base` | ~580M | Có | ~2× small, sát trần tốc độ |
| `google/gemma-3-270m` | 268M | Có (đa ngữ) | decoder, Google ra đúng để finetune việc hẹp. Sinh ~3k token/chương ⇒ ước **75-150 s/chương** trên 2 vCPU → **chậm gấp ~10× hiện tại**. Đáng đo một lần chứ không đáng đặt cược. |
| `google/byt5-small` | ~300M | Có | byte-level, chậm hơn nhiều token-level — **loại** |
| `google/flan-t5-*` | 80M-11B | **Không** (chủ yếu tiếng Anh) | loại |
| **`google/madlad400-3b-mt`** | **2,94B** | Có, 400+ ngôn ngữ | **model dịch thật sự duy nhất của Google** — nhưng nhỏ nhất đã là 3B. Loại khỏi VPS, **giữ làm thầy**. |

**Chốt về nhà Google: họ không có model DỊCH nào dưới 1B.** madlad400 nhỏ nhất là 3B. Những cái
dưới 1B (mt5/umt5/gemma-270m) là **base trắng** — muốn dùng thì tự train, tức là quay về đúng
bài toán bậc 5, và khi đó **mt5-small đã cắt vocab là lựa chọn tốt hơn tự train Marian từ số 0**
(được thừa hưởng pretrain đa ngữ, đỡ vài triệu cặp dữ liệu).

### 3.3 Dữ liệu tìm được (đây mới là phần đổi cục diện)

| Dataset | Cỡ | Tình trạng |
|---|---|---|
| `ngocdang83/tran-vi-teacher` | 350.751 dòng, **3,07 GB**, đoạn văn (trung vị 7 dòng), CC-BY-4.0, chưng cất Gemini 2.5/3.0/3.1 | **mở** — đang dùng làm replay |
| `chi-vi/hirashiba-mt-zh2vi` | **7,0 GB** (`baidu_zh2vi.txt`) | **gated** — phải xin quyền (đã có HF_TOKEN) |
| `chi-vi/hirashiba-mt-zh2vi-b-filtered` | **6,0 GB**, nhiều thầy: `general_quickmt_gemini_1/2` (3,9 GB), `novel_gemini`, `novel_claude_r1`, `qt_nsfw_deepseek-v3` | **gated** |
| `chi-vi/chinese-vietnamse-parallel-corpus-using-gemini` | **8,9 GB** (129 file .db3) | **gated** |
| `chi-vi/CNovels` | **120 GB** truyện Trung thô (qisuwang, zxcs, 84sk…) | **gated** — nguồn đơn ngữ, dùng cho back-translation |
| `chi-vi/linh_hq_parallel_corpus` | 45 MB parquet | gated |
### 3.3b Nguồn KHÔNG cần xin phép (tìm thêm 31/07, sau khi đơn xin chi-vi còn treo)

| Dataset | Cỡ | Nội dung | Đánh giá |
|---|---|---|---|
| **`kaihe/chinese_vietnamese_bilingual_wangwen`** ⭐ | **10,5 GB, Apache-2.0, KHÔNG gated** | **90 bộ truyện mạng**, căn theo **cả CHƯƠNG lẫn CÂU**. Tác giả lấy truyện Việt đang hot trên các trang truyện rồi dò ra bản Trung gốc, căn bằng thuật toán riêng (nhận diện thực thể + quy hoạch động, dựa trên chỗ tên riêng Việt gần âm Hán-Việt: Hàn Lập/韩立, Nguyên Anh/元婴). File: `parallel_chapters.jsonl` 2,26 GB (**theo chương**), `parallel_sentences.jsonl` 5,24 GB, `train_data.jsonl` 1,77 GB (định dạng instruction: *"dịch trọn chương này sang tiếng Việt"*). | **Khác chất mọi thứ đang có: đây là bản dịch NGƯỜI**, không phải output máy — trong khi `tran-vi-teacher` và chi-vi đều là Gemini/Claude/DeepSeek sinh ra, tức **cùng nguồn gốc với cái bias "bịa chủ ngữ"** ở mục 2.7. Và nó **căn theo chương** → doc-level dùng được ngay. |
| `moa/Chinese-Vietnamese-literature` | 76 MB, mở | văn học cổ điển (Hồng Lâu Mộng…), cột `zh`/`vi` | nhỏ nhưng **register cổ chuẩn**, tốt cho Hán-Việt và tên riêng |
| `thevan2404/merged-zh-vi-sentences-clean` | 561 MB, mở | WikiMatrix + tương tự, câu lẻ đời thường | **sai domain** (không có văn kể truyện). **KHÔNG phải sai register** — "Tôi đã xấu hổ vì cha mẹ mình" là tiếng Việt đúng; luật ta–ngươi là luật cho **văn truyện**, không phải cho mọi câu. Có chỗ dùng thật: Hachimi còn dịch **tên truyện / mô tả / tiêu đề chương**, chỗ đó giọng hiện đại mới đúng. Trộn vào train thì phải **gắn tag domain**, đừng trộn trần. |
| `zehaohhhuang/Chinese-VietnameseTextAlignment` | 56 MB, mở | zh/vi để rời hai file | phải tự căn, giá trị thấp |
| `triettheeducator/vietnamese_chinese_ancient_text-40k` | 4 MB, mở | **chỉ có cột tiếng Việt** | không dùng được làm song ngữ |

**Đo mẫu 44 chương của `kaihe`** (400 KB đầu `train_data.jsonl` — mẫu nhỏ, chưa đại diện cả 90 bộ):

| Đo theo **từng giới** (xung đột thật) | Số chương |
|---|---|
| Xung đột cách gọi **nữ** (nàng vs cô) | 3 |
| Xung đột cách gọi **nam** (hắn vs anh ta) | 6 |
| **Chương nhất quán giọng** | **35/44** |

Phần lớn ca "xung đột" còn lại chỉ là nhiễu (`hắn=1` vs `anh ta=1`). Dữ liệu **nhất quán ~80%**,
và cái nó dùng là quy ước **hắn/cô** cho truyện đô thị chứ không phải hắn/nàng — **quy ước khác,
không phải hỏng**. Muốn đổi sang hắn/nàng thì `_fix_register` sẵn có làm được; để nguyên cũng không sai.

> **Hai con số tôi đưa trước đó ĐỀU SAI, do phép đo hỏng — ghi lại để không ai lặp lại:**
> - *"chỉ 35% cổ phong"* → đếm **từ** mù, không nói lên gì.
> - *"33/44 chương trộn giọng"* → gộp nhầm **hai nhân vật khác giới** ("hắn thấy cô" là nam=hắn,
>   nữ=cô, hoàn toàn nhất quán) thành lỗi.
>
> **Luật rút ra cho mọi cổng lọc data sau này: tiêu chí là "MỘT nhân vật có bị gọi hai kiểu
> không", KHÔNG phải "chương có chứa từ hiện đại không".** Chứa từ đó không có nghĩa là sai —
> cùng đúng cái lý do khiến bản dịch bị chê là đảo giọng chứ không phải dùng sai từ.

→ Việc cần làm khi có máy: tải `parallel_chapters.jsonl`, chạy cổng **nhất quán theo giới** (không
phải cổng cấm từ) lên toàn bộ, đếm số chương nhất quán. Đó là con số quyết định bậc 2 có nguyên
liệu hay không.

### 3.3c Nguồn không phụ thuộc ai duyệt: tự sinh

Kho của mình có **9.210 chương nguồn Trung nằm sẵn trên R2** (mục 2.7 đã chứng minh lấy về được).
Cộng với `LLM_PROVIDER=nvidia` (`z-ai/glm-5.2`, miễn phí) và prompt đã ghim đúng gu dịch
(`translator/prompts.py`), mình **tự sinh được data thầy in-domain, đúng register theo cấu tạo**,
không cần ai duyệt. Lưu ý chi phí: gọi LLM từ VPS 38-79 s/lần nhưng từ máy nhà chỉ 2-3 s
([[llm-latency-vps]]) → **chạy ở máy nhà**, vài ngày là xong vài nghìn chương.

Đây là phương án dự phòng nếu chi-vi không duyệt, và đằng nào cũng nên chạy: nó là nguồn duy nhất
đảm bảo **đúng truyện người đọc đang đọc**.

**Link xin quyền** (tất cả đều `gated: manual` — chủ repo duyệt tay, trừ CNovels `auto` = bấm
đồng ý là vào ngay):

- https://huggingface.co/datasets/chi-vi/hirashiba-mt-zh2vi — 7,0 GB
- https://huggingface.co/datasets/chi-vi/hirashiba-mt-zh2vi-b-filtered — 6,0 GB ⭐ ưu tiên
- https://huggingface.co/datasets/chi-vi/hirashiba-mt-zh2vi-b
- https://huggingface.co/datasets/chi-vi/chinese-vietnamse-parallel-corpus-using-gemini — 8,9 GB
- https://huggingface.co/datasets/chi-vi/linh_hq_parallel_corpus
- https://huggingface.co/datasets/chi-vi/cachua-zh2vi
- https://huggingface.co/datasets/chi-vi/linh_truyenfull
- https://huggingface.co/datasets/chi-vi/CNovels — 120 GB, `gated: auto`

| Kho DB của mình | **9.210 chương đã dịch** | **KHÔNG dùng làm gold được** — phần Việt là output của chính Hachimi (tự chưng cất chính mình = khuếch đại lỗi của chính mình). `content_zh` **nằm trên R2** (`blob.get_zh`, đã lấy về được 45/45 chương truyện 2163), không phải cào lại. Chỉ dùng làm **nguồn zh** để tự sinh data thầy và làm bộ test. |

Tức là tổng dữ liệu zh-vi công khai/gated **hơn 20 GB song ngữ** — gấp ~7 lần cái mình đang
dùng. **Việc đầu tiên nên làm: xin quyền truy cập các dataset `chi-vi`.** Miễn phí, chỉ mất
thời gian chờ duyệt, và nó mở khoá mọi phương án phía dưới.

---

## 4. Train một model MỚI từ đầu — nghiên cứu đầy đủ

Chủ dự án hỏi thẳng, nên trả lời thẳng: **làm được, và có một lý do chính đáng duy nhất để làm.**

### 4.1 Chi phí & tính khả thi

- **Kiến trúc đề xuất** (nếu làm): Marian/Transformer **8 enc / 2 dec** (giữ mẹo của Hachimi vì
  nó tối ưu đúng chỗ mình nghẽn — decode trên CPU), d_model 640-768, ffn 2560-3072 →
  **~120-200M tham số**, tức 2-3,5× hiện tại. Trên 2 vCPU ước **20-35 s/chương** (từ 9,7 s) —
  cộng thêm doc-level nữa thì phải đo lại xem có theo kịp crawl không. Phải đo, không đoán.
- **Tokenizer**: đây là chỗ from-scratch thắng rõ. Vocab 24k joint zh+vi hiện tại là **chật**
  cho tiếng Việt (âm tiết + dấu). Vocab riêng 32k, tách nguồn/đích, sẽ giảm số token đích →
  **nhanh hơn và ít lỗi cắt câu hơn**.
- **`max_position_embeddings`**: đặt 1024 ngay từ đầu → doc-level thoải mái.
  *(Lưu ý: Hachimi hiện đã là **512**, đủ cho ngữ cảnh 2-3 dòng — nên **doc-level KHÔNG cần
  train from scratch**. Đây là lý do from-scratch không phải việc phải làm trước.)*
- **Dữ liệu cần**: từ đầu thì cần **≥5-10 triệu cặp** để bằng được một base đã chưng cất tốt.
  Với 20 GB ở mục 3.3 thì **đủ**, sau khi lọc.
- **Máy**: Kaggle T4×2, quota **30 giờ/tuần**. Một vòng train 120-200M trên ~8M cặp, 3-4 epoch,
  ước **40-70 giờ T4×2** ⇒ **2-3 tuần** chia nhiều phiên, phải làm checkpoint/resume tử tế.
  So sánh: một vòng finetune hiện tại chỉ vài giờ. **Vòng phản hồi chậm hơn ~15 lần.**

### 4.2 Cái from-scratch KHÔNG mua được (quan trọng nhất)

Bằng chứng ở mục 2.1: prior "开口道 → **Nàng** mở miệng" là **học từ data thầy** (Gemini).
Một model mới train từ đầu **trên cùng nguồn data thầy đó sẽ kế thừa đúng cái bias đó**.
**Train lại từ đầu không phải là cách sửa lỗi mà chủ dự án đang gặp.** Cái sửa được là:
(a) cho model thấy ngữ cảnh, (b) làm sạch/cân bằng đúng construction đó trong data.

Cả (a) và (b) đều làm được **trên base hiện có**, rẻ hơn 15 lần.

### 4.3 Vậy khi nào mới đáng train từ đầu

Chỉ khi cả ba điều sau đồng thời đúng:
1. Bậc 2 (doc-level trên base cũ) **đã đo** và chạm trần rõ ràng — hoặc vì `max_pos 512` không
   đủ, hoặc vì 57M không gánh nổi ngữ cảnh dài;
2. Đã xin được data `chi-vi` (nếu không thì không đủ nguyên liệu, train từ đầu chắc chắn thua);
3. Chủ dự án chấp nhận vòng phản hồi 2-3 tuần/lần thay vì vài giờ/lần.

Khi đó dự án có tên gọi riêng: **"Hachimi-DOC ~150M"** — vocab 32k riêng, max_pos 1024, tag
giới tính/thể loại nướng sẵn vào nguồn, train trên data đã lọc bằng CometKiwi. Đó là **bậc 5**
của kế hoạch, không phải bậc 1.

---

## 5. Các cách train (xếp theo "đáng làm cho mình")

1. **Seq-KD / distillation từ thầy** — đang làm. Đã bão hoà ở dạng câu.
2. **Doc-level concatenation (2+2)** ⭐ — mẫu train đổi từ `câu → câu` thành
   `ctx ⟨sep⟩ câu → dịch`. Rẻ nhất, chuẩn nhất, **không đổi kiến trúc** (max_pos 512 đủ chỗ).
   Data có sẵn: `tran-vi-teacher` vốn đã là đoạn văn.
3. **Tag control** ⭐ — chèn thẻ giới tính nhân vật/thể loại vào đầu nguồn. Mình đã có glossary
   tên riêng và termguard đã biết chèn mã vào nguồn. Nhắm thẳng nhóm 36 ca ở mục 2.1.
4. **QE-guided filtering** — CometKiwi chấm data, vứt phần dưới ngưỡng. Sạch hơn gate regex
   (gate regex thì "thầy tối ưu được", QE thì không).
5. **Preference tuning (CPO — ALMA-R)** — ALMA-R chỉ dùng **22K cặp + LoRA 0,1% tham số** mà
   đuổi kịp GPT-4/WMT winner. Mình sinh cặp (chosen, rejected) **miễn phí** từ n-best 6.
6. **Thầy mới** — `DanVP/hy-mt-xianxia-lora-vi` hoặc Hy-MT2-1.8B chạy trên Kaggle để dịch lại
   đúng những construction đang lỗi (开口道 lược chủ ngữ), thay vì nhờ Codex gõ tay 660 câu.
7. **APE / monolingual repair** — model thứ hai sửa bản nháp cả chương. Mạnh, nhưng nuôi thêm
   một model. Để dành.
8. **From scratch ~150M** — mục 4, bậc cuối.

---

## 6. Kế hoạch — theo bậc, mỗi bậc phải đo trước khi lên bậc sau

**Đường nhanh nhất tới bản dịch tốt hơn** (chủ dự án yêu cầu "finetune cho nó nhanh"): bậc 0
không phải finetune và đã đo được là ăn 74% lỗi chính — làm trước trong nửa ngày, deploy ngay.
Vòng finetune (bậc 2) chỉ nên khởi động **sau khi** bậc 0 đã dọn xong phần rẻ, vì lúc đó data
gold mới không phải tốn chỗ dạy lại những thứ mà một dòng phạt đã sửa xong.

### Bậc 0 — Vá được ngay + dựng thước đo (0 GPU)

| Trạng thái | Việc | Ở đâu | Nhắm vào |
|---|---|---|---|
| ✅ **XONG, đã deploy** | Phạt "bịa chủ ngữ": nguồn không có 他/她 mà giả thuyết mở đầu bằng Hắn/Nàng/Y/Gã/Nó → phạt 6.0 | `hachimi_engine.py:67` `_invents_subject` | **77/104 ca, đã đo trên model production. 0 hồi quy.** |
| ✅ XONG | Cổng nghiệm thu corpus + chấm LaBSE + test | `pipeline/14_gate_corpus.py`, `15_score_labse.py` | dựng thước đo data |
| ✅ user đã làm | Xin quyền các dataset `chi-vi` trên HF | — | đang chờ duyệt |
| ✅ XONG, đã deploy | Ưu tiên "nam tử" hơn "người đàn ông" (男子/女人), phạt 4 | `hachimi_engine.py` `_SOFT_MODERN` | 6 ca sạch, 0 hồi quy |
| ❌ BỎ — đo 0 lợi ích | Phạt **lệch giới**: nguồn 他/她 vs đích hắn/nàng | — | ranker đã KHÔNG bao giờ chọn sai giới khi nguồn có 他/她 rõ đầu dòng (đo 111 ca). Lỗi giới nằm hết ở nhóm bịa chủ ngữ → bản vá đã deploy lo rồi |
| ❌ BỎ — model đã đúng | Glossary 本少爷/本公子/本座/本尊/本王 | — | teacher-v4 dịch đúng "bản thiếu gia" cả 6 giả thuyết. "Bản thiếu nữ" trong DB là do model CŨ. Luật: đừng ép cái model đã làm đúng |
| ⬜ HOÃN — rủi ro | Hậu xử lý "ông ta" (cả 6 beam đều dính) | postprocess | rewrite trong ngoặc kép có thể phá thoại nơi "ông ta" là lời nhân vật. Chưa đo an toàn |
| ⬜ chờ ca lỗi | `repetition_penalty` / `no_repeat_ngram_size` — quét máy CHƯA xác nhận có lỗi lặp máy móc (2.5) | `hachimi_engine.py:167` | lặp |
| ⬜ CHƯA | Khoá 45 chương truyện 2163 (nguồn từ **R2**) thành **bộ test có nguồn** | `hachimi/eval/` | mọi phép đo sau |

**Không** động vào `repetition_penalty` trước khi có ca lỗi thật — chỉnh mù sẽ phá điệp ngữ
đúng ("Ba mươi năm Hà Đông…").

### Bậc 1 — Đấu loại base (ĐÃ CHẠY 31/07, harness `eval/eval_register.py`)

Bộ test `eval/testset_multi.jsonl`: 7 truyện đa thể loại, 13.532 dòng, nguồn từ R2, chỉ số ref-free.

**Đo 7 model trên bộ 45 chương (5553 dòng lược chủ ngữ):**

| model | bịa CN | **đại từ hiện đại** | nđ.ông | lặp | dòng/s |
|---|---|---|---|---|---|
| **teacher-v4 (giữ)** | 31 | **86** | 3 | 94 | 24,1 |
| HachimiMT-60-QT | 8 | 142 | 1 | 158 | 23,9 |
| HachimiMT-30 | 6 | 135 | 4 | 87 | 29,6 |
| MoxhiMT-60 | 9 | 157 | 3 | 133 | 24,0 |
| MoxhiMT-30 | 6 | 138 | 8 | 145 | 37,1 |
| MoxhiMT-30-QT | 27 | 167 | 1 | 153 | 31,3 |
| hirashiba-medium | 0 | 150 | 18 | 139 | 18,3 |

(hirashiba-tiny lỗi spm không đọc được — bỏ.)

**Kết luận: giữ teacher-v4 làm base — thắng DỨT KHOÁT ở chỉ số chính.** "Đại từ hiện đại lọt" là
vấn đề còn lại thật sự (bịa chủ ngữ n-best đã lo, còn 0,2% trên bộ lớn), và teacher-v4 = **86**,
mọi ứng viên khác **135-167** — gấp đôi. Các con khác giỏi hơn ở bịa-chủ-ngữ (thứ doc-level sẽ
dọn nốt) nhưng đánh đổi bằng rò register nặng hơn nhiều. Đo qua 7 model, kết luận chắc.
**Quy tắc "luôn đi từ HachimiMT-60-zh-vi" giữ nguyên.**

**Chỉ số chính giờ là "đại từ hiện đại lọt" (524)** — không phải bịa chủ ngữ nữa (đã xuống 0,2%).
Đây là lỗi cả-6-beam, chỉ Bậc 2 (train trên data sạch) sửa được.

### Bậc 2 — Doc-level (bậc ăn thua thật)

**Công cụ đã dựng + kiểm chứng offline (31/07):** `pipeline/16_make_doclevel.py` sinh cặp
`ctx ⟨SEP⟩ câu → dịch câu` từ dữ liệu căn theo chương. Chạy thử trên 45 chương thật (truyện 2163):
- 6017 cặp, **99% có ngữ cảnh**;
- độ dài nguồn sau ghép **p95=99, max=152 ký tự** — thừa chỗ trong max_pos 512, **KHÔNG chậm
  gấp 2-3× như ước ban đầu** (câu truyện ngắn nên ghép 2 dòng vẫn nhỏ);
- với dòng lược chủ ngữ, ngữ cảnh phía trước **thật sự chứa 他/她 rõ giới** → tín hiệu doc-level
  cần để hết bịa chủ ngữ là CÓ THẬT trong data, không phải giả định.

Các bước còn lại (cần data + GPU):
1. Sinh cặp doc-level từ `kaihe` (căn theo chương, bản dịch người) + `tran-vi-teacher`.
2. Train từ base thắng bậc 1. **SEP phải cố định giữa data train và `hachimi_engine` lúc chạy.**
3. Sửa engine: `translate_lines` ghép 1-2 dòng **nguồn Trung** phía trước (không dùng bản dịch,
   tránh dồn lỗi); ngữ cảnh phải sống sót qua bước cắt câu dài, không bị `_split_source` xé mất.
4. **Đo tốc độ before/after trên VPS trước khi deploy** — theo kịp lượng chương crawl về/ngày.

**Cổng huỷ:** nếu tỉ lệ bịa chủ ngữ trên bộ test không giảm ≥50% thì dừng nhánh này,
chuyển sang bậc 3 thay vì đổ thêm data.

### ❌ Doc-level v1 ĐÃ TRAIN VÀ THẤT BẠI (31/07) — đừng lặp lại

Train từ base sạch + `doclevel_corpus.jsonl` (600k), 1 epoch. Đo trên 45 chương:

| | teacher-v4 | doclevel ctx=2 | doclevel ctx=0 |
|---|---|---|---|
| bịa chủ ngữ | 31 | 56 | 71 |
| **đại từ hiện đại** | **86** | 197 | 196 |

**Tệ hơn teacher-v4 rõ rệt → không deploy.** Chẩn đoán:
1. Đại từ hiện đại ~196 ở CẢ hai mode → register **không phải** vấn đề ngữ cảnh giải được. Ngữ
   cảnh chỉ nhích bịa chủ ngữ (71→56).
2. 196 ≈ mức register của BASE GỐC → train từ base sạch + corpus doc-level **rộng/loãng** đã
   tụt register về base, **mất phần booster register nhắm-đích** làm teacher-v4 giỏi (86).

**Hai bài học ghim:**
- **Corpus train PHẢI gồm bộ gold register/booster của teacher-v4**, không chỉ kaihe+teacher.
  Train từ base sạch mà bỏ gold = vứt thành quả cũ. (Lỗi thiết kế pipeline 17.)
- **Doc-level là công cụ cho BỊA CHỦ NGỮ, không phải cho đại từ hiện đại (524).** Lỗi 524 cần
  data register nhắm-đích đậm đặc — đúng thứ booster làm — không phải ngữ cảnh.

### ❌❌ CẢ v2 CŨNG KHÔNG THẮNG + METRIC "524" LÀ NHIỄU (1/8/2026)

Đo v2 (gold×6 + doc-level 34k) với metric ĐÃ SỬA (bỏ "mình" khỏi đếm đại từ hiện đại):

| 45 chương | teacher-v4 | v2 ctx=2 |
|---|---|---|
| bịa chủ ngữ | 31 | 68 |
| sai giới thật | 0* | 3 |
| **đại từ hiện đại THẬT** (bỏ mình) | **2** | **1** |
| (con số cũ gộp "mình", nhiễu) | 86 | 194 |
| người đàn ông | 3 | 15 |

**PHÁT HIỆN LỚN: metric "524 đại từ hiện đại" là ~98% "mình"** — mà "của mình/chính mình" là
tiếng Việt ĐÚNG. Lỗi register THẬT chỉ ~2 dòng ở cả teacher-v4 lẫn v2. **Cả bài toán "524" tôi
đuổi theo nhiều lượt là ảo do thước đo hỏng.** teacher-v4 vốn đã sạch register.

**KẾT LUẬN CHỐT: giữ teacher-v4, KHÔNG deploy v1/v2.** Doc-level không cải thiện gì thật, còn
tệ hơn ở bịa chủ ngữ + người đàn ông. Lỗi "nam ra nàng" user gặp ban đầu là từ model CŨ trong
DB; teacher-v4 + n-best đã xử lý. **Đóng nhánh doc-level.** Nếu còn lỗi cụ thể thì cần user chỉ
đúng chương RECENT (dịch bằng teacher-v4 hiện tại), không phải chương DB cũ.

**Bài học đắt nhất cả đợt: hiệu chỉnh thước đo TRƯỚC, đừng để "mình" (hay bất cứ từ đa nghĩa nào)
thổi phồng metric rồi lái cả loạt quyết định.**

### ✅ ĐỌC TAY 7 TRUYỆN ĐA THỂ LOẠI (1/8/2026) — vì sao KHÔNG deploy doclevel, đúng bản chất

Metric 45 chương trên chỉ đo 1 truyện tu tiên. Đọc tay 7 truyện (tu tiên ×4, đô thị/zombie,
học đường ma pháp, game LitRPG), mỗi truyện 1 chương × 3 model (v4 ctx0, doclevel v1/v2 ctx2):

- **Không model nào thắng tuyệt đối — phụ thuộc THỂ LOẠI.** Tu tiên/cổ trang: cả 3 ngang nhau,
  ta-ngươi hợp cảnh. Hiện đại/học đường: v4 **sượng thật** ("lão sư", trò xưng "ta" với cô giáo,
  牛b→"đồ bò"); doclevel đọc tự nhiên hơn ("thầy/cô", "em…ạ", "lợi hại").
- **NHƯNG doclevel (CẢ v1 LẪN v2) trả giá bằng 2 lỗi phá niềm tin người đọc:**
  1. **Bịa giới**: `你`(nam) → "cô" gọi nam chính (205); `回马枪`→"khẩu súng lục" (1380).
     v4 dùng ta-ngươi trung tính nên KHÔNG BAO GIỜ sai giới ở ngôi 2.
  2. **Nuốt ngữ cảnh (bịa nội dung)**: dịch xong câu rồi nối nguyên đoạn ⟪ctx⟫ vào bản dịch —
     đo được ở 1256, 205, 282. Đây là bản chất kiến trúc ghép ngữ cảnh, v2 KHÔNG sửa được.
- **Kết luận CHỐT không đổi nhưng lý do sâu hơn:** giữ v4 KHÔNG phải vì nó dịch hay hơn mọi mặt
  (nó THUA doclevel ở register hiện đại), mà vì doclevel đổi "tự nhiên hơn" lấy bịa-giới +
  bịa-nội-dung. Đừng ai lần sau tưởng "chỉ cần sửa register là doc-level ăn".
- **Điểm yếu THẬT của v4 lộ ra (đáng làm, KHÔNG cần train rộng):**
  - Register hiện đại (lão sư/ta-trò) → cần **booster register theo thể loại**, không phải doc-level.
  - **Loạn tên riêng** cùng chương (罗森 → "Roson"/"La Sâm" lẫn lộn ở 282) → **glossary/termguard**.
  - Số liệu khoa học (`焦耳`→"lạng tai") + lóng net: trần 57M, kệ.

### ⚠️ BẪY: slot `models/hachimi-ct2` LOCAL lệch bản (đo 1/8/2026)

- **VPS (production) = teacher-v4** — đo trong container: `md5 a1813ced…`, mtime 25/07. ĐÚNG bản tốt.
- **LOCAL `models/hachimi-ct2` = bản CŨ 23/07** (`md5 22007e6…`), KHÁC v4. Mọi eval local dùng
  `DEFAULT_MODEL = models/hachimi-ct2` (eval_register, evaluate_*_current) đang chấm **nhầm bản cũ**,
  không phải bản đang chạy thật. **Trước khi tin số eval "current/production", đồng bộ slot này = v4.**
- Hệ quả cho lỗi "dịch lại vẫn sai giới": KHÔNG do VPS chạy bản cũ (đã loại). Còn 2 khả năng —
  (A) chương đang đọc là bản DB cũ, chưa thực sự `redich`; (B) v4 vốn còn sai giới ở ca lược chủ
  ngữ. Tách bằng: query `model_used`+`translated_at` của đúng chương user chỉ, rồi dịch lại nguồn
  chương đó bằng v4 hiện tại. Nếu v4 đúng mà DB sai → A; nếu v4 vẫn sai → cần Bậc 3 (tag giới).

### ✅ ĐÃ TÁCH (1/8): ca "Giang Trần tự xưng nàng" (novel 2163 ch44/45) = **KHẢ NĂNG A**

- Ca thật: ch44 nguồn `轻声道：...` (lược chủ ngữ, chủ ngữ ngầm = 江尘 nam) → bản DB dịch "**Nàng**
  nhẹ giọng nói". Chương dịch 30/07, `model_used='hachimi'`.
- **Dịch lại cả chương bằng v4 + code HIỆN TẠI → HẾT lỗi**: dòng đó ra "Nhẹ giọng nói" (lược, an
  toàn), mọi "Nàng" còn lại đều là Cổ Hi Dao (nữ, đúng). Không tái hiện được lỗi.
- `translation_jobs` cho ch44/45 đều `done` từ 30/07, KHÔNG có job dịch lại mới → **chương chưa
  từng được `redich`** sau khi v4+n-best lên. Lỗi là tàn dư bản 30/07 (lúc đó chưa chặn bịa chủ ngữ).
- ⇒ **Cách chữa: dịch lại thật các chương cũ** (dịch trước mốc v4+n-best). KHÔNG cần Bậc 3, KHÔNG
  train, KHÔNG sửa engine cho ca này. Cần soi vì sao thao tác "dịch lại" của user không tạo job.

### 🔬 Phép thử thẻ giới trên v4 (1/8) — dùng cho Bậc 3 sau này

Dịch 1 câu lược chủ ngữ (江尘 nam) bằng v4 với các tín hiệu giới khác nhau:
- **Thẻ `【男】` / `江尘（男）` → v4 dịch LITERAL** ("[Nam] khẽ nói") — **v4 KHÔNG hiểu thẻ**, muốn
  dùng thẻ **bắt buộc train**.
- **Ghép ngữ cảnh nguồn có tên nam / chèn `他` đầu câu → v4 ra "Hắn" đúng** — v4 **nghe ngữ cảnh +
  đại từ** tốt, KHÔNG cần train. Nhưng ghép nguyên câu ngữ cảnh thì v4 (không có SEP) dịch luôn cả
  câu ngữ cảnh vào output → phải chèn kiểu tối thiểu (1 đại từ), và cần heuristic phân giải chủ ngữ.
- Kết luận cho Bậc 3: hướng "chèn thẻ" cần train; hướng "chèn đại từ 他/她 theo giới glossary" rẻ
  hơn nhưng vướng bài toán biết-câu-nào-lược-chủ-ngữ-và-chủ-ngữ-là-ai.

### Bậc 3 — Tag giới tính từ glossary
Thêm trường giới tính cho term tên riêng (LLM trích tên **đã chạy sẵn**, thêm một field vào
JSON), chèn thẻ vào nguồn lúc train + lúc chạy. Bắt đúng ca nguồn lược chủ ngữ.
Tham khảo `DanVP/moxhimt-pronoun-clf` xem họ giải bài này thế nào.

### Bậc 4 — CPO trên n-best (LoRA, data tự sinh)
Rẻ, không cần thầy mới. Làm sau khi doc-level ổn định.

### Bậc 5 — "Hachimi-DOC ~150M" từ đầu
Chỉ khi thoả cả ba điều kiện ở mục 4.3.

---

## 7. Thước đo (dựng ở bậc 0, dùng cho mọi bậc sau)

| Chỉ số | Cách đếm |
|---|---|
| **Lệch giới lời kể** | tỉ lệ "Nàng \|Hắn " mở đầu dòng, đối chiếu giới nhân vật; riêng cụm `开口道` tách ra đếm |
| **Lỗi giới trong thoại** | 本少爷 → "bản thiếu nữ" và họ hàng |
| **Đảo giọng** | đổi ta/ngươi ↔ tôi/cậu giữa hai dòng liền nhau (đúng cách tác giả QT đo → so trực tiếp với 24%/0%) |
| **Register hiện đại** | danh sách từ ở 2.3 |
| **Tên riêng đổi giữa chừng** | một term Hán ra nhiều bản dịch trong một chương (Thiên Hương Lâu/Các) |
| **Lặp** | n-gram lặp, **trừ điệp ngữ có trong nguồn** |
| **Hán sót / mã sót** | đã có |
| **COMET-22 + CometKiwi** | nếu cài nổi trên máy chủ dự án |
| **MQM rút gọn, đọc tay 50 dòng/vòng** | **bắt buộc** — bài học "cổng đo được thì thầy tối ưu được" |

Bộ test chia **Simple** / **Difficult** như WMT literary. Không trộn với `data/eval_locked/`.

---

## 8. Việc cần chủ dự án làm

1. **Chỉ ca lặp từ cụ thể** (truyện/chương) — quét máy 45 chương không tìm thấy lỗi lặp máy móc,
   nên chưa dám chỉnh `repetition_penalty`.
2. Nếu còn nhớ **loại lỗi nào khác** ngoài 6 nhóm ở mục 2 thì kể — mục 2 chỉ bắt được cái máy
   đếm được, phần "một số lỗi nữa" vẫn đang thiếu.
3. Mở máy để chạy bậc 0 + bậc 1 (không cần GPU).
