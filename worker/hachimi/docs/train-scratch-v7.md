# Train from scratch v7 — chốt kiến trúc + thang probe

> Dựng 30/08/2026. Thay thế phần "HƯỚNG LỚN CHƯA LÀM" của `ban-giao-2026-08-30.md`.
> `HUONG_DAN_TRAIN_TU_DAU.md` chỉ còn giá trị giải nghĩa thuật ngữ — cấu hình trong đó đã cũ.

## 0. Vì sao từ đầu, không finetune nữa

v6 = v5 + 4.024 cặp epub (4,7% pack) → văn xuôi **không nhích**, thơ nhích 31,3% → 22,6%.
Giải thích: HachimiMT-60 là model **trained-from-scratch trên 350k cặp teacher Gemini**, cái
prior đó ghim chặt. Thêm 4,7% data không lay nổi. Thơ nhích được vì v5 gần như **bằng 0** ở
thơ — chỗ trống thì ít data cũng thấy.

⇒ Muốn đổi văn xuôi thì phải đổi prior. Đó là train from scratch, không phải đổi kiến trúc.
**Kiến trúc sửa để lấy hai thứ finetune không bao giờ lấy được** (ngữ cảnh + tokenizer của
chính mình), chứ không phải để chữa văn xuôi.

## 1. Ràng buộc cứng

| ràng buộc | hệ quả |
|---|---|
| Chạy CT2 int8 trên box i5-6200U, 4 luồng, 7GB RAM | kiến trúc **phải convert được sang CTranslate2** — ngoài họ Marian/Transformer là chết ở khâu export, sau khi đã đốt 30 giờ GPU |
| `hachimi_beam_size=6`, `hachimi_nbest=6` (đã đo A/B, không hạ được) | chi phí decode **nhân 6 theo số layer decoder**; encoder chạy 1 lần/câu, **không** nhân |
| Model to hơn không dịch hay hơn (madlad 3B chrF 27,1 vs Hachimi 56M 60,6) | cấm tăng `d_model`, cấm bỏ dạng bất đối xứng |
| Kaggle 30 giờ GPU/tuần | probe + bản thật không lọt một tuần — phải chia lịch |

Hệ quả quan trọng nhất: **thêm layer encoder gần như miễn phí, thêm layer decoder đắt gấp 6.**
Dạng 8 enc / 2 dec của HachimiMT-60 vốn đã đúng cho CPU. Giữ triết lý, chỉ dịch chuyển ngân sách.

## 2. Hai thay đổi được chốt

### 2.1 Doc-level `⟪ctx⟫` làm định dạng GỐC

Khung đã dựng sẵn và đang nằm im:

- `pipeline/16_make_doclevel.py` — dựng cặp `ctx ⟪ctx⟫ câu → dịch câu`
- `pipeline/17_build_doclevel_corpus.py` — corpus doc-level
- runtime `novelworker/translator/hachimi_engine.py:273-305` — ghép ctx + chấm n-best theo câu hiện tại
- `novelworker/config.py: hachimi_context_lines = 0` — TẮT, kèm chú "chỉ bật SAU khi deploy
  model đã train doc-level"

Train from scratch là **lần duy nhất** ghép được nó vào làm định dạng gốc thay vì ghép nối.
Nó đánh trúng những lỗi đã đo mà finetune chữa không nổi: bịa chủ ngữ (27/104 ca cả 6 beam đều
bịa), đại từ hiện đại, lệch tên chương đầu, trôi xưng hô. Model câu-lẻ **không thể** biết 他 là
ai — nó đang đoán.

Giá: nguồn dài gấp ~2-3 ⇒ **encoder** tốn hơn, đúng phía rẻ.

**Trộn ctx-0/1/2 (40/30/30)** chứ không phải 100% ctx-2: model phải dịch được cả khi không có
ngữ cảnh (dòng đầu chương, fallback, `hachimi_context_lines=0`).

### 2.2 Nấu lại SentencePiece trên corpus của chính mình

SPM 24k hiện tại fit trên 350k cặp Gemini — không phải văn của dự án. Fit lại trên kaihe + moa
+ thơ: **ít token hơn cho cùng một câu** ⇒ vừa nhanh hơn khi decode vừa dịch tốt hơn, không tốn
một tham số nào. Món free duy nhất trong danh sách.

**ĐÃ ĐO — dùng bản `scratch/spm24k_clean/fertility.json`:**

| | token/câu SPM cũ | SPM mới | đổi |
|---|---|---|---|
| zh (vào **encoder**) | 18,75 | 17,01 | **−9,3%** |
| vi (ra từ **decoder**) | 24,93 | 24,91 | −0,1% |

⚠ Có **HAI** thư mục SPM, đừng lấy nhầm: `scratch/spm24k/` nấu trên corpus **chưa lọc** ra
−4,5%; `scratch/spm24k_clean/` nấu sau khi bỏ 34% kho-máy (chữ Hán tách rời từng chữ) ra
**−9,3%** — gấp đôi mức lợi, vì phần văn bản tách rời chính là thứ làm SPM học nhầm mảnh.
Bản dùng là **`spm24k_clean/`**.

Nấu lại chỉ thắng ở **phía nguồn** — đúng cái phía vốn đã rẻ. Phía sinh chữ, tức phía quyết
định tốc độ, **không đổi**. Giải thích: SPM cũ fit trên bản dịch Việt của teacher Gemini, cùng
miền văn nên vi vốn đã khớp; zh khá hơn vì corpus mới nhiều văn Trung gấp 5 lần.

⇒ **Chốt 24k, khỏi thử 32k.** vi không ngắn đi thì 32k chỉ gánh thêm ~33% chi phí lớp chiếu
output mỗi bước decode mà không có gì bù. Câu hỏi này đã đóng, đừng khảo sát lại.

Khác một điểm so với chú thích của `16_make_doclevel.py` ("SEP là chuỗi thường, SPM tự học"):
vì lần này **tự nấu SPM**, khai `⟪ctx⟫` là `user_defined_symbol` cho nó thành **một piece
nguyên khối**. Không phải "mổ vocab" — nó nằm trong vocab từ lúc sinh ra.

## 3. Cấu hình đề xuất

| | HachimiMT-60 (nay) | v7 |
|---|---|---|
| encoder_layers | 8 | **12** |
| decoder_layers | 2 | **2** (không đụng) |
| d_model / heads | 512 / 8 | 512 / 8 |
| encoder_ffn_dim | 3072 | **2048** |
| decoder_ffn_dim | 3072 | **2048** (ffn 2048 CẢ HAI phía) |
| vocab | 24k (SPM của người khác) | **24k, fit lại trên corpus mình** |
| max_position_embeddings | 512 | 512 (đủ chứa ctx) |
| activation | swish | swish |
| share embeddings | true | true |
| định dạng train | câu lẻ | **trộn ctx-0/1/2** |

Đếm tham số (emb 24k×512 dùng chung):

