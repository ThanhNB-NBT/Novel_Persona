# Đo lại model NIM từ box nhà — 29/08/2026

> Kết luận: **google/gemma-4-31b-it là model NIM DUY NHẤT dịch nổi cả chương**. Ngang Hachimi v5
> trên mọi thước tự động, hơn rõ khi đọc, thua ở hai điểm: gộp đoạn (11% chương) và
> đại từ hiện đại lọt vào thoại (1,19 vs 0,64 lần/chương).

## Vì sao phải đo lại

Production dời từ VPS thuê về box nhà (28/8). Gọi NIM từ box nhà mất **2,5–3,7s**;
từ VPS cũ là 38–79s. Mọi kết luận "loại vì chậm" trong `HYMT2_BENCH_README.md` và
`benchmark_nim_models.py` đều đo ở IP cũ nên hết giá trị.

## Sàng vòng 1 (12 model, chương thật ~3.900 chữ, prompt production)

| model | kết cục |
|---|---|
| `google/gemma-4-31b-it` | **dùng được** |
| `openai/gpt-oss-120b` | nhanh (36–81s) nhưng lệch đoạn, sai nghĩa 咒语 |
| `nvidia/nemotron-3-super-120b-a12b` | tắt suy luận được (`extra_body={"chat_template_kwargs":{"thinking":False}}`, 67s) nhưng lẫn tiếng Hàn/Ý + phiên âm nguyên cụm |
| `nvidia/nemotron-3-ultra-550b-a55b` | dịch được nhưng rơi về văn convert nguyên đoạn |
| `nvidia/nemotron-3.5-lightning-30b-a3b` | 190 tok/s, KHÔNG tắt được suy luận, tràn 16k token |
| `nvidia/riva-translate-4b-instruct-v2` | dịch ra tiếng Anh + tóm tắt; context chỉ 8k |
| `deepseek-v4-pro-0813` | chép lại nguyên văn tiếng Trung |
| `deepseek-v4-flash-0731`, `kimi-k3`, `minimax-m3` | 504 |
| `kimi-k2.6`, `palmyra-creative-122b` | 404 (key không mở) |

## Chung kết: gemma-4-31b trên 36 chương thật / 12 truyện / 9 nhóm thể loại

Bộ test dựng bằng `bench_build_testset_live.py` (zh lấy từ R2, bản Việt đang phục vụ làm mốc),
chạy bằng `bench_run_model_chapters.py`, chấm bằng `bench_score_chapters.py`.

| chỉ số (TB/chương) | gemma-4-31b | Hachimi v5 |
|---|---|---|
| lỗi / 36 chương | 0 | — |
| ký tự | 8.059 | 8.072 |
| tỉ lệ độ dài so nguồn | 3,38 | 3,38 |
| tỉ lệ số đoạn so nguồn | 0,99 | 1,00 |
| chữ Hán sót (sau vá) | 0 | 0 |
| chữ Hán sót (trước vá) | 0,81 | — |
| cảnh báo lint | 0,75 | 0,81 |
| **đại từ hiện đại** | **1,19** | **0,64** |
| **khớp dòng thoại/kể theo vị trí** | **0,923** | **0,997** |
| giây/chương (1 làn) | 148,9 | ~22 |
| giây/chương (4 làn song song) | **38,9** | — |

- **Gộp đoạn**: 4/36 chương gemma gộp nhiều dòng (65 đoạn so với 94 của nguồn). Đã kiểm:
  KHÔNG mất nội dung — tổng ký tự 0,97–1,03× Hachimi, đoạn cuối khớp, thứ tự đúng.
  Nó gộp câu dẫn với thoại, và thêm một dòng tiêu đề chương (`_pop_title` đã lo).
- **Đại từ**: lỗi dồn vào truyện bối cảnh tây/hiện đại — `nv322` (Dải Ngân Hà) 8 lần/chương,
  toàn "chúng tôi" trong thoại kẻ dưới nói với lãnh chúa. Các truyện khác 0,3–1,0.
  Trái chỉ thị đã ghi rõ trong `MAIN_CHAPTER_DIRECTIVE`; Hachimi tuân vì được finetune.
