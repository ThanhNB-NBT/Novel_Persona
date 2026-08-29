# Train trên Kaggle bằng CLI — sổ tay (dựng 29-30/08/2026)

> **Trước hết: có cần Kaggle không?** Finetune Hachimi (57M) chạy **3,2 giờ trên máy dev CPU**,
> không cần GPU. Kaggle chỉ đáng dùng cho **train from scratch** (15-30 giờ).
> Xem `docs/ban-giao-2026-08-30.md`.

## Chuẩn bị một lần

```bash
uv tool install kaggle          # không cần sudo
```

Token: kaggle.com → Settings → API → *Create New API Token*. Bản mới lưu ở
**`~/.kaggle/access_token`** (một dòng, KHÔNG phải `kaggle.json` như tài liệu cũ):

```bash
mkdir -p ~/.kaggle && echo "KGAT_xxx" > ~/.kaggle/access_token && chmod 600 ~/.kaggle/access_token
kaggle competitions list          # kiểm đã thông
```

## Đẩy dataset

```bash
# thư mục chứa data + dataset-metadata.json
kaggle datasets create  -p <dir> -q                       # lần đầu
kaggle datasets version -p <dir> -m "mo ta" -q            # lần sau
kaggle datasets status thnhnguyn003/<slug>                # đợi tới khi in "ready"
```

`dataset-metadata.json`:
```json
{"title": "hachimi-teacher-v6", "id": "thnhnguyn003/hachimi-teacher-v6",
 "licenses": [{"name": "other"}]}
```

⚠ **Kaggle TỰ GIẢI NÉN file .zip** khi tạo dataset → trong kernel không có `.zip` nào, chỉ có
file rời. Và nó mount ở **`/kaggle/input/datasets/<user>/<slug>`**, không phải
`/kaggle/input/<slug>`. Cách chắc nhất là dò đệ quy tìm một file mốc:

```python
for root, dirs, files in os.walk("/kaggle/input"):
    if "kaggle_train.py" in files:
        SRC = root; break
```

⚠ Push kernel **sau khi** dataset in `ready`, nếu không kernel bắt version cũ (hoặc không thấy
dataset) và lỗi rất khó đoán.

## Đẩy kernel

```bash
kaggle kernels push   -p <dir>                    # dir chứa train.py + kernel-metadata.json
kaggle kernels status thnhnguyn003/<slug>         # RUNNING / COMPLETE / ERROR
kaggle kernels output thnhnguyn003/<slug> -p <đích> --force
kaggle kernels pull   thnhnguyn003/<slug> -p <đích> -m
```

`kernel-metadata.json`:
```json
{
  "id": "thnhnguyn003/hachimi-v6-train",
  "title": "hachimi-v6-train",
  "code_file": "train.py",
  "language": "python",
  "kernel_type": "script",
  "is_private": true,
  "enable_gpu": true,
  "enable_internet": true,
  "machine_shape": "NvidiaTeslaT4",
  "dataset_sources": ["thnhnguyn003/hachimi-teacher-v6"],
  "competition_sources": [], "kernel_sources": [], "model_sources": []
}
```

⚠ **`machine_shape` phải đúng tên**: `NvidiaTeslaT4`, `NvidiaTeslaP100`, `Tpu1VmV38`.
Đặt sai (ví dụ `"gpu_t4x2"`) thì Kaggle im lặng rơi về mặc định **P100** — mà tài liệu của
chính Kaggle ghi **P100 KHÔNG tương thích image mặc định**, gây
`CUDA error: no kernel image is available for execution on the device`.
`kernel_type: "notebook"` + file `.ipynb` cũng push được nếu muốn chạy theo cell.

Log chỉ tải về được khi kernel đã kết thúc; đang RUNNING thì `kernels output` trả log của
lượt trước — dễ tưởng nhầm là lỗi cũ tái diễn.

## Công thức môi trường (đã chạy được)

Image Kaggle 8/2026: `torch 2.10.0+cu128`, `transformers 5.x`, `huggingface-hub 1.11`,
`tokenizers 0.22`. Script của dự án viết cho `transformers 4.48` → phải chỉnh:

```python
# 1) KHOÁ torch — cài đè torch là mất kernel GPU, đây là lỗi tốn nhiều lượt nhất
Path("/kaggle/working/constraints.txt").write_text(f"torch=={torch.__version__}\n")
# 2) để pip TỰ giải phụ thuộc (vá từng gói là vòng luẩn quẩn:
#    transformers → tokenizers → safetensors → ...)
# 3) ghim <5: transformers 5.x bỏ `warmup_ratio` khỏi Seq2SeqTrainingArguments
pip install -U "transformers<5" -c /kaggle/working/constraints.txt
```

**Đừng** dùng `--no-deps` để né torch: nó chỉ đẩy xung đột sang gói khác.
Và **đừng** gọi `importlib.reload(torch)` để xem phiên bản sau khi cài — nó đăng ký lại
namespace triton rồi nổ; hỏi qua một tiến trình con là xong.

## Dataset gated

`kaggle_train.load_replay` vốn stream `ngocdang83/tran-vi-teacher` từ HF — bộ đó **gated**, mà
kernel Kaggle không có token HF → chết ngay. Đã thêm `--teacher-jsonl <file>` để đọc bản tải
sẵn (đóng gói luôn vào dataset). Khỏi mạng, khỏi secret.

Nếu vẫn muốn dùng token HF trên Kaggle: **secret chỉ thêm được qua giao diện web**
(Add-ons → Secrets), API không làm được.

## Bài học lớn nhất

**Môi trường lạ thì lượt đầu để DÒ, không phải để làm việc.** Mất 9 lượt push (mỗi lượt chờ
8-10 phút) vì vá từng lỗi một. Lượt đầu đáng lẽ in hết: phiên bản torch/transformers/
tokenizers/hub, `torch.cuda.get_device_name()`, thử `import`, thử dựng
`Seq2SeqTrainingArguments(**options)` — một lượt là biết đủ để sửa trọn gói.