```
nay: 12,3M emb + 8×(1,05 attn + 3,15 ffn) + 2×(2,10 attn + 3,15 ffn) = 56,4M  ✓ khớp "57M"
v7 : 12 enc / 2 dec, ffn 2048 cả hai                                 = 58,4M
```

+3,5% tham số nhưng phần tăng nằm **hết ở encoder** ⇒ chi phí mỗi token sinh ra gần như không
đổi. Vẫn là `MarianMTModel` thuần, CT2 nuốt được.

⚠ **Mã là bản chuẩn, không phải bảng này** — `pipeline/train_scratch.py: PRESETS`. Ở đó còn
preset **`v7-fast`** (12 enc / **1** dec, 54,2M): decoder là phía nhân 6 vì beam nên hạ 1 layer
là đường rẻ nhất nếu cần nhanh hơn. Để sau, chưa đo.

## 4. Không đổi

- Không RoPE, không GQA, không kiến trúc lạ — CT2 không convert được, và đến lúc export mới
  biết thì đã mất 30 giờ GPU.
- Không làm decoder sâu hơn (nhân 6 vì beam).
- Không tăng `d_model` — đã có số đo bác bỏ.
- Không đổi `max_position_embeddings` — 512 đủ cho ctx-2, tăng lên là tốn positional embedding
  vô ích.

## 5. Thang probe — đổi đúng MỘT nút mỗi bậc

Mỗi bậc ~2M cặp × 1 epoch, model tiny (~15M: 6 enc / 1 dec / d_model 256) để chạy 1-2 giờ.
So với `chi-vi/hirashiba-mt-tiny-zh-vi` (15M, cùng cỡ) làm mốc.

| bậc | đổi gì | trả lời câu hỏi | cổng đi tiếp |
|---|---|---|---|
| **P0** | kiến trúc y gốc + **SPM mới**, câu lẻ | *data người có đủ không?* | chrF đứng được cạnh model production (xem cảnh báo dưới) |
| **P1** | P0 + **doc-level ctx** | *ctx có hạ bịa chủ ngữ không?* | `eval_project_metrics` hạ đại từ hiện đại / bịa chủ ngữ |
| **P2** | P1 + **12 enc / ffn 2048** | *chiều sâu encoder có trả lãi?* | chrF hoặc thước dự án nhích, thời gian decode không tăng |

P0 thua xa ⇒ dừng, khỏi mất hai tuần. P1 không hạ được ⇒ bỏ doc-level, đỡ phức tạp runtime.
P2 không nhích ⇒ giữ 8 enc, tiết kiệm giờ train.

⚠ **Cảnh báo về cổng P0** (hố mà bản bàn giao chưa thấy): bộ dev là truyện holdout của kaihe,
mà probe cũng train trên kaihe ⇒ probe có **lợi thế sân nhà**. Nó thắng
`hirashiba-mt-tiny` gần như chắc chắn, và điều đó **không chứng minh gì**. Nên chấm kèm mốc thứ
hai là chính **model production** (57M, train trên data khác, cũng chịu bất lợi sân khách y
hệt). Đọc số theo ba nước:

- p0 **sập hẳn** so với cả hai mốc ⇒ 2M cặp chưa đủ dựng model từ số 0, **dừng**.
- p0 **đứng được** cạnh production dù chỉ 12M vs 57M ⇒ dây chuyền lành, bản thật (11M cặp,
  57M tham số) đáng bỏ 15-30 giờ.
- p0 **thắng đậm cả hai** ⇒ đừng mừng, phần lớn là sân nhà.

**Thước**: chrF chỉ dùng ở P0 để trả lời câu hỏi *data*. Từ P1 trở đi dùng thước dự án
(`eval/eval_project_metrics.py`, `eval/eval_poem.py`) — chrF với một bản dịch tay bất kỳ
thưởng model trung tính, đã ghi ở phần "đừng làm lại".

## 6. Data cho bản thật

| nguồn | lượng | vai trò |
|---|---|---|
| `kaihe_parallel_sentences.jsonl` | 332 truyện · 32M cặp thô → **10.186.174 dòng / 117 truyện** sau cổng | **mỏ neo người dịch** — lợi thế thật so với model gốc (họ 100% máy) |
| `moa_zh_vi.parquet` | 396k cặp văn học cổ điển | giọng cổ |
| `data/poem_vi.jsonl` → `scratch/poem_corpus.jsonl` | 33.200 bài → **203.039 VẾ** (XONG 01/09) | trục thơ — phiên âm thô 32,4% → **2,2%** |
| `tran_vi_teacher.jsonl` | 350k cặp Gemini | **liều thấp** — data máy, chỉ để phủ subject-drop |
| `scratch/prose_corpus.jsonl` | **76.771 cặp / 1.667 truyện epub** (XONG 01/09) | từ vựng + tình tiết kaihe KHÔNG có; dịch Gemini đã soát 4 vòng |

Cổng: `kaggle_train._replay_ok` (79% qua) → LaBSE **≥0,50** (90% qua, xem mục 14 — con số 0,70
ở bản bàn giao cũ đã bị bác) → **`pipeline/quality_gate.py`** gác theo LÔ (mục 21).

**ĐÃ DỰNG 01/09** — `scratch/corpus_full_v7.jsonl` = **10.465.589 dòng** (kaihe 10.186.174 +
prose 76.406 + thơ 203.009), dev riêng `scratch/dev_full.jsonl`. Đây là bản THẬT, chưa qua
LaBSE.

⚠ `--limit` **không** tỉ lệ thuận với số dòng ra, đừng suy diễn: cùng seed, limit 2M→1,74M,
10M→7,48M, **12M→5,84M** (ÍT hơn 10M), 30M→10,19M. Lý do: quota mỗi truyện lớn lên thì các
truyện ĐẦU đổ hết câu của mình vào bộ khử trùng toàn cục, gồm cả đống câu ngắn phổ thông, làm
truyện SAU bị loại sạch. Muốn biết một `--limit` cho ra bao nhiêu thì **phải chạy**, và đừng
ngoại suy giữa chừng — đo lúc 225/332 truyện được 5,49M, ngỡ chạm trần, thực tế về đích
10,19M.

⚠ Chỉ **117/332 truyện** kaihe vào được corpus — 215 truyện còn lại bị `is_machine_shard` loại
TRỌN, vì kho-máy nằm gọn theo truyện chứ không rải rác. Con số "117 giọng" khớp phiên 30/08.

⚠ LaBSE là một job GPU riêng — **probe bỏ qua LaBSE**, chỉ `_replay_ok`. Xem mục 11.

⚠ Định dạng kaihe: **mỗi dòng jsonl là MỘT TRUYỆN**, `{"name", "sentences": [[vi, zh], ...]}`
theo đúng thứ tự — nên dựng được ctx trực tiếp. Tiếng **Việt đứng trước**, tiếng Trung sau.

