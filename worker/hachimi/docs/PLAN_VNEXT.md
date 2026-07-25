# Kế hoạch finetune HachimiMT v-next — dữ liệu sạch và đánh giá theo cảnh

> Trạng thái: **chưa được train**. Bộ `dataset/train_gold_vnext.jsonl` cũ không được
> dùng: 8.060 dòng nhưng có 1.200 bản sao và ít nhất một nguồn Trung có hai bản Việt
> xung đột. Phần “kế hoạch cũ” ở cuối file chỉ được giữ làm lịch sử.
>
> Tiến độ 24/07/2026: đã khóa 300 cảnh tại `dataset/eval_vnext_300.jsonl`,
> biên tập đủ 60/60 bản tham chiếu tại `dataset/eval_reference_60.jsonl` và duyệt
> 200 cặp gold tại `dataset/gold_approved_vnext.jsonl`. `train_v2` bị loại; pilot
> local dùng 4.949 cặp replay dự phòng đã lọc. Hai ứng viên A (`gold×1`) và B
> (`gold×3`) đã train từ model gốc, xuất CT2 và đánh giá trên 60 cảnh. Cả hai
> chưa đạt cổng pilot; xem `experiments/hachimi_vnext_ab_conclusion.md`.

## 1. Mục tiêu và giới hạn

Mục tiêu của vòng này là sửa lỗi nghĩa và văn phong theo **ngữ cảnh**, không chỉ sửa
từng chữ:

- không đổi chủ thể, quan hệ, phủ định, số lượng hoặc nguyên nhân - kết quả;
- lời thoại giữ đúng người nói, người nghe và không bị tách/gộp vô lý;
- lời kể mặc định dùng `hắn`/`nàng`, hội thoại mặc định dùng `ta` - `ngươi`;
- giữ cách gọi theo quan hệ như `dì`, `thúc thúc`, `sư phụ`, `tiền bối`;
- chỉ dùng `trẫm`, `thần`, `tại hạ`, `vãn bối` khi nguồn Trung thể hiện đúng vai đó;
- không tự hiện đại hóa thành `tôi`, `bạn`, `cậu`, `cháu`;
- không thêm từ đệm như `nhé`, `nha`, `đấy` nếu nguồn không cần;
- dịch đủ lời tác giả, thông báo hệ thống và nội dung trong ngoặc khi chúng có nghĩa.

Tên riêng và tên vật phẩm hiếm vẫn do glossary + termguard cưỡng chế. Không bắt model
57M “học thuộc” kho tên thay đổi theo từng truyện. Nhánh Hachimi vẫn chạy local, không
gọi LLM trên VPS 2 nhân.

## 2. Quyết định với dữ liệu hiện có

| Dữ liệu | Quyết định | Lý do |
|---|---|---|
| `approved_gold.jsonl` (5.000) | Giữ làm **ứng viên replay**, chưa gọi là gold đã duyệt | `status=approved` là trạng thái nhập liệu, không chứng minh đã được người duyệt |
| `register_gold.jsonl` (660) | Cách ly toàn bộ | Có lỗi đổi Maria thành `hắn`, đổi lời kể thành lời thoại `ta`, tên dính chữ |
| `booster.jsonl` (1.200) | Không train bản hiện tại | Mẫu slot đơn giản hóa ngữ cảnh; còn bị chèn lặp hai lần vào manifest cũ |
| `train_gold_vnext.jsonl` (8.060) | Loại khỏi mọi lệnh train | Trùng 1.200 cặp và có xung đột cùng ZH khác VI |
| `train_v2.jsonl` / replay cũ | Loại khỏi vòng này | Sau lọc cơ học vẫn có cặp lệch dòng và thuật ngữ sai; xem `experiments/hachimi_replay_vnext_audit.md` |
| Model gốc `ngocdang83/HachimiMT-60-zh-vi` | Điểm khởi đầu cho cả hai ứng viên | Không resume model CT2 hiện tại; CT2 hiện tại chỉ là baseline so sánh |

Các cờ heuristic của báo cáo Luna chỉ dùng để **xếp hàng duyệt**, không được tự động
kết luận câu sai. Những từ như `ta`, `ngươi`, số và dấu ngoặc có thể hoàn toàn đúng
trong ngữ cảnh.

## 3. Bộ dữ liệu v-next tối thiểu

Chỉ cần ba tập, không tạo thêm hệ thống nhãn phức tạp:

1. **Gold theo cảnh: 1.200 cặp đầu tiên**
   - Lấy từ 225 chương đã chạy Hachimi gốc trong
     `experiments/hachimi_base_longform_audit.md`.
   - Một mẫu phải là đơn vị model thực sự dịch: cả câu thoại kèm lời dẫn, hoặc một
     đoạn ngắn đủ xác định chủ thể; không cắt thành câu mất ngữ cảnh.
   - Mỗi sửa đổi phải được duyệt theo dạng:
     `ZH | bản hiện tại | lỗi cụ thể | bản đề xuất`.
   - Chia theo lỗi đã đo: 400 câu dài/chủ thể/quan hệ; 200 hội thoại/vai nói;
     240 thuật ngữ game-hệ thống-khoa huyễn; 160 phủ định/số/cấp bậc/thêm-bớt;
     100 ngoặc thoại/lời tác giả; 100 ca Việt hóa tự nhiên nhưng giữ nguyên nghĩa.