- Đối chiếu ba cột để đọc tay: `compare_gemma_vs_hachimi.html` (không commit).

## Thông lượng

4 làn = 2 key × `_MAX_INFLIGHT_PER_KEY`=2 → 38,9s/chương hiệu dụng, không dính 429.
Tương đương ~2.200 chương/ngày; tải hiện tại 32 chương/ngày, hàng đợi rỗng.

## Việc phải làm TRƯỚC khi chuyển engine

1. **Termguard**: nhánh LLM trong `handle_chapter` không đi qua `termguard` — mất cưỡng chế
   glossary tên riêng mà Hachimi đang dựa vào. Đây là rào chắn số một.
2. Siết đại từ trong thoại (prompt hoặc mở rộng `_fix_register` bắt "chúng tôi").
3. `TRANSLATOR_CONCURRENCY` 2 → 4 nếu muốn đủ thông lượng.

## Chạy local model to hơn: KHÔNG

Box là i5-6200U 2 nhân, còn 4,6GB trống. Model 1,8B q4 đo được 2,2 tok/s ≈ 19 phút/chương.

## Đọc tay — 5 chương, 5 thể loại, ~150 cặp câu

Thước tự động cho kết quả hoà, nên phải đọc. Đếm lỗi trên các đoạn đã đọc (không phải cả chương):

| chương | thể loại | lỗi Hachimi | lỗi gemma |
|---|---|---|---|
| nv9806 ch1 | khoa huyễn | 4 | 3 |
| nv1256 ch147 | tiên hiệp | 3 | 2 |
| nv322 ch6 | khoa huyễn/tây | 4 | 4 |
| nv282 ch40 | game/ngôn tình | 4 | 2 |
| nv17371 ch1 | võng du | 3 | 0 |

Số lượng gần nhau nhưng **loại lỗi khác hẳn nhau về mức nghiêm trọng**.

### Hachimi sai NGHĨA khi truyện ra ngoài miền được finetune

- `工头` (quản đốc) → **"đầu bếp"**; cùng chương còn gọi thêm "quản đốc" và "công đầu" — ba
  cách cho một từ.
- `驾驶员` (phi công) → **"người lái xe"**, lặp lại 2 lần trong chương khoa huyễn.
- `宅男` → "người đàn ông ẩn thân". `下到3岁的小孩` → "đứa trẻ **dưới** 3 tuổi".
- `46亿` → **"46 tỷ"** (sai 10 lần; đúng là 4,6 tỷ), lặp 2 chỗ.
- `选择支付积分` → "chọn điểm thanh toán" (đảo nghĩa). `三天带薪假期` → "ba ngày cùng kỳ nghỉ lương".
- Câu vỡ mạch: *"Lý Bá Dung trên người bọn họ có mùi vị 'đồng loại', khí chất gọi là lái xe."*
- Sai tên riêng: `枫叶星` → "Phong Hiệp Tinh" (đúng: Phong Diệp).

Trong **tiên hiệp/huyền huyễn thì Hachimi ngang hoặc hơn** — `炼气九重巅峰` → "Luyện Khí cửu
trọng đỉnh phong" (gemma: "đỉnh phong Luyện Khí tầng chín"), `金手指` → "kim thủ chỉ"
(gemma: "bàn tay vàng"), `叮` → "Keng!" (gemma: "Đinh!").

### gemma lệch PHONG và QUY ƯỚC, hiếm khi sai nghĩa

- **Đại từ trong thoại**: "chúng tôi/Tôi khai" ở truyện bối cảnh tây — trái chỉ thị trong
  `MAIN_CHAPTER_DIRECTIVE`. Hachimi không bao giờ tuột.
- **Latin hoá tên**: `大天使号` → "tàu Archangel" (Hachimi: "Đại Thiên Sứ Hào"), `哈里男爵` →
  "Nam tước Harry" (Hachimi: "Ha Lý Nam tước"). Không sai, nhưng **lệch glossary đang có** →
  bằng chứng sống cho rủi ro thiếu termguard.
