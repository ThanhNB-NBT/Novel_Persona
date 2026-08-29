# So model dịch chuyên GỐC trên box nhà — 29/08/2026

> Kết luận: **cỡ model không quyết định, MIỀN DỮ LIỆU train mới quyết định.** Con 3B đa ngữ
> thua con 56M chuyên truyện tới 33 điểm chrF, và chậm hơn 71 lần.

## Cách đo

- Chạy thẳng trên box production (i5-6200U, 2 nhân), CT2 int8, đúng cách gọi của production
  (sentencepiece + `</s>` + beam 6), Docker nên không cần cài gì vào máy.
- Bộ test: **400 câu zh–vi do NGƯỜI dịch** trích từ `kaihe/aligned_chapters.jsonl`.
- Chấm chrF/BLEU bằng `sacrebleu`. Harness: `bench_mt_models.py` (bản trên box: `~/bench/mt_bench.py`).

## Kết quả — model GỐC, chưa finetune

| model | tham số | chrF | BLEU | tốc độ |
|---|---|---|---|---|
| **ngocdang83/HachimiMT-60-zh-vi** | 56M | **60,63** | **41,97** | 284 chữ Trung/s |
| Moleys/hirashiba-mt-medium | 57M | 59,36 | 40,67 | 123 chữ/s |
| facebook/m2m100_418M | 418M | 30,43 | 9,72 | 23 chữ/s |
| google/madlad400-3b-mt | 3B | 27,12 | 8,12 | **4 chữ/s** |
| facebook/nllb-200-distilled-600M | 600M | 26,08 | 5,86 | 21 chữ/s |
| Helsinki-NLP/opus-mt-zh-vi | 77M | 19,90 | 3,41 | 149 chữ/s |

Cùng một câu nguồn (`云落枫转过头，背对着萧辰…`):

- Hachimi-60 gốc: *"Vân Lạc Phong quay đầu, đưa lưng về phía Tiêu Thần, ánh mắt đen nhánh…"* ✅
- hirashiba-medium: *"Vân Lạc Phong quay đầu lại, quay lưng về phía Tiêu Thần…"* ✅
- m2m100: *"**Mây mờ** quay đầu…"* (dịch nghĩa tên người)
- madlad 3B: *"**Mặt trời mọc, mặt trời lặn**, ánh trăng chiếu vào mặt đất…"* (bịa sạch)
- nllb: *"Khi **đám mây lấp lánh trên đầu nó**…"*
- opus-mt-zh-vi: *"Những đám mây đen quay đi, nhìn thẳng vào **cá Shaw**…"*

Model đa ngữ tổng quát **không biết dịch tiểu thuyết mạng Trung→Việt**: chúng dịch nghĩa tên
riêng, mất register, bịa nội dung. Không có bậc trung gian nào đáng theo giữa 57M và 3B.

## Ràng buộc phần cứng đo được

- madlad-3b (model.bin 2,95GB): chạm trần cgroup 4,39GiB, box swap 2,5GB → **vượt trần RAM box**,
  không dùng được kể cả nếu chất lượng có tốt.
- Model ≤600M chạy an toàn cùng production (Supabase 11 container + worker).

## Hệ quả cho hướng finetune

Hai ứng viên đáng quan tâm đều ~56-57M, tức **cùng cỡ Hachimi hiện tại** — không có đường
"tăng cỡ model" nào khả thi trên box này. Muốn ngon hơn thì phải **thêm data đúng loại**,
mà data đúng loại là mỏ neo người dịch (xem `BENCH_GEMMA_2026-08-29.md` và kho epub).

`Moleys/hirashiba-mt-medium` đáng chú ý: gốc đã 59,36 chrF (chỉ kém Hachimi gốc 1,3 điểm)
và là dòng model chuyên truyện của chi-vi — đáng thử làm điểm xuất phát finetune thứ hai.

## Bộ test sạch cho vòng so với v5 production

**Không được** dùng kaihe để chấm v5: v5 đã train trên chính nó → điểm ảo. Bộ sạch dựng từ
kho epub: **82 cặp chương** = nguyên tác Trung (R2) × bản dịch tay (epub `[Dịch]` đạt ≥14 hư
từ/1k ở cấp chương), chưa model nào trong dự án từng thấy. Script: `bench_build_clean_testset`
trong scratchpad phiên 29/8; dữ liệu `~/bench/clean_testset.jsonl` trên box.

## Vòng cuối: v5 production vs model gốc, trên bộ test SẠCH

40 chương sạch (nguyên tác Trung × bản dịch tay từ kho epub), chấm hai kiểu:

**Kiểu 1 — chrF/BLEU so bản dịch tay:**

| model | chrF | BLEU | s/chương |
|---|---|---|---|
| hachimi60-goc | **56,34** | 26,19 | 11,7 |
| hachimi-v5-PRODUCTION | 55,54 | 25,16 | 11,8 |
| hirashiba-medium | 55,29 | 24,94 | 26,8 |

Ba model nằm trong 1 điểm chrF của nhau — **thước này không phân biệt được chúng**, vì nó
chấm độ trùng với gu của MỘT dịch giả cụ thể, không chấm gu mà dự án đã chốt.

**Kiểu 2 — thước của chính dự án** (20 chương, 2.149 câu):

| model | bịa chủ ngữ /100 câu | đại từ hiện đại /chương | Hán sót | lint /chương |
|---|---|---|---|---|
| **hachimi-v5-PRODUCTION** | 0,00 | **0,95** | 0,00 | **3,15** |
| hachimi60-goc | 0,00 | 1,20 | 0,00 | 4,15 |

**v5 thắng ở đúng thứ nó được finetune để sửa** (đại từ -21%, lint -24%). Điểm chrF thấp hơn
là cái giá của việc bám gu riêng, không phải dấu hiệu finetune hỏng.

Bài học đo đạc: **đừng dùng chrF với một bản dịch tay bất kỳ để đánh giá model của dự án** —
nó thưởng model trung tính và phạt model có gu. Dùng nó để so các model GỐC với nhau thì được
(chúng đều trung tính), so với v5 thì không.

## Kết luận cho hướng nâng cấp

Giữ **Hachimi (Marian 57M)** làm engine. Không có model nào vừa chạy nổi trên box vừa tốt hơn:
bậc trên đều ≥7B (Hunyuan-MT-7B, Seed-X-7B, chi-vi/WN-zh-vi-sim 14,7B) và vượt trần RAM;
Hunyuan-MT-7B đo thử trên máy dev 8 nhân chỉ được 2,7 chữ Trung/s (Hachimi: 284) — 24 phút/chương.
Đường nâng cấp duy nhất còn lại là **thêm data đúng loại**: mỏ neo dịch người từ kho epub.