2. **Replay sạch: 10.000-20.000 cặp**
   - Lấy mẫu phân tầng từ corpus gốc qua `kaggle_train.py::load_replay()`;
     không dùng extra replay `train_v2`.
   - Dùng để giữ năng lực dịch phổ thông của model, không dùng để ép văn phong.
   - Loại bản sao chính xác, xung đột cùng ZH, dòng rỗng, dòng đích còn Hán bất thường,
     artefact crawl và dòng vượt giới hạn token.
   - Lệch số, đại từ hiện đại hoặc dấu ngoặc chỉ là cờ cần xem, không hard-reject mù.

3. **Eval cố định: 300 cảnh**
   - Mỗi chương trong pilot 225 chương lấy ít nhất một cảnh; 75 cảnh bổ sung ưu tiên
     câu dài, nhiều nhân vật và UI hệ thống.
   - Tách theo truyện/chương/cảnh, không random theo dòng.
   - Không được trùng hoặc gần trùng với train.
   - Có đủ hội thoại nhiều lượt, lời kể, thông báo hệ thống, lời tác giả và tên glossary.

Mỗi dòng dữ liệu nên giữ thêm metadata ngay trong JSONL:
`source`, `novel_id`, `chapter_index`, `scene_id`, `reviewer`, `reviewed_at`,
`status`. Trainer hiện chỉ đọc `zh` và `vi`, nên không cần đổi schema train để giữ
được nguồn gốc.

## 4. Quy trình chuẩn bị dữ liệu

### Cổng A — làm sạch cơ học

Chạy cùng `text_clean.py` đã dùng ở crawler/worker, sau đó:

- chuẩn hóa Unicode và ký tự vô hình;
- loại artefact chống crawl đã biết;
- báo lỗi khi một ZH có nhiều VI khác nhau;
- loại exact duplicate trước khi tạo manifest;
- kiểm tra giới hạn token bằng tokenizer thật của model.

Không tự “sửa nghĩa” bằng regex.

### Cổng B — duyệt nghĩa theo cảnh

Người duyệt kiểm tra bảy điểm: chủ thể, người nghe, quan hệ, phủ định, số lượng,
thêm-bớt và văn phong. Duyệt 50 mẫu đầu trước; nếu quy tắc ổn mới mở rộng lên
1.200. Không đưa một cặp vào gold chỉ vì nó qua regex hoặc do một model khác sinh.

### Cổng C — chống rò dữ liệu

Split theo `novel_id + chapter_index + scene_id`; hash cả ZH đã chuẩn hóa để chặn
exact duplicate, rồi dò near-duplicate giữa train và eval. Random 2% theo dòng trong
script cũ không đủ an toàn.

## 5. Hai thử nghiệm train, không grid search

Chỉ train hai ứng viên từ model gốc:

| Ứng viên | Thành phần hiệu dụng | Mục đích |
|---|---|---|
| A | replay sạch ×1 + gold ngữ cảnh ×1 | Đo tác dụng thật, ít nguy cơ overfit |
| B | replay sạch ×1 + gold ngữ cảnh ×3 | Kiểm tra mức ép văn phong vừa phải |

Khởi đầu với learning rate thấp `1e-5` và 1 epoch. Chỉ nâng lên 2 epoch nếu loss/eval
cho thấy chưa học; không mặc định `3e-5`, 3 epoch và `gold-repeat=5` như kế hoạch cũ.
Không nhân bản dòng trong file dữ liệu; trọng số chỉ được áp dụng lúc dựng tập train
và phải được ghi trong manifest.

Chưa xây lại booster. Chỉ thêm 200-400 mẫu booster độc nhất khi A/B chứng minh gold
thật quá ít để sửa một nhóm lỗi cụ thể.

## 6. Đánh giá đúng pipeline production

So sánh ba model: Hachimi gốc, CT2 hiện tại và ứng viên A/B. Tất cả chạy cùng:

`clean_source → split theo ngữ nghĩa → termguard → translate → restore`

Chấm theo **cảnh**, không bắt từng lỗi chữ:

- trung thành nghĩa: chủ thể, quan hệ, phủ định, số, nguyên nhân - kết quả;
- nhất quán xưng hô giữa nhiều lượt thoại;
- ranh giới và dấu câu lời thoại;
- không tự thêm hoặc bỏ nội dung;
- đúng tên khi glossary có term;
- câu Việt tự nhiên nhưng vẫn đúng giọng tu tiên/huyền huyễn.

Điều kiện được đề xuất pilot:

- 0 lỗi nghiêm trọng làm đảo nghĩa trên tập eval;
- 0 tên mất khi termguard đã nhận term;
- 0 dòng bị cắt cụt hoặc hỏng marker;
- không nhóm lỗi nào kém model gốc quá 5%;
- tổng điểm nghĩa + ngữ cảnh tốt hơn baseline ít nhất 10%.

Sau đó mới chạy một truyện pilot, đọc toàn chương và lập báo cáo. Chưa ghi đè
`worker/models/hachimi-ct2`, chưa deploy, chưa sửa DB.

## 7. Thứ tự thực hiện

1. Khóa 300 cảnh eval từ output Hachimi gốc, không đưa chúng vào train.
2. Chốt 50/1.200 cặp gold theo cảnh đầu tiên và cho người dùng duyệt.
3. Lọc replay, xuất báo cáo số lượng giữ/loại và lý do.
4. Xuất manifest không duplicate/xung đột/rò eval.
5. Train A và B trên Kaggle từ model gốc.
6. Convert CT2 vào thư mục ứng viên riêng.
7. Chạy so sánh theo cảnh; chỉ pilot nếu qua toàn bộ cổng trên.

## 8. Những việc cố ý chưa làm

- Không train ngay từ manifest 8.060 dòng.
- Không coi dữ liệu Luna/model sinh là gold nếu chưa duyệt.
- Không thêm kho biến thể tên hoặc LLM QA runtime.
- Không xây UI/schema mới cho quy trình chỉ cần JSONL + báo cáo.
- Không finetune tên riêng thay cho glossary/termguard.

---

# Kế hoạch cũ — chỉ lưu lịch sử, không chạy các lệnh bên dưới

<!--
Đã làm xong vòng gold register (mining chặt + Codex GPT-5.6-luna làm thầy + QC):
- `01_mine_register.py` — mine ca lỗi register CĂN DÒNG CHẶT (chỉ chương done model=hachimi
  có số dòng-có-chữ zh==vi khớp đúng; ratio 1.8–4.5; bỏ 14% nền lệch của bản mining cũ).
- `dataset/error_cases.jsonl` — 687 ca nền sạch (zh + vi_model sai register).
- `dataset/labeled_gold.jsonl` — Codex sửa (687, 19 skip lời tác giả). QC: Hán 0, pinyin 0,
  ratio lệch 0, register sót ~8/668 (≈1%, phần lớn cậu-danh-từ). Giữ Hán-Việt đúng gu QT.
- `dataset/register_gold.jsonl` — 660 cặp {zh,vi} register (bỏ skip + lọc qua register-gate).
- `04_make_booster.py` → `dataset/booster.jsonl` — **1200 câu register TỔNG HỢP** (他/她/我 →
  hắn/nàng/ta, cả zh+vi tự điền theo slot nên đáp án đúng theo cấu tạo, KHÔNG cần thầy).
- **`dataset/train_gold_vnext.jsonl` — 8060 gold = 5000 cổ phong + 660 register + 1200×2
  booster.** ĐÂY là file đưa vào `--gold`. Sau gold-repeat×5: register-focused ~15k câu
  (vs v4 booster 8.8k) — đủ nặng để bẻ thói quen đại từ.
- **`kaggle_train.py` ĐÃ THÊM register-gate**: `load_replay`+`load_extra_replay` bỏ cặp replay
  có lời-kể lọt đại từ hiện đại (`_register_ok`). Bài học v2: replay không lọc = model tiếp
  tục học "tôi/mình" từ 698k → phải gate. Test: chặn đúng, 0 chặn nhầm booster.

**Lệnh train (Kaggle, kaggle_train.py sẵn có tự tải 698k replay `tran-vi-teacher`):**
```
python kaggle_train.py --gold dataset/train_gold_vnext.jsonl \
  --extra-replay dataset/train_v2.jsonl --extra-replay-limit 20000 \
  --output-dir hachimi-vnext --export-ct2
```
Sau train: giải nén CT2 vào `worker/models/hachimi-ct2/`, scp lên VPS, rebuild+up -d (xem
memory `hachimi-termguard-dinh-chu`). Đo bằng `07_eval_targeted` (đếm register lọt, KHÔNG chrF).

**Còn có thể mở rộng sau** (chưa làm, không bắt buộc cho vòng này): mine thêm lỗi nói lắp/
thuật ngữ (§1/§4) rồi Codex label, gộp vào gold. Register là lỗi lớn nhất nên làm trước.

---



> Người viết: Claude (phiên 23/07/2026). Người thực thi: **Codex**.
> Mục tiêu tài liệu: mô tả ĐỦ CHI TIẾT để Codex code từng script mà không cần đoán.
> Convention: tiếng Việt, chạy trong `E:\Novel_Project\.venv`, cwd = `worker/`,
> luôn `PYTHONIOENCODING=utf-8`. Hub finetune = `worker/hachimi_finetune/`.

---

## 0. Bối cảnh & mục tiêu vòng này

