# Chẩn đoán Hachimi gốc so với current/D/E

> Cùng 60 đoạn broad đã cố định, không có glossary. Các metric dưới đây chỉ đo lỗi
> cấu trúc/định dạng; chúng không đo đủ nghĩa, quan hệ chủ thể hay độ tự nhiên câu.

| Model so với base | Δ lỗi trọng yếu | Δ đại từ hiện đại | Δ Hán sót | Δ quote lỗi | Δ số lỗi | Δ đệm |
|---|---:|---:|---:|---:|---:|---:|
| `current` | -33 | -35 | +0 | +0 | +2 | -1 |
| `d_historical_replay` | -6 | -11 | +0 | +4 | +1 | -2 |
| `e_strict_replay` | -1 | -5 | +0 | +3 | +1 | -2 |

## Theo thể loại

| Model | Tệ hơn base | Tốt hơn base | Bằng base |
|---|---:|---:|---:|
| `current` | 3 | 7 | 5 |
| `d_historical_replay` | 6 | 4 | 5 |
| `e_strict_replay` | 6 | 3 | 6 |

## Kết luận đúng phạm vi số liệu

- Trên 60 đoạn này: `current` giảm 33 lỗi trọng yếu so với base; `d_historical_replay` giảm 6 lỗi trọng yếu so với base; `e_strict_replay` giảm 1 lỗi trọng yếu so với base.
- Vì vậy giả thuyết **data finetune làm hỏng model một cách tổng thể không được chứng minh** bởi broad test này. D/E vẫn có hồi quy cục bộ rõ ở quote và số, đồng thời tệ hơn base ở 6/15 thể loại theo lỗi trọng yếu; đây là tín hiệu phải sửa/loại data, không phải bằng chứng rằng cả model đã tệ hơn base.
- Có thể kết luận **hồi quy cấu trúc đo được** khi một model có tổng lỗi trọng yếu tăng và tệ hơn base ở đa số thể loại.
- Không thể kết luận chỉ từ bảng này rằng *data finetune làm hỏng chất lượng dịch tổng thể* hoặc làm sai nghĩa: corpus không có bản tham chiếu người dịch. Muốn chứng minh nhân quả đó cần đọc tay các ca khác biệt lớn hoặc thêm tập tham chiếu khóa.
- Vì current cũng là một finetune/biến thể không tách được mọi khác biệt pipeline từ corpus này, kết quả chỉ là bằng chứng cảnh báo hay bác bỏ giả thuyết theo các metric đã đo, không phải phán quyết tuyệt đối về data train.
