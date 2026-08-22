# Benchmark Hy-MT2-1.8B trên VPS

Đo xem model dịch chuyên 1.8B của Tencent có đủ nhanh/nhẹ để chạy chung VPS
2 core/2GB với worker không — quyết định bằng SỐ + MẮT, không bằng ước tính.

## Chuẩn bị đầu vào (một lần)

File `hymt2_bench_input.jsonl` chứa 4 chương mẫu thật (zh gốc + bản v5 để đối
chiếu) — **không vào git** theo chính sách ignore jsonl của thư mục hachimi.
Đã sinh sẵn ở máy nhà; đưa lên VPS bằng:

```powershell
scp worker\hachimi\eval\hymt2_bench_input.jsonl root@103.72.57.133:/root/Novel_Project/worker/hachimi/eval/
```

Muốn đổi chương mẫu khác: chạy lại `make_hymt2_bench_input.py <pairs.json> hymt2_bench_input.jsonl`.

## Chạy trên VPS (~30 phút)

```bash
cd /root/Novel_Project   # hoặc nơi có repo
git pull
cd worker/hachimi/eval
python3 hymt2_bench.py                    # 2bit + Q4_K_M, mỗi bản ~15 phút
python3 hymt2_bench.py --quants 1.25     # thêm bản 440MB nếu muốn
```

Yêu cầu: docker + python3 (VPS đã có cả hai). Không pip install gì.
Container bị chặn RAM ở 1100MB (mô phỏng chung máy với worker ~700MB) —
OOM giữa chừng = trả lời luôn câu hỏi "có vừa không".

## Đọc kết quả

`hymt2_bench_result/report.md`: bảng tok/s + RAM đỉnh từng quant, kèm đầu mỗi
bản dịch đặt cạnh **ref_vi** (Hachimi v5 đang production) — mở ra đọc so sánh
3 lớp lỗi đang đau: ngày tháng xáo trộn, tên nhân vật lệch, thành ngữ chết.

## Cổng quyết định

| Điều kiện | Kết luận |
|---|---|
| ≥10 tok/s và RAM đỉnh ≤900MB và chất lượng rõ hơn v5 | triển khai lane chất lượng |
| Đạt chất lượng nhưng <10 tok/s | chỉ dùng làm teacher sinh data offline |
| Thua v5 hoặc OOM | bỏ hướng này, về booster 57M |

Lưu ý: GGUF 1.25-bit/2-bit cần llama.cpp mới có kernel STQ (PR #22836) —
image `ghcr.io/ggml-org/llama.cpp:server` mới nhất là đủ; server không lên
thì script tự ghi log lỗi vào report và chuyển sang quant kế.
