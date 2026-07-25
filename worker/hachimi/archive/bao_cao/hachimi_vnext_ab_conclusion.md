# Kết luận pilot Hachimi v-next A/B

Ngày chạy: 24/07/2026. Toàn bộ là thí nghiệm local; không sửa production, không
deploy và không ghi DB.

## Dữ liệu và cấu hình

- Gold đã đọc nghĩa và duyệt thủ công: **200** cặp.
- Eval khóa, không trùng gold: **60** cảnh, 10 cảnh cho mỗi nhóm lỗi.
- Replay local dự phòng sau lọc register, duplicate, xung đột và trùng eval/gold:
  **4.949** cặp từ `approved_gold.jsonl`.
- Base của cả hai ứng viên: `ngocdang83/HachimiMT-60-zh-vi`.
- A: gold ×1, tổng 5.149 dòng; B: gold ×3, tổng 5.549 dòng.
- Cả hai: learning rate `1e-5`, 1 epoch, batch hiệu dụng 32, seed cố định.
- A chạy 1.292 giây, eval loss cuối **1,556**.
- B chạy 1.445 giây, eval loss cuối **1,469**.

Replay chuẩn trên Hugging Face chưa dùng vì máy không có `HF_TOKEN`; dataset đó
đang gated. Đây là lý do kết quả được gọi là pilot local, không phải bản train
cuối trên Kaggle.

## Kết quả cùng pipeline hiện tại

| Model | Similarity tham chiếu | Hán sót | Đại từ hiện đại | Đệm thừa | Quote lỗi |
|---|---:|---:|---:|---:|---:|
| Hachimi gốc | 0,5216 | 0 | 15 | 3 | 6 |
| CT2 hiện tại | 0,5270 | 0 | 15 | 2 | 2 |
| A — gold ×1 | 0,5245 | 0 | 15 | 2 | 5 |
| B — gold ×3 | **0,5384** | 0 | 15 | **1** | 6 |

`Similarity` chỉ là chỉ báo ký tự để xếp hàng đọc tay. B chỉ tăng khoảng **2,2%**
so với CT2 hiện tại, thấp xa cổng +10%. Trong 60 cảnh, model thắng theo chỉ báo
không áp đảo: gốc 15, hiện tại 18, A 11, B 16.

Theo nhóm, B còn giảm `semantic_context` từ 0,4173 xuống 0,3958, tức giảm khoảng
**5,2%**. Như vậy B vi phạm đúng cổng “không nhóm nào kém model hiện tại quá 5%”.
A cũng không hơn model hiện tại về tổng thể.

## Đọc tay các ca quyết định

Các lỗi dưới đây là lỗi nghĩa/ngữ cảnh, không phải chỉ khác chữ:

| Cảnh | Điều quan sát được |
|---|---|
| 2, novel 205 | Cả A/B vẫn dịch `后天努力` thành “ngày kia cố gắng”, làm sai nghĩa “nỗ lực rèn luyện về sau”; câu dài mất nhiều dấu ngắt. |
| 3, novel 3978 | B vẫn lặp hai lần cụm quân quy cuối câu và không dịch đủ “Ba điều kỷ luật, Tám điều chú ý”. |
| 4, novel 32 | `枪` trong đúng ngữ cảnh cành cây luyện thương vẫn lúc ra “súng”, lúc ra “thương” trong cùng câu. |
| 18, novel 32 | B bớt đảo chủ thể so với model hiện tại nhưng vẫn để “trang bị của mình” trong lời kể, sai điểm nhìn. |
| 41, novel 24 | B làm rơi đơn vị “gỗ” sau số 10; đây là lỗi số liệu/vật tư nghiêm trọng dù câu còn đọc được. |
| 42, novel 992 | Lời tác giả về bảng lượt đọc/bảng đề cử vẫn bị dịch sai quan hệ; finetune chưa học được loại meta này. |
| 43, novel 3978 | Mệnh đề “ngoại trừ nội địa Trung Quốc” vẫn bị đảo thành giám sát “toàn bộ đại lục Trung Quốc”; đây là lỗi đảo nghĩa nghiêm trọng. |
| 53, novel 1256 | B tự nhiên hơn chút nhưng vẫn đảo cấu trúc “linh căn ngụy trang để lừa cô bé” thành “lừa đơn linh căn của cô bé”. |
| 59, novel 356 | B vẫn giữ “mình” trong lời thoại cổ phong và dịch `真要爆发` thành “thật sự muốn bộc phát”. |
| 60, novel 992 | B bỏ được “nha”, nhưng làm rơi hình ảnh nhóc tỳ “ra vẻ tiểu đại nhân”. |