- Lỗi lẻ: `总得` → "tổng cộng"; "hồn **siêu** phách lạc" (sai chính tả).
- **Dòng tiêu đề**: gemma tự thêm "Chương N: ..." ở 33/36 chương; 1/36 nó nuốt luôn câu đầu
  vào dòng tiêu đề (`Chương 1: Sự hoang mang của Lý Bá Dung rất mờ mịt. Là một phi công...`)
  → `_pop_title` sẽ cắt mất câu mở chương. Phải chặn.

## Phán quyết

Không phải "model nào hơn" mà là **hơn ở đâu**: Hachimi mạnh trong miền nó được finetune
(tiên hiệp, huyền huyễn, kiếm hiệp), sai nghĩa có hệ thống khi ra ngoài (khoa huyễn, võng du,
đô thị, bối cảnh tây). gemma đều tay ở mọi thể loại nhưng lệch phong và làm trôi tên riêng.

**Đề xuất: định tuyến theo thể loại thay vì thay hẳn.** `novels.translation_provider` đã là
cột per-truyện nên đây là việc của DỮ LIỆU, không cần sửa code:
- giữ `hachimi` cho Tiên hiệp / Huyền huyễn / Kiếm hiệp (nhanh 22s, register chuẩn, thuật ngữ chuẩn);
- dùng `nvidia` + gemma-4-31b cho Khoa huyễn / Võng du / Game / Đô thị / Hệ thống hiện đại.

Điều kiện bắt buộc trước khi bật: vá termguard cho nhánh LLM, chặn dòng tiêu đề tự thêm,
siết đại từ trong thoại.

---

# Vòng v6 — kết quả train (30/08/2026)

Pack v6 = v5 + `epub_anchor` 4.024 cặp + `poem_booster` 2.651 bài (+ 120 bài thơ khoá).
Train **trên máy dev CPU**, 84.725 dòng, 2.647 step, **3,2 giờ**, train_loss 1,347.

## Văn xuôi: KHÔNG cải thiện

| 55 chương sạch | bịa chủ ngữ/100 câu | đại từ hiện đại/chương | lint/chương |
|---|---|---|---|
| v5 production | 0,03 | **1,13** | **3,07** |
| v6 | **0,02** | 1,16 | 3,64 |

4.024 cặp epub trên 84.725 dòng (4,7%) là quá loãng để dịch chuyển thứ gì. Khớp đúng bài học
cũ: "booster vài chục dòng không đè nổi prior" — và khớp `DATA_CHUAN` trục 2 (lượng không
thay được đa dạng, mà 4k cặp thì chưa đủ cả lượng).

## Thơ: CÓ cải thiện rõ

Thước cũ (sạch Hán / không lặp) cho cả hai 100% nên vô dụng. Thước phân biệt được là
**tỉ lệ câu bị phiên âm thô** (≥3 từ Hán-Việt viết hoa liên tiếp, kiểu "Cửu Mạch Tận Phong Trần"
thay vì dịch nghĩa):

| model | câu phiên âm thô / 770 | tỉ lệ |
|---|---|---|
| v5 production | 241 | **31,3%** |
| **v6** | **174** | **22,6%** |
| gemma-4-31b (nguồn data) | 9 | 1,2% |

2.651 bài thơ = 3% pack, kéo lỗi xuống hơn một phần tư. Còn xa gemma nhưng chứng minh
**hướng đúng**: model học được thể thơ nếu có data thơ.

## Việc tiếp nếu theo hướng này

- Tăng data thơ: đã có 37.003 bài Đường luật giản thể sạch (`chinese-poetry`, MIT) trong
  `data/poem_tang_simp.jsonl`, mới dịch 3.110. Sinh tiếp bằng gemma-4-31b (1,63s/bài, 4 làn).
- Cân nhắc nhân trọng số shard thơ (như `--gold-repeat`) thay vì chỉ tăng số dòng.
- **Lọc rác trong data thơ**: bộ khoá lộ ra bản gemma có cả chữ Hàn ("평 sinh sơ chí") mà cổng
  hiện tại không bắt. Phải thêm cổng chặn ký tự ngoài Latin/Việt.
