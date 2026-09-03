# Văn xuôi + thơ — sinh xong, soát xong, đã gộp (01/09/2026)

Nối tiếp mục A3 của [`ban-giao-2026-08-30-chieu.md`](ban-giao-2026-08-30-chieu.md).
Kết quả vào bảng data của [`train-scratch-v7.md`](train-scratch-v7.md) mục 6.

## Kết quả

| | |
|---|---|
| Sinh | 100.004 câu / 401 lô / 1.667 truyện epub (Gemini qua Antigravity) |
| Qua cổng | **76.771 cặp** (76,8% — kaihe là 79%, ngang nhau) |
| File | `scratch/prose_corpus.jsonl` + `.manifest.json` |
| Đã nối | `scratch/corpus2m_prose.jsonl` = 1.998.834 dòng (kaihe 1.922.132 + prose 76.702, trùng 69) |
| Rò dev | **0** |

## BẪY LỚN NHẤT: `validate_prose.py` xanh mà data hỏng 17%

Bộ kiểm cũ chỉ so **số dòng** và **số thứ tự `n`** — không so NGHĨA. Nó báo "401 valid" suốt
ba lượt trong khi **114 lô (17.340 câu) đã lệch nội dung**: bản dịch của câu `n` bị gán sang
`n-1`, trôi dồn tới hết file.

Nguyên nhân: lượt sửa văn phong bảo LLM ghi đè `out_XXX.jsonl`, nó gặp dòng `zh` chứa nhiều
mệnh đề / dấu xuống dòng thì **tách thành 2 dòng dịch** (hoặc gộp 2 thành 1) → lệch từ đó
tới cuối file. Cặp `zh` ↔ `vi` vẫn đủ 250 dòng, `n` vẫn đúng thứ tự, nên mọi phép đếm đều xanh.

**Cách bắt** (đã dựng, dùng lại được cho mọi bộ song ngữ zh↔vi):
đối chiếu âm Hán-Việt của `zh` với từ trong `vi` bằng `novelworker.translator.hanviet._load()`,
tìm độ lệch `off ∈ [-6, 6]` cho điểm trùng cao nhất. Lệch đều một hướng ≥4 câu liên tiếp = gãy.

⚠ Thước này **báo động giả** với văn dùng nhiều từ chung, ít yếu tố Hán-Việt (truyện hiện đại,
game). Lô 264 và 359 bị gắn cờ nhưng đọc tay thì khớp đúng — **luôn đọc tay xác nhận trước khi
dịch lại**, đừng tin thẳng cờ.

⇒ Rút ra: **cấm để LLM ghi đè file dữ liệu tại chỗ.** Bắt nó ghi ra file kết quả RIÊNG
(`{file, n, vi}`), rồi mình tự áp ngược vào bằng script khớp theo khoá. Ba lượt sửa tại chỗ đẻ
ra lỗi này; hai lượt ghi file riêng thì không.

## Đường đã đi (để khỏi lặp lại)

| lượt | việc | kết quả |
|---|---|---|
| 1-3 | LLM sửa văn phong, ghi đè tại chỗ | đại từ cấm 15,7% → 1,4%; **đẻ ra lỗi lệch 17%** |
| 4-5 | Dịch lại vùng lệch, LLM ghi file riêng | 17.340 → 2.390 → 1.115 câu còn cờ |
| 6 | 8 lô cuối tự dịch tay (~775 câu) | hết lệch thật |

Lượt 4-5 vẫn tái phát lệch **ngay trong đoạn vừa dịch lại** vì cùng lỗi tách câu — prompt phải
nói thẳng "một dòng `zh` ra ĐÚNG một dòng `vi`, dù bên trong có bao nhiêu xuống dòng".

## Nhãn truyện: suy ra từ cấu trúc, không có sẵn

`in_*.jsonl` chỉ có `{n, zh}`, không có tên truyện. Nhưng đo ra: **100.004 câu = 1.667 khối
60 câu liên tiếp, mỗi khối một truyện** (khớp đúng con số 1.667 truyện epub).