⚠ Prose **chỉ vào TRAIN, không sinh dev**. Dev phải là bản dịch NGƯỜI (truyện holdout kaihe);
nhét bản dịch Gemini vào dev thì thước đo thành "bắt chước teacher giống đến đâu" chứ không
còn là "dịch hay đến đâu" — đúng cái bẫy đã ghi ở mục 5. Đã đo: prose trùng `dev.jsonl` = **0**,
trùng kaihe = 69 câu (epub và kaihe gần như rời nhau, đúng như giả định).

## 7. Chống rò

- Tách **theo TRUYỆN**, không theo câu: truyện holdout không có một câu nào trong train.
- Chặn thêm mọi `zh` có trong `data/eval_locked/*.jsonl` + `eval_poem_locked.jsonl`.

⚠ Đo 01/09: `corpus2m.jsonl` (dựng 30/08) có **14 câu trùng `dev.jsonl`** — rò sẵn từ trước,
không phải do gộp prose (prose rò 0). 14/1,92M nên bỏ qua được, nhưng dựng lại corpus thì
nhớ chặn cả `dev.jsonl`, đừng chỉ chặn `eval_locked`.

## 8. Lịch Kaggle

Quota 30 giờ GPU/tuần, reset thứ 2. Bản thật 15-30 giờ ⇒ probe và bản thật **không lọt cùng
tuần**. Ba probe gộp vào **một kernel chạy tuần tự** (~4-6 giờ) để đỡ chi phí push, chạy nốt
tuần này; bản thật để tuần sau.

Quy trình + toàn bộ bẫy Kaggle: `docs/kaggle-cli.md`. **Đọc trước, đừng dò lại** — đã trả giá
9 lượt push.

## 9. File

| file | việc |
|---|---|
| `pipeline/28_build_scratch_corpus.py` | kaihe → corpus mang sẵn `ctx`, tách theo truyện, chặn eval |
| `pipeline/29_train_spm.py` | nấu SPM joint 24k + `source.spm`/`target.spm`/`vocab.json`, đo fertility |
| `pipeline/train_scratch.py` | dựng `MarianConfig` từ số 0, train, export CT2 |
| `pipeline/kaggle_probe_v7.py` | kernel Kaggle: dò môi trường → smoke → P0/P1/P2 tuần tự |
| `eval/eval_scratch_probe.py` | chấm chrF ba bậc ở nhà so với mốc `hirashiba-mt-tiny` |
| `pipeline/35_build_prose_corpus.py` | 401 lô prose → shard corpus (nhãn truyện, ctx, cổng lọc) |
| `pipeline/36_build_poem_booster.py` | 337 lô thơ → `data/poem_vi.jsonl`, kèm thước phiên âm thô |
| `pipeline/37_build_poem_corpus.py` | `poem_vi.jsonl` → shard corpus **một dòng một VẾ** (đơn vị runtime) |

Ba file pipeline đầu đều có `--self-check`; `train_scratch.py --self-check` chạy **trọn vòng**
trên CPU (nấu spm tí hon → train 50 bước → xuất CT2 → dịch thử) trong ~1 phút. Kernel gọi đúng
cái đó làm smoke trước khi đốt giờ GPU.

Ba quyết định kỹ thuật đáng nhớ, đã trả giá để biết:

1. **Tokenize bằng spm thô, không qua `MarianTokenizer`.** `MarianTokenizer` bọc thêm
   `MosesPunctNormalizer` khi máy có `sacremoses` — Kaggle có, máy dev không. Để nó vào thì
   train và chạy tokenize khác nhau tuỳ máy. Runtime thật (`hachimi_engine._translate_safe`)
   vốn đã dùng spm thô + `</s>`, nên bỏ hẳn là hết một lớp bẫy.
2. **Cắt nguồn từ ĐẦU, không từ cuối.** Câu phải dịch nằm SAU `⟪ctx⟫`; cắt đuôi là cắt mất
   chính nó.
3. **Nạp data theo lô vào mảng numpy phẳng.** 2M dòng giữ dạng list Python tốn ~5GB mỗi tiến
   trình, mà DDP chạy 2 tiến trình trên máy Kaggle 13GB RAM. Mảng int32 phẳng còn ~700MB.

## 9b. Chạy lại từ đầu (runbook)

```bash
cd worker/hachimi
# 1. Corpus (~25 phút, đọc 5,2GB kaihe hai lượt)
.venv/bin/python pipeline/28_build_scratch_corpus.py --limit 2000000 \
    --block-extra ~/hachimi-work/clean_testset.jsonl
# 1b. Hai shard phụ rồi nối vào (~2 phút). Nối ra file MỚI, đừng đè corpus probe:
#     probe phải giữ đúng "một bậc đổi một nút", thêm nguồn data là hỏng phép so.
.venv/bin/python pipeline/35_build_prose_corpus.py \
    --block-extra ~/hachimi-work/clean_testset.jsonl \
    --block-extra ~/hachimi-work/eval_poem_locked.jsonl
.venv/bin/python pipeline/36_build_poem_booster.py    # chỉ khi lô thơ có thêm bài mới
.venv/bin/python pipeline/37_build_poem_corpus.py
python3 - <<'PY'
import hashlib, json
from pathlib import Path
S = Path.home() / "hachimi-work/scratch"
key = lambda z: hashlib.blake2b(z.encode(), digest_size=8).digest()
seen = set()
with (S / "corpus2m_v7.jsonl").open("w", encoding="utf-8") as out:
    # kaihe TRƯỚC: chỗ trùng giữ bản dịch NGƯỜI, bỏ bản Gemini
    for name in ("corpus2m.jsonl", "prose_corpus.jsonl", "poem_corpus.jsonl"):
        for line in (S / name).open(encoding="utf-8"):
            if line.strip() and (k := key(json.loads(line)["zh"])) not in seen:
                seen.add(k)
                out.write(line)
PY
# 2. SPM 24k trên chính corpus đó (~10 phút CPU)
.venv/bin/python pipeline/29_train_spm.py --compare ~/hachimi-work/hachimi-v6/source.spm
# 3. Gói phẳng lên Kaggle — nhớ -t và KHÔNG để thư mục con
kaggle datasets create -p ~/hachimi-work/kg_v7_ds -t
kaggle datasets status thnhnguyn003/hachimi-v7-probe     # đợi "ready" RỒI mới push kernel
kaggle kernels push -p ~/hachimi-work/kg_v7_kernel
# 4. Lấy kết quả
kaggle kernels output thnhnguyn003/hachimi-v7-probe-train -p ~/hachimi-work/scratch/kaggle_out --force
.venv/bin/python eval/eval_scratch_probe.py --hyp-dir ~/hachimi-work/scratch/kaggle_out \
    --ct2-baseline ~/hachimi-work/hachimi-v6/ct2-int8_float32
```

Bộ test cho `eval_register.py` phải ở dạng `zh_lines`; `clean_testset.jsonl` là `zh` một chuỗi
nhiều dòng, chuyển bằng:

```python
{"zh_lines": [l.strip() for l in row["zh"].split("\n") if l.strip()]}
```

(đã dựng sẵn ở `~/hachimi-work/scratch/register_testset.jsonl` — 55 chương → 3.749 câu.)

