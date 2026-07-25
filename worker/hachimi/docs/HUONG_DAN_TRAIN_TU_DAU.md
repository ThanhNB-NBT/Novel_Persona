# Hướng dẫn train model từ số 0 — cho người chưa biết gì

> **Cảnh báo (24/07/2026):** tài liệu này chỉ giải thích khái niệm. Không chạy các
> lệnh dùng `train_gold_vnext.jsonl` hoặc cấu hình lặp gold cũ. Kế hoạch có hiệu lực
> nằm ở [`PLAN_VNEXT.md`](PLAN_VNEXT.md); hiện chưa có manifest nào được phép train.

> Viết cho bạn (chưa có kiến thức train model). Đọc tuần tự từ trên xuống.
> Mọi khái niệm đều ví von + gắn với chính dự án dịch truyện này.

---

## PHẦN 1 — Model là gì? Train là gì?

### Model giống một "học sinh dịch thuật"
Hãy tưởng tượng một **học sinh** chuyên làm đúng một việc: đưa nó một câu **tiếng Trung**,
nó viết ra câu **tiếng Việt**. Cái "học sinh" đó chính là **model** (mô hình).

Model của mình tên **HachimiMT-60**. Nó không "hiểu" truyện như người — nó chỉ học được
**thói quen**: "thấy cụm chữ Trung thế này thì viết tiếng Việt thế kia", qua việc xem **rất
nhiều ví dụ**.

### "Tham số" (parameters) = số nếp nhăn trong não học sinh
Model có **57 triệu tham số** (nên tên có số "60", làm tròn 57→60 triệu). Tham số giống
**số kết nối trong não** học sinh:
- Nhiều tham số → học sinh "thông minh" hơn, dịch câu khó tốt hơn — NHƯNG **nặng và chậm** hơn.
- Ít tham số → nhẹ, nhanh, chạy được trên máy yếu (VPS 2 nhân của mình) — nhưng có **trần**:
  câu quá phức tạp thì đuối.

57 triệu là **cỡ nhỏ** (các model như ChatGPT là hàng trăm **tỷ**). Mình chọn nhỏ vì phải
chạy nhanh trên VPS yếu, chấp nhận đánh đổi.

### "Train" = cho học sinh làm thật nhiều bài mẫu
**Train (huấn luyện)** nghĩa là: đưa cho học sinh **hàng trăm nghìn cặp bài mẫu**, mỗi cặp gồm
_(câu tiếng Trung → câu tiếng Việt ĐÚNG)_. Học sinh xem đi xem lại, tự chỉnh "não" (tham số)
cho tới khi nó tự dịch giống đáp án. Xong, nó dịch được cả những câu **chưa từng thấy**.

- **Dataset (bộ dữ liệu)** = **cuốn sách bài tập** chứa các cặp mẫu đó.
- **Token** = "mẩu chữ" nhỏ nhất model đọc (gần như: một tiếng/một âm). Không cần quan tâm sâu.
- **Epoch** = học sinh **đọc trọn cuốn sách bài tập MỘT lượt**. Train "3 epoch" = bắt nó đọc
  cả cuốn **3 lần** cho ngấm. (Đọc quá nhiều lần lại thành "học vẹt" — nên thường 3 lần là đủ.)

---

## PHẦN 2 — "Finetune" khác "train từ đầu" thế nào?

Đây là chỗ quan trọng nhất cho dự án của mình.

- **Train từ đầu (from scratch)**: học sinh **chưa biết gì**, dạy từ con số 0. Rất tốn kém
  (cần hàng triệu bài + máy khủng). Mình **KHÔNG** làm cái này.
- **Finetune (tinh chỉnh)**: học sinh **ĐÃ biết dịch rồi** (model HachimiMT-60 có sẵn, người
  ta đã train trên ~350.000 cặp mẫu). Mình chỉ **dạy thêm vài buổi** để **sửa TẬT XẤU cụ thể**,
  không dạy lại từ đầu.

**Tật xấu mình muốn sửa lần này**: trong lời kể, học sinh hay viết **"tôi / mình / cậu"** (giọng
hiện đại), trong khi truyện tiên hiệp phải là **"ta / hắn / nàng"** (giọng cổ phong). Đo được:
**~20% số chương bị lỗi này**.

→ Finetune = giữ nguyên khả năng dịch đã có, chỉ **nắn lại thói quen xưng hô**.

---

## PHẦN 3 — Thầy giỏi dạy trò: "distillation"

Học sinh nhỏ (57 triệu) tự nó không biết câu nào đúng chuẩn. Nên mình cần **THẦY** — một model
**giỏi hơn nhiều** — viết sẵn **đáp án đúng**, rồi học sinh nhỏ **bắt chước**. Cách này gọi là
**distillation (chưng cất tri thức)**: rót cái hay của thầy lớn vào trò nhỏ.

