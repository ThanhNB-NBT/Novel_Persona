# Mỏ neo người dịch từ kho epub — 29/08/2026

Nguồn thứ hai sau `kaihe`, dựng từ `novel/output_epubs.zip` (18.317 epub, 43,6GB, không commit).

## Vì sao đáng làm — và làm SAI thì thành vô ích

`kaihe` đã có **745.905 cặp** nhưng chỉ từ **90 bộ truyện**. Theo `DATA_CHUAN.md` trục 2
(LIMA: 1.000 mẫu chọn tay thắng 52.000), thứ còn thiếu là **đa dạng giọng dịch**, không phải
số dòng. Kho epub có ~2.300 bản dịch tay của ~2.300 dịch giả khác nhau — đó mới là giá trị.

> **Vì vậy: lấy ÍT chương từ NHIỀU truyện.** Cày 220 truyện × 300 chương chỉ nhân đôi số dòng
> (764k cặp ≈ 1,0× kaihe) mà không thêm bao nhiêu kiểu câu, lại tốn 66.000 lượt crawl.
> 220 truyện × 10 chương cho ~25.500 cặp từ 220 giọng dịch — rẻ hơn 30 lần, đúng trục hơn.

## Luồng

1. **Sàng convert khỏi dịch tay** — `eval/scan_epub_corpus.py`. Thước là **mật độ hư từ**
   (bởi vì, cho nên, của, rằng…): convert 4–6/1k từ, dịch tay 17–22/1k, mốc kaihe 18,5.
   `lint_score` và đếm cụm convert đều MÙ ở đây vì convert hỏng ở cấu trúc câu.
   Toàn kho: 13,2% đạt ngưỡng ≥14/1k.
2. **Ghép với DB** theo tên truyện đã chuẩn hoá → 170 khớp chặt + 50 khớp mờ = **220 truyện**
   đã biết nguồn crawl. Loại truyện dịch từ Anh/Nhật và sách Việt gốc.
2b. **Tải nguyên tác Trung** — `pipeline/25_fetch_zh_anchor.py`, chạy trên box.
   Mỗi truyện mới chỉ có 1 chương mẫu trong DB (`sample_chapters=1`) nên phải tải thêm.
   Script gọi THẲNG adapter, ghi ra file, **cố ý không đi qua `queue_sample_chapters`**: đường
   đó sẽ kéo theo dịch cả nghìn chương (~13 giờ CPU box) + gọi LLM trích tên từng chương,
   trong khi ta chỉ cần vế tiếng Trung.
   ⚠ **Chỉ 94/152 truyện lấy được**: 39 truyện thuộc `ddxs` và 19 thuộc `shuhaige` — hai nguồn
   này đang TẮT trong bảng `sources`. Muốn lấy nốt thì phải bật lại nguồn (đụng production)
   hoặc tìm truyện đó ở nguồn khác bằng tên Trung.
2c. **Ghép chương** — `pipeline/26_pair_epub_chapters.py`, chạy ở máy dev (nơi có file zip).
3. **Lọc cặp chương** — dịch máy chương zh rồi chấm chrF với bản epub; giữ ≥50.
   (epub đánh số chương lệch DB vì có quyển/phiên ngoại → cùng số chưa chắc cùng nội dung)
   Đo thật: 55/82 cặp đạt; cặp <40 là lệch chương, align vào sẽ ra data bẩn.
4. **Căn câu** — `pipeline/24_align_epub_anchor.py`. Hachimi dịch từng câu Trung làm cầu,
   rồi quy hoạch động căn bản máy với bản người (1-1, 1-2, 2-1).
5. **Cổng** — nhất quán xưng hô cấp chương (`pipeline/19`) + `_replay_ok` cấp dòng.
6. **Chấm lại bằng LaBSE** (`pipeline/15_score_labse.py`) — DATA_CHUAN.md nói rõ đây **không
   phải việc tuỳ chọn**. Chạy ở máy nhà, đừng đụng box.

## Luồng lệnh

```bash
# trên box — tải nguyên tác Trung (rải chậm, không đụng hàng đợi production)
python 25_fetch_zh_anchor.py anchor_ids_live.json zh_raw.jsonl --chapters 10 --delay 3

# trên máy dev — ghép với epub, căn câu, cổng, LaBSE
.venv/bin/python pipeline/26_pair_epub_chapters.py zh_raw.jsonl match_ids.json <zip> paired.jsonl
ANCHOR_DATA=<dir> ANCHOR_INPUT=paired.jsonl HACHIMI_DIR=<model> \
  .venv/bin/python pipeline/24_align_epub_anchor.py 9999
.venv/bin/python pipeline/15_score_labse.py epub_anchor.jsonl epub_anchor_labse.jsonl --batch 32
```