## 10. Đo bậc nào bằng thước nào

| bậc | thước | lệnh |
|---|---|---|
| P0 | chrF vs mốc tiny | `eval/eval_scratch_probe.py --hyp-dir <output>` |
| P1 | bịa chủ ngữ / sai giới, CÓ ngữ cảnh | `eval/eval_register.py --context 2` (đã có sẵn cờ này) |
| P1/P2 | lint + đại từ hiện đại | `eval/eval_project_metrics.py` |

`eval_register.py --context 2` là mấu chốt của P1: chấm P1 mà **không** dựng ngữ cảnh thì đúng
cái lợi thế của nó bị giấu đi, kết luận sẽ ra sai.

## 11. Cổng LaBSE — và vì sao KHÔNG lọc cả 32 triệu

Con số "11 triệu cặp" của bản bàn giao là **ước tính, chưa ai chạy**. Nó cần cổng thứ hai
(LaBSE ≥ ngưỡng) mà tới 30/08 chưa chấm một dòng nào.

Chi phí thật nếu làm đủ:

| việc | GPU |
|---|---|
| LaBSE toàn bộ ~25M cặp còn lại sau `_replay_ok` | 8-14 giờ |
| Train bản thật 57-60M | 15-30 giờ |
| **cộng** | **23-44 giờ** — vượt quota 30h/tuần |

**Quyết định: chỉ lọc ~10M cặp** (`28_build_scratch_corpus.py --limit 10000000`) → LaBSE
~4-6 giờ → còn khoảng 4-5M cặp sạch. Lý do không tiếc:

- Model 60M tham số **bão hoà** sớm hơn 11M cặp nhiều. Quá ngưỡng đó, chất lượng data ăn đứt
  số lượng — mà cổng LaBSE chính là cái nâng chất lượng.
- 4-5M cặp vẫn gấp **13 lần** lượng 350k mà HachimiMT-60 gốc dùng, và là data NGƯỜI dịch.
- Cả dây chuyền lọt một tuần quota thay vì hai.

Ngưỡng **không lấy thẳng 0,70 của bản bàn giao** — chạy `--calibrate` trước: nó in phân vị, tỉ
lệ giữ ở từng mức, 5 cặp điểm thấp nhất và 5 cặp **quanh ngưỡng** (chỗ dao thực sự cắt). Lệch
0,05 là mất hoặc giữ hàng triệu cặp.

Hai chi tiết kỹ thuật của `30_labse_filter_corpus.py`:

- **Chảy theo dòng + ghi state.** `15_score_labse.py` nạp cả file vào RAM — 9 triệu dòng là
  chết. Bản này ghi `.state.json` mỗi lô nên kernel hết giờ vẫn chạy tiếp được.
- **Hiệu chuẩn phải lấy `--stride`.** Corpus xếp theo TRUYỆN; 2000 dòng đầu chỉ là một truyện,
  chấm trên đó ra ngưỡng của riêng truyện ấy.

## 12. Hố lớn nhất phát hiện 30/08: một PHẦN BA kaihe không phải văn người

Trong lúc hiệu chuẩn ngưỡng LaBSE thì lộ ra thứ quan trọng hơn nhiều. Đo trên 102k dòng đã
qua `_replay_ok`:

| dấu hiệu | tỉ lệ |
|---|---|
| zh **tách rời từng chữ** (`叶 紫 芸 身 份 高 贵`) | 32,9% |
| vi dài ≥20 ký tự mà **không có một chữ hoa nào** | 29,0% |
| bản dịch lọt token `<UNK>` | 0,44% |
| **dính ít nhất một dấu hiệu** | **34,0%** |

Mẫu điển hình:

```
叶 紫 芸 身 份 高 贵   →   thân phận diệp tử vân cao quý
不 是 妈 咪 思 想 太 古 板   →   không phải <UNK> tư tưởng cổ hủ
```

Đây là data **đã qua tiền xử lý của một pipeline MT khác**, không phải văn người dịch. Hại
theo hai đường:

1. **Phía vi là cái model học để SINH RA.** 34% mẫu viết thường tuốt, tên riêng không hoa →
   dạy thẳng model xuất `diệp tử vân` thay vì `Diệp Tử Vân`. Đúng trục dự án đang yếu nhất.
2. **Phía zh tách rời từng chữ tokenize khác hẳn** đầu vào thật (liền mạch), vừa phí token vừa
   dạy quy luật không tồn tại lúc chạy.

`_replay_ok` không bắt được — nó xét Hán sót, ngoặc, tỉ lệ dài, số khớp, register; **không xét
hoa/thường lẫn dấu cách**. Cổng mới `is_machine_shard()` trong `28_build_scratch_corpus.py`.

**Không sửa mà loại.** Phía zh gỡ dấu cách thì dễ, nhưng phía vi **không khôi phục nổi chữ hoa
của tên riêng** — mà vi mới là phía model học để sinh.

Hệ quả dây chuyền:

- SPM 24k nấu ngày 30/08 (mục 2.2) **nấu trên corpus còn bẩn** → phải nấu lại. Chỉ mất ~1 phút.
- Lượt probe đẩy lên Kaggle 30/08 train trên corpus còn bẩn ⇒ **số của nó chỉ có giá trị kiểm
  máy móc** (môi trường, DDP, export CT2 ở quy mô thật), **KHÔNG dùng để quyết** P0/P1/P2.
- Ước tính "còn ~11M cặp" của bản bàn giao phải trừ tiếp 34%.

### Bài học phương pháp

Cổng LaBSE không tìm ra hố này — **đọc mẫu bằng mắt** mới tìm ra. `--calibrate` được thêm vào
chỉ để chọn ngưỡng, nhưng giá trị thật của nó là **bắt người ta nhìn vào data**. Giữ thói quen
đó: trước mỗi vòng train, in vài chục mẫu ra đọc.

### Ngưỡng LaBSE — chưa chốt

Đo trên corpus CÒN BẨN: ngưỡng 0,70 giữ 44,7%, nhưng các cặp **ngay tại 0,70 đều dịch đúng**
(`金霄聚灵剑符 → kim tiêu tụ linh kiếm phù`). LaBSE chấm thấp phiên âm Hán-Việt — đúng cái giọng
dự án theo đuổi — nên 0,70 là **dao cắt vào thịt**. Phân bố sẽ dịch chuyển sau khi lọc kho máy,
nên **hiệu chuẩn lại trên corpus sạch** rồi mới chốt. Ghi lại để khỏi lặp: con số 0,70 của bản
bàn giao nhiều khả năng tính trên kaihe THÔ (trước `_replay_ok`), nên chồng nó lên sau
`_replay_ok` là lọc hai lần cùng một thứ.

## 13. Quét nguồn data khác — ĐỪNG QUÉT LẠI (30/08/2026)

Dò 38 ứng viên trên HuggingFace bằng 12 truy vấn (`zh-vi`, `chinese vietnamese`,
`truyen dich`, `wuxia vietnamese`, `han viet`…), kiểm quyền tải THẬT chứ không chỉ metadata.