`scratch/map_prose_novel.py` khớp 81% câu về `paired_clean.jsonl` (3,8GB, có `novel`) bằng cách
tra 24 ký tự đầu tại mỗi vị trí sau dấu kết câu — khỏi phải đoán đúng bộ tách câu. 19% còn lại
suy ra từ **nhãn đa số của khối**. Đa số chứ không phải nhãn đầu: 8/1.667 khối dính 1-2 câu
khớp nhầm (câu trùng giữa hai truyện).

Kết quả: `scratch/prose_novel_map.jsonl`. Chạy hết ~60 giây.

## Cổng lọc: nới ĐÚNG một chỗ

`_replay_ok` nguyên bản loại **38,7%** — quá cao. Soi ra: `_quotes_balanced` giết 24%, vì nguồn
cắt câu giữa lời thoại nên dấu `”` đóng thoại rơi sang đầu câu SAU.

Đo: 17.494 cặp lệch nháy cả hai phía, **17.390 (99,4%) lệch y hệt nhau** — bản dịch bám đúng
dấu mồ côi của nguồn, không hỏng. Và đây là tình huống CHẠY THẬT (`hachimi_engine` cũng cắt
chương kiểu ấy).

⇒ `35_build_prose_corpus.prose_replay_ok`: hai phía lệch **giống hệt** thì bù nháy cho cân rồi
chấm lại bằng cổng chung; lệch **khác nhau** vẫn loại. Văn bản ghi ra giữ nguyên dấu mồ côi.
38,7% → 23% rớt, tức 61.152 → 76.771 dòng.

Phần rớt còn lại chủ yếu là `_register_ok` (9,5%) cấm `tôi|mình|bạn|cậu|cháu|...` — cấm cả khi
chúng là DANH TỪ ("bạn học", "cậu bé"). Cổng chung, cố ý chặt, **không đụng**.

## Thơ — cũng xong, nhưng số đo phải sửa lại

Sinh **đủ 312/312 lô** (33.699 bài) từ trước. Cái còn thiếu là bước A4: `data/poem_vi.jsonl`
vẫn là **bộ gemma cũ 3.228 bài** (29/08) cho tới 01/09. `36_build_poem_booster.py` đã thay:

| | bộ gemma cũ | bộ Gemini mới |
|---|---|---|
| bài | 3.228 (118 dòng chỉ có `error` 502) | **33.200** |
| phiên âm thô | **32,4%** | **2,2%** |

Tức **tốt hơn ~14 lần**, đúng như bản bàn giao 30/08 ghi (33,7% → 2,4%).

⚠ **BẪY THƯỚC — tại hạ đã dính, ghi lại kẻo dẫm tiếp.** Thước phiên âm thô của dự án là:
tỉ lệ âm trong bản dịch trùng phiên âm Hán-Việt của nguồn, tính trên **CẢ BÀI**, ngưỡng
**0,44** (hiệu chuẩn để bộ gemma ra đúng 33,7%). Tại hạ dựng lại thước theo **VẾ** ở ngưỡng
**0,5**, thấy bộ gemma ra 34,9% ≈ 33,7% nên tưởng đã khớp — rồi kết luận bộ mới 7,4%, "chỉ
tốt hơn 4,7 lần", và ghi đè con số đúng trong tài liệu.

Sai ở chỗ: **khớp bộ đối chứng tại MỘT điểm không chứng minh cả cái thước đúng.** Cùng bộ
gemma ra ~33% ở cả hai cách đo, nhưng bộ mới thì 2,2% với thước đúng và 7,4% với thước tự
chế — sai số gấp 3, đủ đảo kết luận. Muốn tin một thước tự dựng thì phải khớp đối chứng ở
**nhiều điểm**, hoặc chỉ dùng đúng thước cũ.

Rò `eval_poem_locked.jsonl`: **0** bài (so cả khi chỉ lấy chữ Hán).

Hai bẫy định dạng đã dính khi dựng:

1. Lô ra dùng `" / "` ngăn CÂU, `", "` ngăn VẾ; `gate_poem` lại đòi **mỗi vế một dòng**.
   Không đổi thì rớt cổng gần hết.
2. Đổi `", "` → xuống dòng làm **mất dấu phẩy cuối vế**, trong khi bộ cũ giữ
   (`"...trái ân quân,\n Đành cam..."`). Phải đổi thành `",\n"` — data này chính là chỗ model
   học cách trình bày thơ, bỏ phẩy là dạy sai.

Bản cũ giữ ở `data/poem_vi.gemma.jsonl` (làm đối chứng cho thước, đừng xoá).

## Thơ vào corpus v7: đơn vị là VẾ, không phải bài

`37_build_poem_corpus.py`. Chọn đơn vị theo đúng câu trong `eval/eval_poem.py`:
*"Dịch TỪNG VẾ: đó là cách production chia câu"* — runtime cắt theo `，。；？！` nên model chỉ
bao giờ thấy MỘT vế. Train cả bài là dạy một hình dạng đầu vào không tồn tại lúc chạy.
`ctx` gánh phần còn lại: 2 vế trước của chính bài đó.

33.200 bài → 213.790 vế → **203.039 dòng** (rớt: 5.066 register, 5.635 trùng, 50 bị chặn).

**Hai thứ chỉ lộ ra khi làm ở mức vế:**

1. **Cổng tỉ lệ đếm nhầm đơn vị.** `_replay_ok` chặn `0,25 ≤ ký_tự_vi/ký_tự_zh ≤ 4`, hiệu chỉnh
   cho câu văn xuôi dài. Chữ Hán 1 ký tự = 1 âm, tiếng Việt tốn ~3,8 ký tự mỗi âm ⇒ vế thơ 5-7
   chữ **luôn** vọt trần dù dịch chuẩn: `回首白云间` → `ngoảnh trông giữa bạch vân` là 5 chữ ra
   5 âm, tỉ lệ ký tự 4,6 ⇒ bị loại. Loại oan **26%**.
   Đo 213.790 vế: tỉ lệ **âm tiết** trung vị đúng **1,00** (p5 1,0 · p95 1,4), **100%** trong
   [0,5; 2]. ⇒ Đổi sang cổng âm tiết, các cổng khác giữ nguyên.

2. **Chặn eval phải theo VẾ, không theo bài.** Chặn ở mức bài (bước 36) báo `blocked_hit = 0`,
   tưởng sạch. Chặn theo vế bắt được **50 vế của bài eval** nằm trong các bài train khác —
   thơ Đường dùng lại vế của nhau. `eval_poem.py` chấm từng vế nên đó là rò thật.

## Đã gộp

`scratch/corpus2m_v7.jsonl` — **2.201.868 dòng**, `zh` duy nhất 100%:

| nguồn | dòng | truyện/bài |
|---|---|---|
| kaihe (dịch người) | 1.922.132 | 117 truyện |
| prose epub (Gemini) | 76.702 | 1.667 truyện |
| thơ (Gemini, theo vế) | 203.034 | 33.106 bài |

Rò `eval_poem_locked` theo vế: **0**. Rò `dev.jsonl`: 14 — xem mục dưới.

## THƯỚC MẬT ĐỘ HƯ TỪ KHÔNG TÁCH ĐƯỢC NGƯỜI vs MÁY GIỎI (đo 01/09)

Thước `func_per_1k` của `eval/scan_epub_corpus.py` là căn cứ cho kết luận "kho epub ~98%
convert" và cho ngưỡng ≥14 = dịch tay. Đem chấm lại các bộ **đã biết chắc nguồn gốc**:

| bộ | bản chất | hư từ/1k |
|---|---|---|
| epub nhóm trung vị | convert | **7,3** |
| **kaihe (corpus đã gác)** | **NGƯỜI** | **14,4** |
| **kaihe (file thô, 8 truyện đầu)** | **NGƯỜI** | **15,6** |
| epub nhóm ≥14 (33 truyện) | *chưa biết* | 15,2 |
| **Gemini prose (`prose_corpus`)** | **MÁY** | **16,1** |
| **Gemini teacher (`tran_vi_teacher`)** | **MÁY** | **18,1** |