**Model hiện tại** (`worker/models/hachimi-ct2/`): MarianMT ~57M distill giọng "cổ phong",
CT2 int8. Đã production trên VPS cho toàn kho (2819 chương done, 100% engine hachimi).

**Đính chính quan trọng (23/07, sau khi đọc model card):** base `HachimiMT-60-zh-vi` pretrain
trên **~350k cặp** (`ngocdang83/tran-vi-teacher`, teacher **Gemini 2.5/3.0/3.1**) +
`chi-vi/hirashiba-mt-zh2vi-b-filtered` (web-novel), phủ **xianxia/modern/sci-fi/history**.
→ Base KHÔNG lệch game, coverage thể loại KHÔNG phải vấn đề. Bỏ tiền đề "lệch tủ". Và teacher
của base là **Gemini (frontier), MẠNH HƠN mistral-small** → **TUYỆT ĐỐI KHÔNG bulk-regenerate
teacher bằng mistral NIM** (distill từ thầy yếu hơn = kéo model xuống). Đây là điều chỉnh lớn
so với bản nháp đầu.

**QUYẾT ĐỊNH BASE (23/07, đã thử THẬT — không đoán):** đã test base to hơn trên câu
production thật + CPU 2 threads: **Qwen2.5-0.5B-Instruct** (chatbot, bịa/viết tiếp tiếng
Trung, 9 chữ/s), **NLLB-200-distilled-600M** (dịch thật nhưng biến thuật ngữ tu tiên
九天御龙决→"chín ngày", mất tên riêng, 5 chữ/s ≈ 10-17× chậm), **small100-300M** (xuất tiếng
Anh, hỏng). → **KHÔNG đổi base.** Hachimi-57M chuyên dụng (train 698k cặp tiểu thuyết) THẮNG
mọi base to hơn ở thuật ngữ + tốc độ; model đa dụng to hơn thua vì không biết từ tu tiên +
chậm ~10× trên VPS 2 core. Chốt: **finetune chính 57M**, chấp nhận trần cấu trúc (câu phức).
Trần đó KHÔNG phải register (register dạy được) mà là dung lượng cho câu dài/đảo mệnh đề.

**Định hướng đúng của vòng này = SỬA LỖI CÓ CHỦ ĐÍCH, không re-distill:**