| bộ | quy mô | kết luận |
|---|---|---|
| `kaihe/chinese_vietnamese_bilingual_wangwen` | `parallel_sentences.jsonl` 5238,5 MB | **đã có rồi** — đúng file đang dùng. Thứ CHƯA có: `parallel_chapters.jsonl` (2,26 GB, căn theo CHƯƠNG → biên chương thật cho ctx) |
| `thevan2404/merged-zh-vi-sentences-clean` | 1.711.362 cặp | **LOẠI.** README khai nguồn: `ViBidirectionMT-Eval` (bộ EVAL — train vào là hỏng phép đo), `tran-vi-teacher` (teacher Gemini mình đã có), `WikiMatrix` + `ccalign-triplet` (bách khoa + web crawl). Mẫu thật: *"Tôi đã xấu hổ vì cha mẹ mình"* — giọng hiện đại, đúng thứ dự án cấm |
| `CjangCjengh/hanviet_dataset` | 550.218 câu | **LOẠI phần câu** (33% dính từ hiện đại: tôi/bạn/giáo sư/công ty; câu sinh máy, miền văn hiện đại). **LẤY phần tên**: xem dưới |
| `moa/Chinese-Vietnamese-literature` | 76,6 MB | đã có (`moa_zh_vi.parquet`) |
| `zehaohhhuang/Chinese-VietnameseTextAlignment` | `cn_unique` + `vi_unique` | câu ĐƠN NGỮ rời, không phải cặp — vô dụng với ta |
| `chi-vi/linh_hq_parallel_corpus`, `chi-vi/linh_truyenfull` | 3 + 66 shard | **CHẶN** (`gated=manual`, xin quyền tay). Đọc được metadata nhưng tải file trả `GatedRepoError` |
| `chi-vi/CNovels` (17,6 GB+), `Moleys/emtichu` (64,9 GB) | Trung ĐƠN NGỮ | tải được, nhưng dịch máy để lấy đích = model collapse (mục 0 + `DATA_CHUAN.md` trục 1) |
| `VLSP2023-MT/ViBidirectionMT-Eval` | 300k cặp | bộ EVAL, miền tin tức. Train vào là vừa sai giọng vừa hỏng thước |

**Món DUY NHẤT đáng lấy**: `CjangCjengh/hanviet_dataset` chứa **579.265 ánh xạ TÊN RIÊNG
Trung → Hán-Việt** (`陈厚仍 → Trần Hậu Nhưng`, `沮水 → Tự Thuỷ`). So với
`data/gold/name_booster.jsonl` hiện có **800 dòng** thì gấp ~720 lần. Dùng cho glossary /
termguard / sinh booster tên theo giọng của mình — **không** bê câu của họ vào.
⚠ Repo không có README nên **giấy phép không rõ**, kiểm trước khi dùng vào bản phát hành.

### Kết luận: nguồn thật nằm trên ĐĨA, không nằm trên HF

`docs/epub-anchor.md` đã chỉ đúng chỗ: kaihe có 745.905 cặp nhưng chỉ từ **90 bộ truyện**;
kho epub có **18.317 epub / 43,6 GB / ~2.300 giọng dịch khác nhau**. Hiện mới rút được
**5.127 cặp**.

Nút thắt ghi trong tài liệu đó — *"chỉ 94/152 truyện lấy được vì `ddxs` và `shuhaige` đang
TẮT"* — **ĐÃ HẾT**. Đo lại trên box 30/08:

```
ddxs|t   shuhaige|t
```

Cả hai đã bật. 58 truyện còn kẹt giờ tải được nguyên tác Trung.

## 14. Ngưỡng LaBSE — CHỐT 0,50 (đo trên corpus sạch 30/08)

Mẫu 2.500 cặp rải đều (`--stride 2333`) trên `corpus12m.jsonl` sau khi đã lọc kho máy.
Trung vị **0,696**; phân vị 10% = 0,502.

| ngưỡng | giữ | còn |
|---|---|---|
| 0,45 | 92,6% | 5,41M |
| **0,50** | **90,1%** | **5,26M** |
| 0,55 | 85,7% | 5,01M |
| 0,70 (bản bàn giao) | 48,6% | 2,84M |

Đọc mẫu từng dải mới ra được chỗ cắt:

- **quanh 0,55**: cả 4 cặp **dịch đúng** (`苏贝贝忍无可忍了。→ Tô Bối Bối không thể nhẫn được
  nữa.`) ⇒ cắt ở đây là cắt vào thịt.
- **quanh 0,50**: khoảng một nửa hỏng — lệch một câu, dịch thiếu vế sau, hoặc câu tối nghĩa cả
  hai phía ⇒ đây là ranh giới thật.
- **quanh 0,33-0,40**: lỗi áp đảo, nhưng VẪN còn cặp đúng (câu ngắn) ⇒ đừng cắt sâu hơn.

⇒ **0,50**, trùng phân vị 10%. Cắt đúng đuôi hỏng, giữ lại phần LaBSE chấm thấp chỉ vì câu
ngắn hoặc vì phiên âm Hán-Việt.

**Ghi rõ để khỏi hiểu nhầm vai trò cổng này:** sau `_replay_ok` + cổng kho máy, LaBSE chỉ còn
là **dao tỉa đuôi (~10%)**, không phải cổng lọc chính "45% qua" như bản bàn giao hình dung.
Con số 0,70/45% của bản đó gần như chắc chắn tính trên kaihe THÔ; chồng nó lên sau hai cổng
kia là lọc hai lần cùng một thứ, và lần thứ hai cắt nhầm.

**LaBSE có thiên kiến hệ thống chống lại gu của dự án** — nó chấm thấp phiên âm Hán-Việt
(`金霄聚灵剑符 → kim tiêu tụ linh kiếm phù`) vì không nhận ra đó là cùng một thứ. Nên với dự án
này, ngưỡng LaBSE luôn phải đặt THẤP hơn khuyến nghị chung.

### Vá kèm: cổng kho máy hạ từ ≥4 xuống ≥3 chữ Hán

`裂 云 手 → liệt vân thủ` lọt cổng vì chỉ có 3 chữ. Hạ ngưỡng bắt thêm **2,18%**, kiểm 8 mẫu
đều đúng là kho máy, không oan cặp nào. Dưới 3 chữ thì thôi — mẫu quá mỏng để chắc.

⚠ Corpus probe đã đẩy lên Kaggle *trước* lần vá này nên còn sót ~2% kho máy. Không đẩy lại vì
2% không đổi kết luận P0/P1/P2; corpus của **bản thật** thì đã sạch.

## 15. KẾT QUẢ PROBE (30/08/2026) — P0 QUA CỔNG

Ba bậc chạy tuần tự trên Kaggle T4×2, ~3 giờ, corpus sạch 1.947.675 cặp × 2 epoch, model
12,46M tham số. chrF trên 500 câu dev (10 truyện holdout):