Trong dự án:
- Thầy tạo ra bộ mẫu gốc (~350k cặp) là **Gemini** (model lớn của Google).
- Lần finetune này, thầy sửa các câu lỗi xưng hô là **Codex (GPT-5.6)** — mình đã nhờ nó dịch
  lại 660 câu cho đúng "ta/hắn/nàng".

---

## PHẦN 4 — Bộ dữ liệu train của mình gồm những gì?

Cuốn "sách bài tập" cho lần finetune này (`train_gold_vnext.jsonl`, 8060 cặp) trộn 3 loại +
1 nguồn tải riêng:

| Tên | Là gì (ví von) | Số lượng | Vai trò |
|---|---|---|---|
| **Gold cổ phong** | Bài mẫu "chuẩn vàng" đã duyệt tay từ trước | 5000 | Giữ giọng văn hay |
| **Gold register** | 660 câu Codex sửa lỗi xưng hô | 660 | Dạy đúng ta/hắn/nàng |
| **Booster** | Bài **luyện tập tự chế** cho đúng tật (他→hắn, 我→ta...) | 1200 | Tăng "liều" cho đủ ngấm |
| **Replay** | Đọc lại bài CŨ (698k cặp Gemini) | tải từ mạng | **Chống quên** |

Giải thích 2 cái lạ:

- **Gold** (vàng) = bài mẫu **chất lượng cao nhất**, nên cho học sinh **học lại nhiều lần**
  (`--gold-repeat 5` = mỗi câu gold lặp 5 lần). Bài thường học 1 lần, bài vàng học 5 lần.
- **Replay** (đọc lại) = nếu chỉ cho học sinh học bài MỚI về xưng hô, nó có thể **quên** cách
  dịch bình thường ("học cái này quên cái kia"). Nên mình trộn lại **bài cũ** để nó **ôn**,
  giữ nguyên phong độ. Đây là lý do bộ train có tới mấy chục nghìn dòng dù bài mới chỉ ~2000.

- **Booster** = tại sao cần? Vì 660 câu gold **quá ít** so với 698k bài ôn (0,5%) → tín hiệu
  "sửa xưng hô" bị loãng, học sinh không đủ ngấm. Nên mình **tự chế thêm 1200 câu** đơn giản
  mà chắc đúng (他握紧双拳。→ Hắn siết chặt song quyền.) để "tăng liều".

---

## PHẦN 5 — "Gate" (bộ lọc) và tại sao có nó

Vấn đề: chính **698k bài ôn (replay)** cũng **lẫn** những câu dùng sai "tôi/mình" (vì thầy
Gemini hồi đó không bị bắt buộc luật cổ phong). Nếu bắt học sinh ôn cả những câu sai đó → **vừa
dạy đúng vừa dạy sai**, công cốc.

→ Mình thêm **register-gate** = **bộ lọc** đọc từng câu ôn, **vứt bỏ** câu nào lời kể có
"tôi/mình/cô ta". Chỉ cho học sinh ôn bài SẠCH.

(Đây đúng bài học từ lần train cũ "v2": không lọc → model vẫn lọt "tôi". Nên lần này bắt buộc lọc.)

---

## PHẦN 6 — Máy để train: tại sao lên Kaggle?

Train cần làm **cực nhiều phép tính** cùng lúc → cần **GPU** (card đồ hoạ, chuyên tính song song,
mạnh hơn CPU thường hàng chục lần cho việc này). Máy bạn / VPS **không có GPU đủ mạnh**.

**Kaggle** = trang của Google cho **dùng GPU miễn phí** (có giới hạn giờ). Mình:
1. Đưa "sách bài tập" + script train lên Kaggle (đã làm — dataset `hachimi-cophong`).
2. Bật **GPU T4 × 2** (T4 = tên loại GPU; ×2 = hai cái chạy song song cho nhanh).
3. Bấm chạy → Kaggle train hộ → trả về model đã finetune.

**`--export-ct2`** = sau khi train xong, **đóng gói model sang định dạng CT2** — bản nén gọn,
chạy nhanh trên CPU (để mang về VPS chạy). Giống xuất file "bản rút gọn để chạy máy yếu".

---

## PHẦN 7 — Chạy trên Kaggle (các bước thực tế)

**Cell 1 — cài thư viện** (đã chạy; mấy dòng đỏ "conflict" là của gói Kaggle khác, kệ nó):
```bash
pip -q install "transformers==4.48.3" "datasets==3.3.2" "accelerate==1.3.0" sentencepiece ctranslate2
```

