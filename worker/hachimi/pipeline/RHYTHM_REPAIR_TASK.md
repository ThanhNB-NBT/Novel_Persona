# Quy trình một lô SỬA dòng bị cổng loại

Người giao việc sẽ nói bạn sửa dải dòng nào của `data/source/rhythm_rejects_for_teacher.jsonl`,
ví dụ "dải 1–100". Mỗi dòng là một bản dịch đã bị cổng loại, có sẵn `reject_reason`.

1. Đọc `RHYTHM_TEACHER_SPEC.md` trước — luật viết nằm ở đó, lô này không đổi luật.
2. Lấy đúng dải được giao. Mỗi dòng có `{zh, vi, vi_model, reject_reason, ...}`; `vi` là bản
   bạn viết lần trước, `reject_reason` nói nó hỏng ở đâu.
3. Sửa `vi` cho qua được cổng. Bảng đối chiếu lý do → việc phải làm:

   | reject_reason | Sửa thế nào |
   |---|---|
   | chưa tách chuỗi phẩy thành câu | Ngắt thêm câu: mỗi dấu 。 nguồn cho ra ~2 câu tiếng Việt |
   | băm câu quá vụn | Gộp bớt lại, câu trung bình 70–90 ký tự |
   | số không khớp | Trả lại đúng mọi con số của nguồn, đúng thứ tự |
   | thay mù đại từ (một ngươi bé) | Chữ bị hỏng do thay máy móc — viết lại cả câu cho đúng nghĩa |
   | mất dấu thoại / quote lệch | Trả lại ngoặc kép cho lời thoại, mở đóng cân nhau |
   | đại từ / danh xưng hiện đại | ta/ngươi/hắn/nàng; 哥哥=ca ca, 姐姐=tỷ tỷ, 妹妹=muội muội, 弟弟=đệ đệ |
   | tỷ lệ dài bất thường | Bản dịch thiếu hoặc thừa ý so với nguồn — dịch lại cho đủ |
   | dấu câu nhân đôi / không viết hoa | Dọn dấu, viết hoa đầu câu |

4. Ghi `data/source/rhythm_fixed_<đầu>_<cuối>.jsonl`, mỗi dòng giữ nguyên các trường gốc
   (bỏ `reject_reason`) với `vi` đã sửa. Ghi bằng Python `open(..., encoding="utf-8")` +
   `json.dumps(row, ensure_ascii=True)`. Không viết tiếng Việt trực tiếp trong lệnh PowerShell.
5. Tự kiểm: `E:\Novel_Project\.venv\Scripts\python.exe 09_gate_rhythm_gold.py data/source/rhythm_fixed_<đầu>_<cuối>.jsonl`
   rồi sửa tiếp những dòng còn bị loại. Mục tiêu **≥70%** dòng trong lô qua cổng.
6. Báo cáo: số đạt/tổng, các lý do còn lại.

Dòng nào chữa mãi không được thì cứ để bản tốt nhất của bạn — cổng sẽ tự loại, không sao.
Đừng bịa nội dung không có trong nguồn để lấp chỗ trống.
