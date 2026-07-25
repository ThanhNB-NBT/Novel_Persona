# Kho lưu artifact Hachimi v-next trước E

Các file dưới đây là đầu ra có thể tái tạo của vòng so sánh cũ, được giữ lại để
truy vết chứ không còn là bằng chứng quyết định cho ứng viên E. Không có file mã
nguồn, model CT2, dữ liệu train, corpus `hachimi_base_longform.jsonl`, hay artifact
E nào bị di chuyển.

| File | Lý do chuyển |
|---|---|
| `hachimi_base_vs_finetune.md` | So sánh base/finetune đời đầu, không còn tham chiếu. |
| `hachimi_base_vs_finetune_vnext_d.md` | So sánh dài của ứng viên D đã bị vòng E thay thế. |
| `hachimi_vnext_abd_eval.jsonl` | Đầu ra thô 60 cảnh của vòng đến D; chỉ dùng làm lịch sử. |
| `hachimi_vnext_abd_eval.md` | Bản đọc tay của đầu ra vòng đến D; chỉ dùng làm lịch sử. |
| `hachimi_vnext_d_conclusion.md` | Kết luận không nhận D; được lưu cùng các bằng chứng D. |
| `hachimi_vnext_d_eval.stderr.log` | Log rỗng của lần đánh giá D. |
| `hachimi_vnext_d_eval.stdout.log` | Log rỗng của lần đánh giá D. |
| `sample_translation_current_gate.md` | Mẫu baseline đã dùng riêng khi đối chiếu D. |
| `sample_translation_d.md` | Mẫu đầu ra riêng của ứng viên D. |

## Cố ý giữ ở `experiments/`

- `evaluate_hachimi_vnext_ab.py`: được evaluator E import hàm kiểm tra quote.
- Toàn bộ `hachimi_vnext_e*`, `hachimi_vnext_e/`, `hachimi-vnext-e-kaggle.zip`:
  artifact vòng E đang đánh giá.
- `hachimi_split_strategy_eval.*`: đầu ra có E và đường dẫn được evaluator hiện tại
  ghi đè khi chạy lại.
- `hachimi_vnext_ab_conclusion.md` cùng `hachimi_vnext_ab_eval.*`: README/plan còn
  tham chiếu trực tiếp.
- `hachimi_external_replay_pilot.md`: tài liệu nghiên cứu nguồn dữ liệu còn trỏ tới.
- Mọi thư mục model C/D/E và dữ liệu/corpus huấn luyện: không phải output báo cáo.