| model | tham số | chrF |
|---|---|---|
| Hachimi v6 (production) | 57M | **70,84** |
| p1 — doc-level ctx | 12M | 62,36 |
| p0 — câu lẻ | 12M | 62,29 |
| p2 — encoder sâu (param-matched) | 12M | 62,02 |
| `chi-vi/hirashiba-mt-tiny-zh-vi` | 15M | 50,12 |

**P0 qua cổng dứt khoát.** Model 12M dựng từ số 0 trên 1,95M cặp người dịch, 2 epoch:
hơn mốc ngoài cùng cỡ **+12,2 chrF**, kém production 57M **8,5 chrF**. Với 4,7 lần tham số và
3 lần data, bản thật thừa sức bù khoảng đó. **Đáng bỏ 15-30 giờ GPU.**

Kiểm rò cẩn thận trước khi tin khoảng cách: v6 có `kaihe_anchor.jsonl` (745.905 dòng) trong
pack, nên phải hỏi nó đã thấy dev chưa — **1/500 câu** (0,2%). v6 không học thuộc bài; khoảng
cách là thật.

Bản dịch đọc được thật, tên riêng Hán-Việt đúng:
`南宫正雄 → Nam Cung Chính Hùng`, `黄礼严 → Hoàng Lễ Nghiêm`.

### P1 và P2: chrF KHÔNG kết luận được

p1 hơn p0 **+0,07** — nhiễu. p2 kém p0 **−0,34**. Nhưng chrF gần như **mù** với thứ ngữ cảnh
sinh ra để chữa (bịa chủ ngữ, sai giới), nên đây chưa phải phán quyết. Phải chấm bằng
`eval/eval_register.py --context 2`. Kết quả ghi ở mục 16.

## 16. Cấu trúc thật của kaihe — 121 truyện, không phải 332

Truy ra khi thấy manifest ghi `novels_train: 322` mà corpus chỉ có **117 tên truyện**.

- kaihe có **332 dòng jsonl nhưng chỉ 121 TÊN TRUYỆN khác nhau** — mỗi truyện 2-3 lần.
- Ba bản của một truyện là **CÙNG MỘT BẢN DỊCH, khác cách tiền xử lý**:

```
zh   : 嗖                zh   : 还差一点点，还差一点点……
bản1 : Vèo               bản1 : Còn kém một chút xíu, còn kém một chút xíu
bản2 : vèo               bản3 : Còn kém một chút xíu , | còn kém một chút xíu . . .
```

⇒ Cổng `is_machine_shard` giữ đúng bản 1, loại bản 2/3. **Không mất giọng dịch nào** — điều
từng đáng lo khi thấy `dup: 1.421.251`.

⇒ Kiểu bẩn thứ ba (dấu `|` ngăn vế, cách trước dấu câu) đo lại trên corpus sạch: `|` còn
**0,00%**, cách-trước-dấu-câu còn **0,12%** — cổng cũ đã quét sạch, khỏi dựng thêm cổng.

**Hệ quả cho chiến lược data**: kaihe cho tối đa **117 giọng dịch**, không phải 332. Khớp với
`docs/epub-anchor.md` ("745.905 cặp nhưng chỉ từ 90 bộ truyện"). Khối lượng thì dư (5,77M cặp),
**đa dạng giọng mới là trần**. Đó là lý do kho epub (~2.300 dịch giả) đáng cày, dù nó chỉ thêm
vài chục nghìn cặp.

## 17. Hai điểm phải sửa TRƯỚC khi bật `hachimi_context_lines > 0`

Lộ ra khi `eval_register --context 2` nổ:
`RuntimeError: No position encodings are defined for positions >= 512, but got position 524`.

Production **không dính** lỗi này — `hachimi_engine._with_context` đã có chốt: ghép xong mà
vượt trần thì bỏ ngữ cảnh, trả về câu trần. Nhưng chốt đó có hai chỗ chưa ổn:

1. **Trần đang mượn `hachimi_max_len` (=180).** Đó là tham số của ĐỘ DÀI SINH RA, bị dùng nhầm
   làm trần ĐỘ DÀI NẠP VÀO. 180 token quá chặt: ghép ctx-2 thường vượt ngay, nên ngữ cảnh sẽ bị
   bỏ ở phần lớn câu dài — đúng những câu cần ngữ cảnh nhất. Phải tách thành setting riêng
   (`hachimi_context_max_src`, đặt ~400: dưới `max_position` 512 và chừa chỗ cho `</s>`).
2. **Đường ctx KHÔNG gọi `_split_source`.** `_translate_context` nạp thẳng `lines[i]`; nếu một
   dòng nguồn tự nó đã dài hơn `max_position` thì vẫn nổ. Đường không-ctx thì có chẻ.
   Hiếm, nhưng là lỗi làm chết cả chương chứ không phải dịch xấu một câu.

Chưa sửa vì `hachimi_context_lines` vẫn đang là 0 (chưa có model doc-level trên production).
Sửa cùng lúc với lần deploy model doc-level đầu tiên — **đừng bật cờ trước khi sửa hai chỗ này**.

## 18. BUG LỚN NHẤT: decoder khởi động lệch giữa train và CT2

Suýt mất 30 giờ GPU vì lỗi này. Triệu chứng ban đầu trông như model kém: **61% câu output mất
chữ hoa đầu, có câu rụng nguyên từ đầu tiên**, dù phần còn lại dịch đúng.

```
HF  : Thanh niên hít sâu một hơi nói      CT2 : thanh niên hít sâu một hơi
HF  : Vậy tốt, có bản lĩnh ngươi…         CT2 : tốt, có bản lĩnh ngươi…
```

### Nguyên nhân

- HF train với `decoder_input_ids[0] = <pad>` ⇒ decoder khởi động từ **embedding của `<pad>`**.
- CTranslate2 khởi động decoder từ **vector 0**. Chú thích ngay trong
  `ctranslate2/converters/transformers.py`, lớp `MarianMTLoader`:
  *"The decoder start token can be any token because the decoder always starts from a zero
  embedding."*
- Hàng `<pad>` **không bao giờ nhận gradient** (`padding_idx`) nên nó nằm nguyên ở giá trị
  **khởi tạo ngẫu nhiên** — đo được norm 0,286 (p0) và 0,481 (v6).

⇒ Train khởi động từ một vector ngẫu nhiên, chạy thật khởi động từ 0. **Lệch ngay bước decode
đầu tiên**, và bước đầu tiên quyết định chữ hoa + từ mở đầu.

### Cách chứng minh (dùng lại nếu nghi lỗi tương tự)

Ép hàng `<pad>` về 0 rồi chạy **HF** — nếu HF hỏng y hệt CT2 thì đúng thủ phạm:

| | trùng khớp với CT2 |
|---|---|
| HF nguyên bản | 8/25 |
| HF sau khi ép `<pad>` = 0 | **16/25** |

Và `Thanh niên…` → `thanh niên…` đúng như CT2. Xong, không phải đoán nữa.

