# Kết luận ứng viên Hachimi v-next D

Ngày đánh giá: 2026-07-24. Đây là thí nghiệm; không thay model production.

## Cấu hình đã xác minh

- Base: `ngocdang83/HachimiMT-60-zh-vi`.
- Gold đã duyệt: 240 cặp, lặp 3 lần.
- Replay lịch sử qua cổng lọc: 4.948/5.000 cặp.
- Tổng: 5.668 lượt train, 1 epoch, learning rate `1e-5`, effective batch 32.
- CT2: `experiments/hachimi_vnext_d/ct2-int8_float32/model.bin`.

## Eval 60 cảnh khóa

| Model | Similarity TB | Hán sót | Đại từ hiện đại | Đệm thừa | Quote lỗi | Số lỗi |
|---|---:|---:|---:|---:|---:|---:|
| Base | 0,7050 | 0 | 15 | 3 | 6 | 0 |
| Current | 0,7107 | 0 | 15 | 2 | 6 | 0 |
| B — gold x3 | 0,7149 | 0 | 15 | 1 | 6 | 0 |
| C — replay ngoài miền | 0,7192 | 0 | 21 | 3 | 5 | 0 |
| **D — replay lịch sử** | **0,7160** | **0** | **15** | **1** | **5** | **0** |

D cải thiện similarity, đệm thừa và giảm nhẹ lỗi dấu thoại so với current. Một
số câu tự nhiên hơn, nhưng vẫn còn văn convert và sai quan hệ chủ thể.

## Sáu chương dài

Chạy cùng pipeline trên truyện 32, 282 và 293, mỗi truyện hai chương:

| Model | Hán sót | Đại từ hiện đại | Đệm thừa | Dấu ngoặc cong |
|---|---:|---:|---:|---:|
| Current | 21 | 39 | 10 | 4 đoạn lệch |
| **D** | **21** | **51** | **8** | **4 đoạn lệch** |

Phần tăng đại từ tập trung ở chương 2 truyện 32: D đổi `ta` thành `tôi`, lạm dụng
`mình` trong lời kể và suy nghĩ nội tâm. Tên `玛利亚` vẫn dao động giữa `Mã Lợi Á`
và `Malia`; `摩尔多左相到` vẫn bị đảo
thành “Moredo đến tả tướng”; `耶` vẫn có lúc thành “Yah”.

## Quyết định

**Không dùng D thay model hiện tại.** Replay lịch sử giúp điểm giống tham chiếu
nhưng không sửa được các lỗi ngữ cảnh cốt lõi và còn làm xưng hô, dấu thoại xấu hơn
trên chương dài. Không làm thêm biến thể chỉ bằng cách đổi hệ số lặp trên cùng bộ
dữ liệu này.

Muốn có vòng E, dữ liệu mới phải nhắm trực tiếp vào ba lỗi đã chứng minh:

1. quan hệ chủ thể và nhất quán `ta/hắn/nàng` trong đoạn nhiều câu;
2. một lượt thoại dài với dấu mở/đóng cân bằng;
3. trật tự chức danh–tên riêng và tên xuyên suốt ngữ cảnh.

Chi tiết:

- `hachimi_vnext_abd_eval.md`
- `hachimi_base_vs_finetune_vnext_d.md`
- `sample_translation_current_gate.md`
- `sample_translation_d.md`
