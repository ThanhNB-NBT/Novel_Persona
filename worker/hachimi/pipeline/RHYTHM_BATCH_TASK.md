# Quy trình một lô gold nhịp câu

Bạn là thầy dịch cho vòng finetune model MT 57M Trung→Việt. Người giao việc sẽ nói bạn
làm dải dòng nào, ví dụ "dải 1601–1700".

1. Đọc `RHYTHM_TEACHER_SPEC.md` trước — mục tiêu và luật viết nằm ở đó.
2. Lấy đúng dải dòng được giao trong `dataset/rhythm_pool.jsonl` (1-indexed). Mỗi dòng có
   `{zh, vi_model, novel_id, chapter_index, line_index}`.
3. Với TỪNG dòng, đọc `zh` rồi viết bản dịch mới vào trường `vi`:
   - Dịch lại cho ĐÚNG NGHĨA từ `zh`. `vi_model` chỉ để tham khảo tên riêng và thuật ngữ;
     sửa luôn những chỗ nó dịch sai, sai chủ ngữ hoặc dùng cụm Hán-Việt ngô nghê.
   - **Nhịp câu là mục tiêu chính**: mỗi dấu 。 của nguồn cho ra khoảng **2 câu tiếng Việt**,
     mỗi câu khoảng **70–90 ký tự**. Không gói cả chuỗi phẩy thành một câu lê thê, cũng
     không băm mỗi mệnh đề thành một câu.
   - Xưng hô: lời kể ngôi ba nam `hắn`, nữ `nàng`, ngôi nhất `ta`; thoại xưng `ta` gọi
     `ngươi`. CẤM `tôi, mình, bạn, cậu, cháu, anh ta, cô ta, cô ấy, ông ta, bà ta`.
   - Giữ nguyên mọi con số, giữ cách phiên tên riêng của `vi_model`, giữ ngoặc kép cho lời
     thoại, không sót chữ Hán, không space trước dấu câu, mỗi câu viết hoa chữ đầu.
   - KHÔNG copy nguyên `vi_model` cho bất kỳ dòng nào. KHÔNG dùng script/regex thay dấu
     hàng loạt — cổng phát hiện và loại sạch.
4. Ghi `dataset/rhythm_shard_<đầu>_<cuối>.jsonl`: dòng gốc của pool cộng thêm trường `vi`.
   Ghi bằng Python `open(..., encoding="utf-8")` + `json.dumps(row, ensure_ascii=True)`.
   Không bao giờ viết tiếng Việt trực tiếp trong lệnh PowerShell (hỏng mã UTF-8).
5. Tự kiểm: `E:\Novel_Project\.venv\Scripts\python.exe 09_gate_rhythm_gold.py dataset/rhythm_shard_<đầu>_<cuối>.jsonl`.
   Xem `..._rejects.jsonl`, sửa đúng những dòng bị loại, chạy lại. Lặp tới khi **≥75/100 đạt**.
6. Báo cáo ngắn: số đạt/100, tỷ lệ câu VI trên dấu 。, độ dài câu trung bình.

Chỉ động vào shard của mình. Không chạy git. Không sửa `rhythm_pool.jsonl`.