Kết luận đọc tay: loss thấp hơn không đồng nghĩa câu đúng hơn. B sửa được một số
dấu câu, thuật ngữ và nhịp câu ngắn, nhưng chưa xử lý ổn chủ thể, quan hệ, phủ
định và thêm-bớt ở câu dài.

## Thí nghiệm ngữ cảnh và cách chia câu

Engine hiện đặt giới hạn nguồn là `hachimi_max_len // 2 = 90` token. Khi một câu
dài vượt giới hạn, nó tách ở từng dấu phẩy rồi dịch các mảnh độc lập. Trong khi
đó gold được train dưới dạng cảnh dài tới 448 token. Đây là lệch đơn vị
train–inference.

Đã thử thật trên cùng 60 cảnh:

| Chiến lược | Similarity | Đại từ hiện đại | Quote lỗi |
|---|---:|---:|---:|
| CT2 hiện tại, split 90 | 0,5270 | 15 | 2 |
| B, split 90 | 0,5384 | 15 | 6 |
| B, gom mệnh đề 160 | 0,5445 | 18 | 3 |
| B, nguồn 448 / đích 180 | 0,5466 | 18 | 3 |
| B, nguồn 448 / đích 448 | **0,5477** | 17 | **0** |

Ngay cả cấu hình tốt nhất cũng chỉ hơn CT2 hiện tại khoảng **3,9%**, đồng thời
nhóm `dialogue_register` giảm khoảng 2,6% và `semantic_context` giảm khoảng 2,5%.
Nó vẫn có nhiều hồi quy nghiêm trọng ở từng cảnh. Vì vậy không nên chỉ tăng
`hachimi_max_len` hoặc đổi splitter trong production.

## Quyết định

**Không nhận A, không nhận B, không đổi splitter production.** Cả hai ứng viên
đều không qua cổng pilot. CT2 hiện tại được giữ nguyên.

Không nên train tiếp bằng cách tăng `gold-repeat` hay số epoch: B đã cho thấy
trọng số gold cao hơn làm loss eval đẹp hơn nhưng không loại được lỗi nghĩa và
còn tăng lỗi quote.

Hướng tiếp theo đúng gốc, nếu vẫn muốn theo Hachimi 57M:

1. Chốt một đơn vị dịch duy nhất cho cả train và inference. Nếu inference vẫn
   chia ở 90 token thì gold phải được căn nguồn–đích theo đúng các mảnh đó; nếu
   train cảnh dài thì engine phải có chiến lược giữ ngữ cảnh ổn định, không chỉ
   nâng trần token.
2. Chỉ sau khi bước 1 có benchmark tốt mới duyệt thêm 100–200 cặp, ưu tiên câu
   dài nhiều chủ thể, lời thoại kèm lời dẫn và lời tác giả. Không lấy thêm mẫu
   câu ngắn vốn đã gần bão hòa.
3. Tên riêng/item hiếm tiếp tục giao cho glossary + termguard; không tăng data
   để bắt model ghi nhớ tên.
4. Nếu mục tiêu bắt buộc là hiểu ổn quan hệ trong cảnh dài, cần chấp nhận trần
   của MarianMT 57M: finetune nhỏ chỉ sửa phân bố câu chữ, không biến model thành
   bộ dịch có suy luận ngữ cảnh. Khi đó nên đánh giá một model dịch lớn hơn ở
   chế độ offline, thay vì tiếp tục đổ gold vào 57M.

Artifact chi tiết:

- `experiments/hachimi_vnext_ab_eval.md`
- `experiments/hachimi_vnext_ab_eval.jsonl`
- `experiments/hachimi_split_strategy_eval.md`
- `experiments/hachimi_split_strategy_eval.jsonl`
- `hachimi_finetune/runs/vnext-a-local/`
- `hachimi_finetune/runs/vnext-b-local/`