**Cell 2 — nạp chìa khoá tải bài ôn** (giải thích ở Phần 8):
```python
import os
from kaggle_secrets import UserSecretsClient
os.environ["HF_TOKEN"] = UserSecretsClient().get_secret("HF_TOKEN")
print("HF_TOKEN:", bool(os.environ.get("HF_TOKEN")))
```

**Cell 3 — train**:
```bash
!accelerate launch --num_processes=2 --multi_gpu \
  /kaggle/input/datasets/thnhnguyn003/hachimi-cophong/kaggle_train.py \
  --gold /kaggle/input/datasets/thnhnguyn003/hachimi-cophong/train_gold_vnext.jsonl \
  --extra-replay /kaggle/input/datasets/thnhnguyn003/hachimi-cophong/train_v2.jsonl \
  --extra-replay-limit 20000 \
  --pro-limit 8000 --replay-limit 22000 \
  --output-dir /kaggle/working/hachimi-vnext --export-ct2
```

Điều kiện: bật **Internet** + **GPU T4×2** (menu Settings bên phải), và **Attach** secret HF_TOKEN.

Train xong: vào **Output → /kaggle/working/hachimi-vnext**, tải về, giải nén vào
`worker/models/hachimi-ct2/`, rồi copy lên VPS (như quy trình cũ).

---

## PHẦN 8 — Giải thích cái LỖI bạn vừa gặp (dễ hiểu)

Lỗi: `RuntimeError: Chỉ lấy được 8496/9000 hàng Pro từ corpus gốc`.

- Bộ 698k bài ôn chia 2 hạng: **"pro"** (hạng xịn nhất) và **"replay"** (hạng thường).
- Hạng **"pro" chỉ có sẵn khoảng 9000 bài** — không hơn.
- Script được đặt mặc định: "lấy cho tôi **đúng 9000** bài pro, thiếu 1 bài cũng BÁO LỖI dừng".
- **Bộ lọc gate** (Phần 5) vứt đi ~504 bài pro dùng sai "tôi/mình" → chỉ còn **8496** bài pro sạch.
- 8496 < 9000 → script thấy "thiếu" → **dừng và báo lỗi**.

**Cách sửa**: bảo script "lấy **8000** bài pro thôi" (`--pro-limit 8000`) → 8496 sạch ≥ 8000 →
đủ, không lỗi nữa. Không mất mát gì đáng kể (8000 bài pro vẫn quá thừa).

Nói ngắn: **bộ lọc làm ít bài đi một chút, mà script lại đòi con số cứng cũ → hạ con số đòi hỏi
xuống là xong.**

---

## PHẦN 9 — Sau khi train xong thì làm gì?

1. **Đo (eval)**: dịch thử vài trăm câu bằng model MỚI, **đếm còn lọt "tôi/mình" không**. Nếu
   giảm mạnh so với model cũ → thành công. (Không dùng điểm số máy móc "chrF" vì nó cùn với
   việc này — mình đếm lỗi trực tiếp.)
2. **Deploy**: copy model CT2 mới lên VPS, khởi động lại worker → từ đó truyện dịch bằng bản mới.
3. Nếu muốn, **dịch lại kho** để các chương cũ hưởng bản mới (chạy nền, vài ngày).

---

## Bảng tra nhanh thuật ngữ

| Từ | Nghĩa dễ hiểu |
|---|---|
| Model | "Học sinh" dịch Trung→Việt |
| Tham số (parameters) | Số "nếp nhăn não" — nhiều = giỏi + nặng |
| Train | Cho học sinh làm thật nhiều bài mẫu để học thói quen |
| Dataset | Cuốn sách bài tập (các cặp Trung→Việt) |
| Epoch | Đọc trọn cuốn sách 1 lượt (mình đọc 3 lượt) |
| Finetune | Dạy THÊM để sửa tật, không dạy lại từ đầu |
| Distillation | Thầy giỏi viết đáp án, trò nhỏ bắt chước |
| Gold | Bài mẫu "chuẩn vàng", cho học nhiều lần |
| Replay | Ôn lại bài cũ để không quên |
| Booster | Bài luyện tự chế cho đúng tật |
| Gate | Bộ lọc, vứt bài mẫu sai trước khi học |
| GPU | Card mạnh chuyên tính toán train |
| Kaggle | Nơi cho dùng GPU miễn phí |
| CT2 / export-ct2 | Đóng gói model thành bản gọn, chạy nhanh trên CPU/VPS |
| pro-limit / replay-limit | Số bài ôn mỗi hạng lấy vào — hạ xuống nếu gate cắt nhiều |