## Tỉ lệ rơi qua từng cửa (đo trên mẻ đầu)

| cửa | còn lại |
|---|---|
| chương Trung tải về | 100% |
| ghép được với epub (bước 26) | **45%** — phần lớn rơi vì chương đó là bản convert dù cả sách đạt chuẩn |
| cặp thật sự cùng nội dung (chrF≥50) | 76% số đã ghép |
| câu căn được | 41% số câu Trung |
| qua cổng chương + dòng | 51% số cặp đã căn |

Nhân lại: **~100 chương Trung tải về cho ra ~600 cặp câu sạch.**

## Số đo thật (55 chương / 54 truyện)

| bước | còn lại |
|---|---|
| câu Trung trong 55 chương | 5.174 |
| căn được | 1.225 cặp (~22/chương) |
| qua cổng chương + dòng | **637 cặp** (52% số đã căn, ~11,6/chương) |

## Bẫy đã dính khi dựng aligner

**Hai câu tiếng Việt bất kỳ đã tương đồng ~0,30** (cùng bộ hư từ). Bản đầu đặt ngưỡng 0,34 và
phạt bỏ câu -0,25 → thuật toán ghép bừa rồi trôi hàng, 100% cặp sai mà điểm vẫn "đẹp". Phải:
trừ nền 0,30, ngưỡng thô 0,50, phạt bỏ câu rẻ (0,04) để thà mất data còn hơn data bẩn, và
đo tương đồng bằng Jaccard 3-gram ký tự thay vì SequenceMatcher.

## Chấm LaBSE — data mới SẠCH HƠN kaihe

Hiệu chuẩn bằng chính kaihe (lấy 621 cặp ngẫu nhiên, chấm cùng cách):

| | p10 | p25 | trung vị | p75 | p90 |
|---|---|---|---|---|---|
| **epub anchor (mới)** | 0,642 | 0,715 | **0,781** | 0,831 | 0,875 |
| kaihe (đang dùng train) | 0,512 | 0,668 | 0,744 | 0,792 | 0,837 |

Ở mọi phân vị data mới đều căn khớp tốt hơn. Ngưỡng ≥0,80: epub giữ 40%, kaihe chỉ 22%.
Lý do: kaihe căn theo CHƯƠNG bằng thuật toán tự chế chưa qua bộ lọc nào (DATA_CHUAN.md mục 1),
còn luồng này lọc cặp chương (chrF≥50) trước rồi mới căn câu, và phạt bỏ câu rất rẻ.

Mẻ đầu: `data/epub_anchor.jsonl` — **621 cặp / 50 truyện** (không commit, theo quy ước data).

## Chạy ở đâu

Box lo mạng (crawl), **máy dev lo tính toán** — hai máy chung một IP công cộng nên chạy crawl
song song KHÔNG nhanh hơn, chỉ tăng rủi ro bị chặn.

Môi trường tính toán trên máy dev: `worker/hachimi/.venv` (Python 3.11 cài bằng `uv` vào thư
mục nhà, không cần sudo — Python hệ thống là 3.14 nên `ctranslate2`/`torch` chưa có wheel).
Align 55 chương: máy dev 94s, box ~320s (nhanh gấp 3,4×).

```bash
ANCHOR_DATA=<thư mục data> HACHIMI_DIR=<model> .venv/bin/python pipeline/24_align_epub_anchor.py 55
.venv/bin/python pipeline/15_score_labse.py vao.jsonl ra.jsonl --batch 32
```


## Mẻ đầy đủ (29/08, sau khi crawl 152 truyện)

| bước | còn lại |
|---|---|
| chương Trung tải về (152 truyện × 10 chương) | **1.474** |
| ghép được với epub | 912 (bỏ 487 vì CHƯƠNG đó là convert, 53 lệch tỉ lệ, 22 epub thiếu chương) |
| cặp thật sự cùng nội dung (chrF≥50) | 468 (bỏ **444** cặp lệch — gần một nửa!) |
| câu căn được | 10.572 cặp (26% số câu Trung) |
| qua cổng chương + dòng | **5.127 cặp / 77 truyện** |
| sau LaBSE ≥0,70 | **4.078 cặp** |

LaBSE: p25 0,715 · trung vị **0,770** · p75 0,822 — vẫn sạch hơn kaihe (0,744) dù mẻ lớn hơn.

Lưu ý: **444/912 cặp chương bị loại vì lệch nội dung**. epub đánh số chương khác DB (quyển,
phiên ngoại, chương gộp) nên cửa chrF≥50 là bắt buộc, không phải tuỳ chọn.