### Vá

`train_scratch._zero_pad_embedding()` — ép hàng về 0 lúc khởi tạo (không gradient nên nó nằm
yên), ép lại lần nữa trước khi lưu, và `--self-check` khẳng định `|w[PAD]|max == 0` sau train.

### Production KHÔNG dính

Đối chiếu v6 HF vs CT2 trên 40 câu: chỉ khác vài từ giữa câu (nhiễu lượng tử int8), chữ hoa đầu
câu đúng cả. HachimiMT-60 chịu được vì nó train rất nhiều bước nên không bám vào vector khởi
động cụ thể; model 12M train 2 epoch thì bám chặt.

### Hệ quả cho kết quả mục 15

chrF 62,29 của p0 là **ĐO THIẾU** — 61% câu bị hỏng token đầu. Khoảng cách thật với production
(70,84) hẹp hơn 8,5 điểm. Chưa đo lại vì phải train lại mới biết; cứ coi 62,3 là **sàn**.

### Bài học

Thước dự án (`eval_register`) ra **`invented: 0` cho MỌI model, kể cả v6** — tức thước không
chạy chứ không phải model hoàn hảo (`_LEAD_VI` đòi đại từ VIẾT HOA đầu output, mà output đang
viết thường). Nếu tin số 0 đó thì vừa bỏ sót bug vừa kết luận sai về P1.
**Số đẹp bất thường ⇒ nghi thước trước, nghi model sau.** Luôn chạy một model ĐỐI CHỨNG đã biết
tính nết qua cùng cái thước.

## 19. MỎ DATA MỚI: 3.347 truyện ghép được nguyên tác Trung ↔ bản dịch người

Trần 117 giọng dịch (mục 16) **đã phá được**, và không phải bằng crawl.

### Nguồn

| bộ | nội dung | dùng thế nào |
|---|---|---|
| `chi-vi/CNovels` (120 GB, 5 zip) | **68.125 truyện Trung** thô, crawl 4/2024 từ 12z.cn, zxcs, 84sk, jjjjxsw, qisuwang | vế TRUNG |
| `novel/output_epubs.zip` (42,8 GB, tại chỗ) | **18.317 epub** bản dịch tay | vế VIỆT |
| `Moleys/emtichu` (`detail.zip` 60 MB) | **30.447 truyện metruyencv**, có `author.local_name` = tên tác giả TRUNG | vế VIỆT (thêm) |

### Cách ghép — dùng lại `han_viet()` của chính dự án

Tên truyện dịch sang tiếng Việt gần như luôn là **phiên âm Hán-Việt trọn cụm** (đúng gu đã chốt).
Nên chỉ cần `novelworker.translator.hanviet.han_viet()` là ghép được, không cần model:

```
妖神记 → Yêu Thần Ký        暗黑茄子 → Ám Hắc Gia Tử   (khớp đúng tên trong emtichu)
```

Kết quả ghép **khớp CHÍNH XÁC** sau chuẩn hoá (chưa dùng fuzzy):

| | truyện |
|---|---|
| có bản dịch trong **epub trên đĩa** | **2.628** |
| có bản dịch trên emtichu | 1.259 |
| có cả hai | 540 |
| **tổng** | **3.347** |

So với hiện trạng `docs/epub-anchor.md`: 220 ghép / 94 tải được. **Gấp ~15 lần.**

### Tải chọn lọc, không tải 120 GB

Zip trên HF đọc được **mục lục qua HTTP range** (`scratch/remote_zip_list.py`, ~40 dòng, không
thêm dependency — zip >4GB nên phải đọc ZIP64). Từ mục lục có offset + kích thước từng file
⇒ tải đúng những truyện đã ghép:

**10,67 GB thay vì 120 GB.**

### Bẫy đã dính

Mỗi kho đặt tên file một kiểu. Lượt đầu chỉ viết regex cho `《tên》（…）作者：tác giả.txt` nên
**bỏ sót 76.700 truyện** của 84sk/jjjjxsw/qisuwang (chúng dùng `tên.txt` trơn) — ghép ra 1.968
thay vì 3.347. Luôn in vài tên file của TỪNG kho trước khi viết parser.

### Việc tiếp

1. Tải 10,67 GB truyện Trung đã ghép (range request theo từng file trong zip).
2. Ghép chương + căn câu bằng pipeline sẵn có (`26_pair_epub_chapters` → `24_align_epub_anchor`).
3. Cổng: `is_machine_shard` → `_replay_ok` → LaBSE 0,50.

Ghép mờ (fuzzy) và ghép theo **tên tác giả Trung** (`emtichu.author.local_name` ↔ `作者：`) chưa
làm — còn dư địa.

## 20. Đối chiếu tài liệu nghiên cứu — kiến trúc CHỐT LẠI, và probe bị bác

Tra ngày 30/08 vì đề xuất ở mục 3 là suy luận, chưa đối chiếu nguồn.

### 20.1 Kasai et al., ICLR 2021 — *Deep Encoder, Shallow Decoder* (arXiv 2006.10369)

Đo trên WMT17 **EN↔ZH** (đúng cặp có tiếng Trung), Table 2:

| | EN→ZH | ZH→EN | tăng tốc |
|---|---|---|---|
| AR 6-6 (chuẩn) | 35,06 | 24,19 | 1,0× |
| **AR 12-1** | 34,71 | **24,22** | **2,7-2,9×** |

- Decoder **1 layer** chỉ mất ~0,35 BLEU; chiều ZH→EN còn nhỉnh hơn.
- Với ngân sách 12 layer, chất lượng **đi ngang từ 4 encoder trở lên** (Figure 2 giữa).
- Họ dùng **ffn 2048 CẢ HAI phía** (transformer-base chuẩn). HachimiMT-60 để 3072 là to hơn chuẩn.
- Một layer decoder **nặng hơn 30%** một layer encoder vì có cross-attention.

⇒ Preset `v7` sửa từ 12 enc / **2** dec (ffn 2048/3072) thành **12 enc / 1 dec, ffn 2048/2048**:

| | HachimiMT-60 | v7 |
|---|---|---|
| tham số | 56,3M | **54,2M** |
| phần decoder (chi phí ×6 vì beam) | 10,5M | **4,2M** |

Nhỏ hơn model hiện tại, encoder sâu hơn, **decode rẻ hơn một nửa**.

### 20.2 Popel & Bojar, *Training Tips for the Transformer Model* (PBML 110)

- 16M cặp cần **~10 epoch / 27k bước** mới hội tụ; 58M cặp thì **18 epoch VẪN CHƯA đủ**.
- Batch nhỏ hại nặng: BASE batch 2000 → ~19,7 BLEU, batch 4500 → ~22,3. **Chênh 2,6 BLEU
  chỉ vì batch.**
- Hạ `max_length` xuống 70 làm tụt BLEU rõ — để 384 như hiện tại là đúng.
- Kasai train **300.000 bước**, lấy **trung bình 5 checkpoint tốt nhất**.

