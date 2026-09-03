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

## Bổ sung 30/08/2026 (vòng v7)

- **Không có lệnh cancel.** `kaggle kernels` chỉ có `delete`. Muốn dừng một kernel đang RUNNING
  mà giữ lại nó thì phải bấm Stop trên web; qua CLI chỉ còn cách `kernels pull -m` sao lưu mã
  rồi `kernels delete` (nhớ `echo y |` vì nó hỏi xác nhận, chạy không TTY sẽ `EOFError`).
- **`datasets create` mặc định `--dir-mode skip`** → **thư mục con bị bỏ qua, KHÔNG báo lỗi**.
  Để mọi file phẳng ở gốc, hoặc `-r zip`.
- **Mặc định nó CHUYỂN file tabular sang CSV** — luôn thêm `-t/--keep-tabular` cho chắc.
- **Zip được giải vào THƯ MỤC TRÙNG TÊN**, không phải ra gốc: `data.zip` → `data/corpus.jsonl`.
  (Bản ghi cũ ở trên chỉ nói "tự giải nén" nên dễ hiểu nhầm là đổ ra gốc.) Kiểm bằng
  `kaggle datasets files <slug>` sau khi status ra `ready`, đừng đoán đường dẫn.

## Bổ sung 01/09/2026 (vòng LaBSE)

- **Kernel KHÔNG được trùng slug với dataset** dù hai thứ khác namespace: `kernels push` với
  `id` = `thnhnguyn003/hachimi-v7-labse` (đang là slug của một dataset) trả **409 Conflict**,
  không kèm lý do. Đặt slug khác (`...-labse-run`) là qua.
- **In cây `/kaggle/input` TRƯỚC mọi `assert`/`raise`.** Lượt 1 chết vì glob
  `/kaggle/input/*/file.py` không khớp, mà phần in chẩn đoán lại đặt SAU `assert` — log chỉ
  còn `AssertionError`, không biết thư mục thật chứa gì, phải push lại một lượt chỉ để nhìn.
  Đây đúng là "lượt đầu để DÒ" ở mục trên, nhưng biết luật mà xếp sai thứ tự thì vẫn dính.
  Và dò file bằng `os.walk` chứ đừng glob cố định độ sâu — zip giải vào thư mục con nên độ
  sâu không đoán được.

## GPU: đếm bằng `device_count()`, và mã phải biết dùng con thứ hai (01/09/2026)

Ba chỗ dính liền nhau, dính đủ cả ba trong một lượt:

**1. Không tra được `machine_shape` cho T4 ×2 — tài liệu Kaggle đã cũ.** Đã kiểm ba nguồn
(01/09):

| nguồn | nói gì |
|---|---|
| Tài liệu CLI chính thức (`Kaggle/kaggle-cli` → `docs/kernels_metadata.md`) | chỉ 3 giá trị: `NvidiaTeslaT4` · `NvidiaTeslaP100` · `Tpu1VmV38`. **Không có bản x2** |
| `kaggle.com/docs/efficient-gpu-usage` | chỉ nhắc **P100**, không nhắc T4 — trang đã lạc hậu |
| UI Notebook (Settings → Accelerator) | `None` · **`GPU T4 ×2`** · `GPU P100` · `TPU v5e-8`; **`GPU T4 ×2` là MẶC ĐỊNH** |

**ĐÃ ĐO 02/09 bằng kernel `hachimi-gpuprobe` (in `torch.cuda.device_count()`):**

| cấu hình metadata | máy nhận được |
|---|---|
| **bỏ trống** `machine_shape`, chỉ `enable_gpu: true` | **P100 · 1 GPU · sm_60** |
| `machine_shape: "NvidiaTeslaT4"` | **T4 ×2 · 2 GPU · sm_75** (14,6 GiB mỗi con) |

⇒ Hai điều chốt được:

1. **`NvidiaTeslaT4` CHÍNH LÀ cỗ T4 ×2** — không có bản T4 đơn. Xin nó là được 2 GPU.
2. **Mặc định của API ≠ mặc định của UI.** UI hiện `GPU T4 ×2`, nhưng qua API bỏ trống trường
   này thì rơi về **P100**, và P100 `sm_60` **không chạy nổi** PyTorch của image (hỗ trợ từ
   `sm_70`): `Tesla P100... is not compatible with the current PyTorch installation`.
   ⇒ **LUÔN đặt `machine_shape` tường minh**, đừng bao giờ để trống.

Mã CLI cũng tự thú nhận không kiểm giá trị này:

```python
# The allowed names are in an enum that is not currently included in kagglesdk.
request.machine_shape = acc if acc else self.get_or_default(meta_data, "machine_shape", None)
```

⇒ Chuỗi được đẩy thẳng lên server, sai tên thì **im lặng rơi về mặc định P100** — tức hỏng
theo đúng kiểu khó đoán nhất. Cờ `kaggle kernels push --accelerator` cũng đặt được trường này.

Kernel dò để lâu: `~/hachimi-work/kg_gpuprobe/` (chạy ~2 phút, gần như không tốn quota).

**2. `torch.cuda.get_device_name(0)` KHÔNG cho biết có mấy GPU.** Nó in tên của GPU số 0, máy
2 con vẫn ra đúng một dòng `Tesla T4`. Đọc log rồi kết luận "chỉ được 1 GPU" là kết luận từ
bằng chứng không đủ. Muốn biết thì in:

```python
print(torch.cuda.device_count(), [torch.cuda.get_device_name(i)
                                  for i in range(torch.cuda.device_count())])
```

Cho vào khối "dò môi trường" của MỌI kernel, cùng chỗ in cây `/kaggle/input`.

**3. Xin 2 GPU vô nghĩa nếu mã chỉ bám `cuda:0`.** `30_labse_filter_corpus.load_model` gọi
`SentenceTransformer(MODEL, device="cuda")` — con thứ hai nằm không. Muốn dùng cả hai phải
đổi sang `start_multi_process_pool()` + `encode_multi_process()` của sentence-transformers.
Đáng sửa trước lần train bản thật (15-30 giờ GPU), không đáng sửa giữa chừng một job đang
chạy: state `--resume` nằm ở `/kaggle/working`, mà thư mục đó bị xoá sạch giữa các lượt
kernel ⇒ huỷ giữa chừng là mất trắng phần đã chạy.