1. **Register drift có thật (lỗi ưu tiên #1).** `glossary_terms` (approved, có wrong_vi) chứa
   cặp user sửa tay: `cậu→ngươi`, `mình→hắn`, `em gái mình→em gái hắn`. Model production VẪN
   lọt đại từ hiện đại. → Trị bằng booster register + gold, KHÔNG cần thầy mạnh (register là
   pattern cơ học).
2. **Các lỗi model-limit đã liệt kê** (memory `hachimi-game-finetune` mục "How to apply"):
   thuật ngữ tái diễn (枪兵→thương binh, 冷却期→thời gia hồi...), convertese, đảo tân ngữ
   (57M — chấp nhận). → Booster targeted + gold.
3. **Nguồn dữ liệu = MINE LỖI từ production, không sinh teacher bulk.** `content_zh`+`content_vi`
   của 2819 chương = cặp (nguồn, bản-hachimi-hiện-tại). Quét để TÌM chỗ model đang sai
   (register leak, nói lắp, term sai) → chỉ những câu ĐÓ mới cần nhãn đúng (gold tay / thầy
   mạnh cho số ít), phần còn lại model đã dịch ổn, không cần đụng.

**Mục tiêu v-next (thu hẹp, đo được):**
- Giảm register drift ở production (đếm đại từ hiện đại lọt, không phải chrF).
- Sửa nhóm lỗi thuật ngữ/convertese tái diễn theo bảng kiểm.
- Nạp bản sửa tay user làm gold trọng số cao.
- KHÔNG kỳ vọng model học tên riêng hiếm / item (giao termguard + glossary — xem
  `worker/novelworker/translator/termguard.py`, memory `hachimi-termguard-dinh-chu`).
- KHÔNG re-distill bulk; giữ 350k Gemini teacher làm replay (retention), chỉ THÊM data targeted.

**Thước đo (không dùng chrF — đã kết luận cùn):** bộ `eval_gold`/`approved_gold` giữ nguyên
làm hold-out + **đếm lỗi targeted** (script §9): (a) tỉ lệ dòng lọt đại từ hiện đại
(tôi/mình/cậu/anh/cô ta...); (b) số câu nói lắp; (c) số ca thuật ngữ tu luyện sai theo bảng
kiểm; (d) sót chữ Hán. So model cũ vs mới trên cùng tập.

---

## 1. Bước 1 — Mine LỖI của model hiện tại từ production (không lấy bulk source)

**Script mới: `worker/hachimi_finetune/01_mine_prod_errors.py`**

Mục đích: model đã dịch 2819 chương rồi — thay vì sinh corpus mới, QUÉT bản dịch hiện tại
để tìm chỗ model SAI, chỉ những chỗ đó mới cần dạy lại. Đây là "đọc dữ liệu thật từ DB" đúng
nghĩa: dùng (content_zh, content_vi) làm cặp (nguồn, output-model) để lộ lỗi.

Input: DB (`from novelworker import db`). Output:
`dataset/error_cases.jsonl` `{"zh": <câu nguồn>, "vi_model": <câu model dịch>, "tag": <loại lỗi>, "novel_id","chapter_index"}`.

Logic — page qua chương done, tách câu song song zh↔vi (theo dòng, vì hachimi dịch giữ khung
dòng), gắn cờ câu có dấu hiệu lỗi:
1. **register**: câu LỜI KỂ (ngoài ngoặc) chứa đại từ hiện đại (tôi/mình/cậu/anh ta/cô ta/
   cô ấy) — reuse regex `_NARRATOR_TERMS`/`_MODERN_PRONOUN` trong `lint.py`. (Lỗi ưu tiên #1.)
2. **stutter**: `DUP_PHRASE` khớp (dù runtime `_clean_output` đã vá — vẫn mine để dạy sạch).
3. **term**: câu chứa cụm trong bảng kiểm thuật ngữ (§4 nhóm 2/4) mà dịch ra khác chuẩn.
4. **convertese**: khớp các luật `_fix_soft_style` (không khỏi/tổng cảm thấy/...).
Chỉ giữ câu ĐỦ NGẮN (≤180 Hán) và cặp thẳng hàng (số dòng zh≈vi). Khử trùng theo hash zh.

Đây KHÔNG phải nhãn train (vi_model là output SAI) — nó là DANH SÁCH ca cần nhãn ĐÚNG ở §2/§3.
Egress: chỉ select `content_zh,content_vi`, page `.range`, có `--limit-novels` chạy thử.

**KHÔNG cần** kéo bulk source theo phân bố thể loại nữa (base đã phủ rộng — đính chính §0).

---

## 2. Bước 2 — Nhãn ĐÚNG cho ca lỗi (targeted, thầy MẠNH — không mistral bulk)

**Script mới: `worker/hachimi_finetune/02_label_errors.py`**

Mục đích: chỉ các câu ở `error_cases.jsonl` (số ÍT so với 40k bulk) mới cần nhãn đúng. Vì
base học từ Gemini (mạnh), nhãn mới PHẢI ≥ chất Gemini, KHÔNG được dùng mistral yếu hơn làm
nhãn bulk. Ba nguồn nhãn, ưu tiên giảm dần:

1. **Rule-based cho register** (đa số ca #1): lỗi register là cơ học — có thể sinh nhãn đúng
   bằng REGEX thay pronoun trong chính `vi_model` (cậu→ngươi, mình→hắn theo giới tính nhân
   vật lời kể). KHÔNG cần LLM. Đây là phần lớn gold, rẻ và chắc.
2. **User gold** (§3): chỗ user đã sửa tay = nhãn người, chất cao nhất.
3. **Thầy = Codex GPT-5.6-luna (user chốt 23/07).** KHÔNG cần Gemini/mistral API — dùng thẳng
   Codex qua MCP làm thầy dịch ca khó. Codex đọc `zh` + luật register → xuất `vi` đúng. Vì
   Codex là model mạnh (≥ Gemini-teacher của base) nên nhãn nó tạo ĐỦ chất để distill.
   - Input đã mine sẵn: `dataset/error_cases.jsonl` (800 ca register, có `zh` + `vi_model` sai).
   - Quy trình: VALIDATION batch ~40 ca trước → người duyệt chất → rồi mới chạy full 800 +
     mở rộng sang tag khác (stutter/term/convertese).
   - Luật cho thầy (chép vào prompt): lời KỂ ngôi ba nam→hắn nữ→nàng; ngôi nhất/độc thoại
     nội tâm→**ta** (KHÔNG tôi/mình); thoại→ta/ngươi + vai vế; **giữ Hán-Việt cho từ gốc Hán**
     (骷髅=khô lâu), chỉ từ gốc Tây mới trả Tây; KHÔNG tự đệm hư từ (đâu/nhé/mà). LỜI TÁC GIẢ
     (preface, "tôi lấy X làm nữ chính") thì GIỮ tôi — không ép, và đánh dấu loại khỏi gold.

Output: `dataset/labeled_gold.jsonl` `{"zh","vi","tag","label_src": "rule"|"user"|"codex"}`.

**Nguyên tắc vàng: thà ÍT gold đúng-chắc còn hơn nhiều gold từ thầy yếu làm hỏng giọng.**

**Volume đo thật (23/07):** register leak = **19.7% chương, ~1458 ca** (tôi 798, mình 426,
cậu 234) — KHÔNG hiếm, và mình/tôi post-process KHÔNG vá được (không biết thay bằng ai) →
train là đúng lever. Đây là lớp lỗi lớn nhất, làm trước.

---

## 3. Bước 3 — Mine bản sửa tay của user thành gold (tín hiệu vàng)

**Script mới: `worker/hachimi_finetune/03_mine_user_gold.py`**

Mục đích: các chỗ user ĐÃ sửa tay = nhãn người, chất lượng cao nhất, bám đúng lỗi thật.
Nhưng phần lớn là lỗi TÊN (việc glossary) → phải LỌC ra lỗi CÂU/REGISTER (việc model học).

Input DB:
- `chapter_edit_vi_history` (wrong, correct, novel_id, chapter_index) — 15 dòng hiện có,
  sẽ tăng dần; script chạy lại được.
- `glossary_terms` approved có `wrong_vi` (114 cặp) — nhưng đây là term đơn lẻ.

Output: `dataset/user_gold.jsonl` `{"zh"?, "vi", "kind": "register"|"phrase", "src"}`.

Logic phân loại (QUAN TRỌNG — đừng nhét lỗi tên vào train):
1. **GIỮ (đưa vào gold)**: cặp mà `wrong→correct` là REGISTER/đại từ/cấu trúc câu —
   nhận diện bằng bảng: wrong hoặc correct chứa {tôi, mình, cậu, anh ta, cô ta, cô ấy, em}
   ↔ {ta, ngươi, hắn, nàng}; hoặc đảo trật tự từ (tươi huyết→máu tươi). Đây là cái model
   PHẢI học. Với `chapter_edit_vi_history` có (novel_id, chapter_index) → lấy được CÂU chứa
   `correct` từ `content_vi` hiện tại để có ngữ cảnh câu đầy đủ (không chỉ cụm).
2. **LOẠI (giao glossary/termguard, KHÔNG train)**: cặp là tên riêng/item/địa danh —
   `term_type` person/place/sect/item/skill, hoặc chỉ khác nhau ở cách phiên âm Hán-Việt
   (dùng `hanviet.han_viet` so khớp). VD Laosen→La Sâm, Cú Nguyên Đan→cố nguyên đan.
3. Với gold register: nếu có câu zh gốc (qua chapter_index → content_zh + căn cụm) thì ghi
   cặp {zh, vi}; nếu chỉ có cụm vi (glossary) thì để `kind:"phrase"` không zh — dùng ở
   booster §4 thay vì train trực tiếp (train câu→câu cần zh).

Số lượng nhỏ (chục dòng) nhưng weight cao (§7 gold_repeat). Sẽ lớn dần khi user sửa nhiều.

---

## 4. Bước 4 — Booster tổng hợp cho lỗi model-limit CÓ THẬT

**Script mới: `worker/hachimi_finetune/04_make_booster.py`** (nâng cấp ý tưởng
`05_make_booster.py` cũ đã mô tả trong memory).

Mục đích: các lỗi đã biết mà data thật ĐÓI ví dụ → sinh câu template dạy có chủ đích.
CHỈ làm cho lỗi model HỌC ĐƯỢC (register, convertese phổ biến, thuật ngữ tu luyện tái
diễn), KHÔNG làm cho tên hiếm/item (giao glossary).

Nhóm booster (mỗi nhóm N câu, slot điền từ danh sách):
1. **Register lock** — bám lỗi thật §3: câu kể ngôi ba (nam→hắn, nữ→nàng), độc thoại→ta;
   thoại cổ phong ta/ngươi. Sinh CẶP nhiều biến thể để model không quen "tôi/mình/cậu".
   Slot: động từ, tên (đánh dấu bằng placeholder để termguard-style, hoặc tên phổ biến).
2. **Thuật ngữ tu luyện huyền huyễn/tiên hiệp** (coverage gap §1): bảng cụm cố định
   zh→vi kiểu QT chuẩn (筑基→trúc cơ, 金丹→kim đan, 元婴→nguyên anh, 渡劫→độ kiếp, 灵气→linh
   khí, 修为→tu vi, 突破→đột phá, cảnh giới...). Lấy danh sách từ memory `xianxia-lore-sources`
   nếu có, hoặc dựng bảng ~150 cụm. Nhúng vào câu mẫu tự nhiên.
3. **Convertese phổ biến** (đã có `_fix_soft_style` lo runtime, nhưng dạy model để đỡ phải
   vá): 不禁→..., 总感觉→cứ cảm thấy, 直接+V, 一下→... — dạy bản tự nhiên.
4. **Game terms từ danh sách lỗi cũ** (giữ, đừng bỏ coverage game): 游戏玩家→người chơi,
   枪兵→thương binh, 冷却期→thời gian hồi, 白嫖→hưởng free, 数字+点→giờ.

**Gate EXPECTED (bắt buộc, học từ v4):** mỗi câu booster biết TRƯỚC đáp án đúng; nếu teacher
(nếu dùng teacher điền) trả khác đáp án kỳ vọng → loại. Template register/term thì đáp án
tự sinh, không cần teacher. Oversample ×N (v4 dùng ×15) cho từ đói data.

Output: `dataset/booster.jsonl` `{"zh","vi","group"}`.

Lưu ý template (bài học v4): 氏家族 phải dùng HỌ ĐƠN; tránh tên Trung không tự nhiên;
đa dạng cấu trúc câu để không overfit khuôn.

---

## 5. Bước 5 — QC gates lọc gold + booster

**Script mới: `worker/hachimi_finetune/05_qc_gates.py`**

Mục đích: gold (kể cả rule-fix, user) và booster đều có thể lỗi → lọc trước khi train, tránh
đầu độc model.

Input: `labeled_gold.jsonl` + `user_gold.jsonl` + `booster.jsonl`. Output:
`dataset/train_clean.jsonl` (đã qua gate) + `dataset/rejected.jsonl` (để soi lý do).

Các gate (reject nếu vi phạm):
1. **Register gate**: vi (phần LỜI KỂ, ngoài ngoặc thoại) chứa đại từ hiện đại
   (tôi/mình/cậu/anh ta/cô ta/cô ấy) → reject. Đây là lỗi nghiêm trọng nhất (§0 mục tiêu).
   Tái dùng regex `_NARRATOR_TERMS`/`_MODERN_PRONOUN` nếu có trong `lint.py`.
2. **Sót Hán**: vi còn ký tự Hán → reject (`[一-鿿]`).
3. **Nói lắp**: `DUP_PHRASE` (trong `worker.py`) khớp → reject (dạy sạch từ đầu).
4. **Hư từ đệm**: vi tự thêm "đâu/nhé/mà/á" cuối câu mà zh không có tín hiệu ngữ khí → reject
   (gate v4 đã làm, ~722 dòng bị loại — giữ luật này).
5. **Escape/rác**: `u00[0-9a-f]{2}`, markdown, code fence → reject.
6. **Độ dài lệch**: len(vi) ngoài khoảng [0.5, 4.5]×len(zh) → reject (cụt/phình).
7. **Trùng eval**: zh có trong hold-out → reject.

Log thống kê reject theo gate để biết teacher yếu chỗ nào.

---

## 6. Bước 6 — Trộn tập train cuối

**Script mới: `worker/hachimi_finetune/06_build_train.py`**

Input: `train_clean.jsonl` (gold đã lọc) + `booster.jsonl` (đã lọc) + **350k replay
`tran-vi-teacher` (HF, tải qua `kaggle_train.py` sẵn có) + `dataset/train_v2.jsonl`** (chống
quên) + `approved_gold.jsonl` (giữ hold-out, KHÔNG train phần eval).

Output: `dataset/train_vnext.jsonl` (`{"zh","vi"}` — khớp `kaggle_train.py:_pair`).

Tỉ lệ trộn — vòng SỬA CHỮA nên replay chiếm đa số (giữ giọng), gold targeted nhỏ nhưng nặng:
- **Replay retention: phần lớn** (350k Gemini teacher + train_v2 qua register gate) — giữ
  nguyên năng lực base, KHÔNG để data nhỏ mới làm lệch.
- Booster oversample: ~8–10k — targeted.
- Gold (rule register + user) repeat ×10–15 (vàng, ít nên nhân mạnh).
Ghi chú: `kaggle_train.py` đã có cơ chế trộn pro/replay từ `tran-vi-teacher` + `--extra-replay`
+ `--gold` với `--gold-repeat`; chỉ cần đưa `train_clean.jsonl` (gold+booster) vào `--gold`
và giữ replay mặc định. Có thể KHÔNG cần `06_build_train.py` riêng — tận dụng flag sẵn có.

**Chống quên (bài học replay v2→v4):** GIỮ replay 350k, đừng train chỉ trên data mới kẻo mất
giọng. Replay PHẢI qua register gate §5 (bài học v2: replay không lọc = lọt "tôi").

---

## 7. Bước 7 — Train trên Kaggle

Tái dùng **`kaggle_train.py` hiện có** (đã vá lỗi Marian pad off-by-one — monkeypatch
`_remove_pad_weights`=no-op + `get_vocabulary` BartLoader; commit f247e54). Chỉ đổi input:
`--gold approved_gold.jsonl --extra-replay dataset/train_vnext.jsonl`.

Checklist (bài học đau từ memory):
- **Upload BẢN MỚI** của dataset lên Kaggle (v-cũ hay quên → crash converter).
- HF token cho `tran-vi-teacher` trong Kaggle Secrets.
- `--export-ct2` để ra thẳng model CT2 int8 deploy được (~58MB).
- Tham số mặc định trong README (2×T4, batch 8, grad-accum 4, lr 3e-5, 3 epoch, gold-repeat 5).
- Model base: `ngocdang83/HachimiMT-60-zh-vi` (MODEL_ID trong kaggle_train.py).

Output: zip CT2 → tải về `worker/hachimi_finetune/hachimi-ct2-int8.zip`.

---

## 8. Bước 8 — Đánh giá targeted (KHÔNG chrF)

**Script mới: `worker/hachimi_finetune/07_eval_targeted.py`**

Mục đích: so model CŨ (`worker/models/hachimi-ct2/`) vs MỚI trên cùng tập, đếm lỗi theo
loại — vì chrF đã kết luận cùn (3 bản v3/v4 hoà ~51).

Input: tập hold-out = `approved_gold.jsonl` + ~200 câu production MỚI (không train). Dịch cả
2 model (load CT2 local qua `hachimi_engine` với `HACHIMI_MODEL_DIR` trỏ từng model), qua
CÙNG termguard+glossary như production.

Đo (in bảng so sánh cũ vs mới):
- % dòng lọt đại từ hiện đại (mục tiêu chính — phải GIẢM).
- Số câu nói lắp (`DUP_PHRASE`).
- Sót chữ Hán.
- Đếm ca thuật ngữ tu luyện sai theo bảng kiểm (~30 cụm vàng: 筑基/金丹/元婴... phải ra đúng QT).
- Đệm hư từ thừa.

Chốt nhận model mới CHỈ KHI: register drift giảm + không hồi quy giọng cổ phong (spot-check
tay vài chương huyền huyễn/tiên hiệp).

---

## 9. Bước 9 — Deploy (đã có quy trình)

Sau nghiệm thu: giải nén zip vào `worker/models/hachimi-ct2/` (gitignored), scp lên VPS
`/root/Novel_Project/worker/models/hachimi-ct2/`, rebuild + `up -d` (COPY code vào image;
xem memory `hachimi-termguard-dinh-chu` phần deploy). KHÔNG cần đổi code worker (chỉ đổi file
model). Requeue nếu muốn dịch lại kho bằng model mới (cân nhắc — 2819 chương, chạy nền).

---

## 10. Thứ tự file & việc cho Codex (tóm tắt)

| Script (mới) | Input | Output | Ghi chú |
|---|---|---|---|
| `01_mine_prod_errors.py` | DB (content_zh+content_vi) | `dataset/error_cases.jsonl` | quét LỖI model hiện tại, không lấy bulk |
| `02_label_errors.py` | error_cases | `dataset/labeled_gold.jsonl` | rule cho register; thầy mạnh CHỜ user |
| `03_mine_user_gold.py` | DB (edit_hist + glossary) | `dataset/user_gold.jsonl` | LỌC register vs tên |
| `04_make_booster.py` | bảng term nội bộ | `dataset/booster.jsonl` | gate EXPECTED, oversample |
| `05_qc_gates.py` | labeled+booster | `train_clean.jsonl`+`rejected.jsonl` | 7 gate |
| `06_build_train.py` | tất cả trên + 350k replay | `dataset/train_vnext.jsonl` | gold targeted + replay retention |
| `kaggle_train.py` (có sẵn) | train_vnext | model CT2 | chỉ đổi input |
| `07_eval_targeted.py` | 2 model | bảng so sánh | đếm lỗi, không chrF |

**Nguyên tắc xuyên suốt (đừng phá):**
- Tên riêng/item hiếm KHÔNG dạy model → glossary + termguard lo. Model chỉ học GIỌNG,
  REGISTER, THUẬT NGỮ PHỔ BIẾN, CÂU TỰ NHIÊN.
- **KHÔNG bulk-distill bằng mistral** (yếu hơn Gemini-teacher của base) — chỉ THÊM gold
  targeted + giữ 350k Gemini replay. Vòng này là SỬA CHỮA, không phải train lại từ đầu.
- Mọi nhãn (gold/replay/booster) PHẢI qua register gate — bài học v2 lọt "tôi".
- Giữ 350k `tran-vi-teacher` replay chống quên giọng đã nghiệm thu.
- Đo bằng đếm lỗi targeted, không chrF.
- `text_clean.py` trong hub PHẢI đồng bộ với `worker/novelworker/translator/text_clean.py`.

**Rủi ro / điểm cần user quyết trước khi Codex chạy:**
1. **Nhãn cho ca KHÓ (§2 nguồn 3)**: project chỉ còn NVIDIA/mistral (yếu hơn Gemini). User có
   Gemini API để làm nhãn ca khó không? Nếu KHÔNG → chỉ dùng rule register + user gold +
   booster (bỏ ca khó cần thầy), an toàn hơn là dùng mistral làm hỏng giọng.
2. Có requeue lại toàn kho sau khi có model mới không (tốn ~1 ngày nền VPS)?
3. Bảng thuật ngữ tu luyện §4 nhóm 2 — user duyệt cách đọc chuẩn (筑基→trúc cơ...) trước
   khi đưa vào booster, để khỏi dạy sai hàng loạt.
4. Vòng này nhỏ (sửa chữa) — cân nhắc liệu có ĐÁNG train lại không, hay chỉ cần: rule-fix
   register ở POST-PROCESS (thêm vào `_fix_register` trong worker.py) + termguard cho term?
   Nếu lỗi register hiếm, vá runtime rẻ hơn train. **User cân nhắc trước khi bỏ công train.**
-->