### 20.3 Hệ quả: KHÔNG được dùng kết quả probe để chốt ngữ cảnh

Probe chạy **2 epoch ≈ 10.000 bước** — kém công thức chuẩn **30 lần**. Ở mức đó cả ba bậc
đều chưa hội tụ, nên:

- Kết luận "ngữ cảnh làm tệ đi 1,32 chrF" (mục ~19) **không đáng tin**. Bằng chứng nhiễu: cùng
  thiết lập, lượt 1 đo `P1−P0 = +0,07`, lượt 2 đo `−1,32` — dao động ngang hiệu ứng.
- Lỗi vị trí 0 (28-67%) cũng là **triệu chứng thiếu train**, không phải kiến trúc: v6 (57M,
  train rất dài) không dính, dù hàng `<pad>` của nó cũng khác 0 y như bản chưa vá của ta.

⇒ **Đừng chạy thêm probe ngắn.** Dồn quota vào MỘT bản train dài với kiến trúc đã có bằng
chứng, rồi bật/tắt ngữ cảnh so ở mức hội tụ.

### 20.4 Ba thứ đang bỏ sót, đều gần như miễn phí

1. **Trung bình 5 checkpoint tốt nhất** — cả hai nguồn đều làm, ta chưa.
2. **Batch tính theo TOKEN, không theo CÂU.** Đang đặt `--per-device-batch 96` (số câu) nên số
   token mỗi bước trôi nổi theo độ dài — đúng thứ Popel đo là ảnh hưởng 2,6 BLEU.
3. `max_length` giữ 384, đừng hạ.

### 20.5 Phản biện: EN↔ZH ≠ ZH→VI — và cách xử

Bằng chứng ở 20.1 đo trên EN↔ZH, **không phải** ZH→VI. Đã tra riêng cho cặp của mình:

- Tài liệu zh-vi **không có bài nào** thử phân bổ layer sâu-cạn. Toàn bộ là bối cảnh ít data
  (VLSP 2022: 300k cặp song ngữ, model 2 layer, finetune mBART-25) — khác chế độ của ta (5,77M
  cặp, train từ số 0).
- Mốc zh→vi có được: VBD-MT (arXiv 2308.07601) đạt **38,0 BLEU** baseline;
  **+0,8** nhờ back-translation; **+0,1** nhờ trung bình 5 checkpoint. Đánh giá bởi người bản
  ngữ chỉ ra lỗi tồn đọng hàng đầu là **"dịch sai tên người"** — trùng đúng điểm yếu Hán-Việt
  của dự án.

Vì sao vẫn tin phần encoder chuyển giao được: Kasai làm thí nghiệm **đảo trật tự từ** (Table 4
trái) — ép trật tự tiếng Anh khớp tiếng Đức rồi train lại. Đảo trật tự chính là thứ KHÁC NHAU
giữa các cặp ngôn ngữ, và nó ảnh hưởng **y hệt** lên 6-6 và 12-1 (đều +4,3 BLEU):
*"AR gains the same improvement regardless of the layer configuration"*. Với model tự hồi quy,
độ sâu decoder không phải để xử lý đảo trật tự. Thêm nữa zh và vi **cùng đơn lập, cùng SVO** —
ít đảo hơn en↔de, tức lệch về phía an toàn.

**Nhưng chốt lại theo CÁN CÂN RỦI RO, không theo bằng chứng thuần:**

| thay đổi | được gì | rủi ro nếu không chuyển giao |
|---|---|---|
| encoder 8 → 12 | chất lượng | ~0 — encoder chạy 1 lần/câu, không nhân theo beam |
| decoder 2 → 1 | **tốc độ** | mất chất lượng phía sinh chữ, chưa ai kiểm cho zh→vi |

Dự án đang thiếu **chất lượng**, không thiếu tốc độ (production 2 layer vẫn chạy được). Cược
0,35 BLEU chưa kiểm chứng để lấy tốc độ chưa cần là sai hướng ưu tiên.

⇒ **`v7` = 12 enc / 2 dec, ffn 2048 cả hai** (58,4M; encoder 37,7M, decoder 8,4M — vẫn rẻ hơn
decoder 10,5M của HachimiMT-60 nhờ ffn 2048).
⇒ **`v7-fast` = 12 enc / 1 dec** giữ làm thí nghiệm TỐC ĐỘ chạy sau, khi chất lượng đã có.

## 21. Cổng chất lượng theo LÔ — `pipeline/quality_gate.py` (01/09)

Thay cho việc đi đoán "người dịch hay máy dịch". Lý do đổi: thước mật độ hư từ (`func_per_1k`)
**ngược dấu** khi đem chấm các bộ đã biết nguồn gốc — Gemini (máy) 16,1-18,1 còn kaihe (người)
14,4-15,6. Nó đo "văn có tự nhiên như tiếng Việt không", đúng thứ LLM tối ưu.

Ba thước CẤU TRÚC xếp hạng nhất quán, đo đúng trục thật là **mức bám sát chữ Hán**:

| bộ | convert/1k | POSS/10k | phiên âm % | (hư từ/1k) |
|---|---|---|---|---|
| epub trung vị — convert | 4,25 | 0,7 | 47,5 | 7,3 |
| epub ≥14 — "33 truyện dịch tay" | 2,79 | 0,5 | 43,2 | 15,2 |
| kaihe — NGƯỜI | 1,86 | 0,5 | 38,5 | 14,4 |
| Gemini prose — MÁY | 1,11 | 0,1 | 29,2 | 16,1 |
| Gemini teacher — MÁY | 1,06 | 0,1 | 30,9 | 18,1 |

⇒ **33 truyện epub kia là convert ĐÃ GỌT, không phải dịch tay**: hư từ nói 15,2 (hơn cả kaihe)
nhưng cấu trúc tố cáo — cụm convert gấp rưỡi và phiên âm thô cao hơn kaihe. Hướng epub×CNovels
cạn thật, giờ xác nhận bằng cấu trúc chứ không chỉ hư từ. **Đừng đốt GPU chạy bước 34 lên đó.**

Cổng gác HAI ĐẦU (`MAX_CONVERT_PER_1K=2.4`, `MAX_TRANSLIT_PCT=41`, `MIN_TRANSLIT_PCT=27`):
quá bám chữ = convert, loại; quá thoát = mất register Hán-Việt, chỉ cảnh báo.

⚠ Gác theo **LÔ**, không theo câu — cả ba là mật độ, một câu 20 từ thì vô nghĩa.
⚠ Sàn `MIN_TRANSLIT_PCT` hiệu chuẩn theo VĂN XUÔI. Thơ nằm dưới sàn một cách chính đáng
(`poem_corpus` 19,8%) vì hạ phiên âm thô chính là mục đích của bộ thơ mới — chấm thơ thì
truyền `min_translit=15`.

Chấm ba shard hiện có: prose **ok** · kaihe **ok** · thơ **ok** (sàn 15).

    python pipeline/quality_gate.py ~/hachimi-work/scratch/prose_corpus.jsonl