Hai kết luận:

1. ✅ **Tách convert vs trôi chảy thì tốt** — 7,3 so với 14-18, cách nhau hơn gấp đôi, không
   nhầm được. Kết luận "epub ~98% convert" **vẫn đứng**.
2. ❌ **Tách người vs máy thì HỎNG, mà còn ngược dấu** — bản dịch Gemini ăn điểm **CAO HƠN**
   bản dịch người. Vì thước đo "văn có tự nhiên như tiếng Việt không", mà LLM thì tối ưu đúng
   cái đó. Ngày xưa hai chuyện này trùng nhau vì máy chỉ biết convert; giờ thì không.

⇒ **Không dùng thước này để đi tìm thêm data người dịch.** 33 truyện epub ở mức 15,2 nằm lọt
giữa kaihe-người (14,4-15,6) và Gemini-máy (16,1) — thước **không nói được** chúng là người
dịch hay là ai đó chạy LLM. Coi chúng là "mỏ neo người dịch" là tự lừa.

⚠ Mốc tuyệt đối trong `docs/epub-anchor.md` ("dịch tay 17-22, kaihe 18,5") **không tái lập
được**: đo lại kaihe ra 15,6 (thô) / 14,4 (đã gác). Nên ngưỡng ≥14 không mang sang đơn vị văn
bản khác được — muốn dùng thì phải hiệu chuẩn lại trên chính đơn vị đang chấm.

**Muốn tách người khỏi máy giỏi thì cần thước khác.** Hướng đáng thử: đo **độ lệch so với một
model MT** — văn máy dịch thì model tái tạo lại gần đúng (lệch thấp), văn người dịch thì lệch
cao. Chưa đo. Lưu ý `[[glossary-mining-negative]]` đã ghi divergence dùng ở mức CÂU thì
precision thấp; ở mức TRUYỆN có thể khác, nhưng phải dựng đối chứng âm trước khi tin.

## Còn dở

- **`corpus2m.jsonl` rò 14 câu sang `dev.jsonl`** (có sẵn từ 30/08, không phải do gộp).
  14/2,2M nên bỏ qua được, nhưng dựng lại corpus thì chặn thêm `dev.jsonl`.
- `scratch/corpus2m_prose.jsonl` (703MB) là bản gộp giữa chừng chỉ có prose, đã bị
  `corpus2m_v7.jsonl` thay — xoá được.
- `moa_zh_vi.parquet` (396k cặp văn cổ) và `tran_vi_teacher.jsonl` (liều thấp) trong bảng data
  mục 6 vẫn **chưa nắn thành shard**.
- **Đường epub × CNovels dừng ở bước 33.** `scratch/paired_clean.jsonl` có **162.752 cặp
  chương / 1.762 truyện** (≈16 triệu câu), nhưng `pipeline/34_align_labse.py` **chưa chạy
  lần nào** (cần GPU) — không có file đầu ra. Corpus v7 hiện **không có câu nào** từ đường
  này; tại hạ chỉ đọc vế `zh` của nó để lấy nhãn truyện cho prose.
  Trước khi đốt GPU cho bước 34: vế Việt của nó ~98% convert (trung vị 7,4, đo lại 01/09 trên
  chính file này), và 33 truyện ≥14 thì **không chứng minh được là người dịch** (xem mục
  thước ở trên). Kết quả per-truyện đã lưu ở `scratch/epub_density.jsonl`.
- **6.872 chương crawl** (`scratch/zh_raw_v7.jsonl`, 351 truyện, 19,3M chữ) vẫn **chưa dùng**.
  Bản bàn giao 30/08 định dùng vế TRUNG của nó cho đường Gemini "nhập chung với 100k câu văn
  xuôi" — nhưng 100k câu prose đã sinh lấy từ epub, không có chương crawl nào.
