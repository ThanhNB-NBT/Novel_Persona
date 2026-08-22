# Benchmark Hy-MT2-1.8B trên VPS

> ## ⛔ KẾT QUẢ THỰC TẾ (22/08/2026): LOẠI hướng này khỏi VPS 2GB
>
> Đã chạy thật trên VPS production. Ba phát hiện:
>
> 1. **GGUF low-bit chính chủ hỏng**: cả `2Bit.gguf` lẫn `1.25Bit.gguf` đều fail
>    `tensor offset mismatch` ở `blk.0.attn_k_norm` — file viết bằng writer riêng
>    của AngelSlim, lệch chuẩn kể cả khi build llama.cpp từ nhánh PR #22836
>    (`sjl623/llama.cpp@STQ_0`, commit 1e411d8). Là issue đã biết — HF discussion
>    #6; Tencent xác nhận *"main branch does not support our kernel"* và kernel
>    2-bit **chưa viết xong** ("on the way"). File tải về khớp SHA256 của HF nên
>    KHÔNG phải do download hỏng.
> 2. **Q4_K_M (quant chuẩn) chạy được nhưng quá chậm + quá nặng**: đo thật cùng
>    máy với worker — token generation **~2,2 tok/s** (tuột còn <1 khi swap
>    thrash), RSS **1,2GB**, load average 3.2 trên 2 core. Một chương ~2500
>    token = **~19 phút**, chậm hơn Hachimi v5 (~10s/chương) khoảng 100×.
> 3. **Cổng qua/lo fail cả hai điều kiện** (<10 tok/s, >900MB).
>
> ### Giữ lại từ đợt này
> - Build llama-server nhánh STQ_0 còn nằm ở `/root/llamacpp-stq/` trên VPS —
>   dùng lại được khi (a) Tencent sửa file GGUF + merge kernel, hoặc (b) muốn tự
>   quantize bản LoRA-finetune theo công thức trong PR #22836
>   (`convert_hf_to_gguf.py` → `llama-quantize STQ1_0`) chạy Ở MÁY KHÁC.
> - Hướng Hy-MT2 vẫn sống ở vai trò **teacher offline** (Kaggle/máy nhà) sinh
>   data distill vào model nhỏ — xem lại khi làm vòng v6.

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
