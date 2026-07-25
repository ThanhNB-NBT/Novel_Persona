# Hachimi — finetune, dữ liệu và đánh giá

Trước 25/07 thứ này nằm rải ở ba nơi (`hachimi_finetune/`, `experiments/`,
`teacher_build_20260725/`) với 2,5 GB checkpoint chết. Giờ tất cả ở đây.

Model production KHÔNG nằm trong thư mục này — nó ở `worker/models/hachimi-ct2/`.

## Bản đồ

| Thư mục | Chứa gì |
|---|---|
| `pipeline/` | Script còn chạy: sinh data → cổng nghiệm thu → dựng gói Kaggle. Phải nằm chung một thư mục vì import lẫn nhau. |
| `data/gold/` | Cặp ZH-VI vào slot gold (lặp 3 lần khi train). |
| `data/replay/` | Replay teacher Gemini, bản gốc và bản đã sàng nhịp câu. |
| `data/eval_locked/` | Ba tập eval đã khoá. **Không bao giờ đưa vào train** — cổng `assert_no_leakage` sẽ chặn. |
| `data/source/` | Nguyên liệu thô: pool nhịp câu, bản thầy viết, bản bị cổng loại. |
| `eval/` | Harness đo model + corpus longform + báo cáo mới nhất. |
| `packs/` | Gói zip upload lên Kaggle. |
| `docs/` | Kế hoạch, nghiên cứu, hướng dẫn train từ đầu. |
| `archive/` | Kết luận các vòng đã chốt và script chỉ chạy một lần. Không sửa, chỉ tra cứu. |

## Chạy gì, khi nào

Mọi lệnh cần `PYTHONPATH` trỏ vào `worker/` (để import `novelworker`):

```bash
cd E:/Novel_Project/worker/hachimi/pipeline && PYTHONPATH=E:/Novel_Project/worker python 09_gate_rhythm_gold.py
```

| Việc | Lệnh |
|---|---|
| Sinh booster xưng hô + 枪 | `python 07_make_booster_v3.py` |
| Gom pool câu chuỗi phẩy từ DB | `python 08_make_rhythm_pool.py [số dòng]` |
| Chấm bản thầy viết | `python 09_gate_rhythm_gold.py [file.jsonl]` |
| Sàng replay dạy sai nhịp | `python 10_screen_replay_rhythm.py` |
| Dựng gói Kaggle v3 | `python prepare_teacher_v3_pack.py` |
| Đo model trên eval khoá | `cd ../eval && python evaluate_hachimi_teacher_v2.py` |
| Đo ảnh hưởng cách chia câu | `cd ../eval && python evaluate_teacher_v2_split.py` |

Mỗi script pipeline có `--self-check` chạy trong một giây; chạy nó trước khi tin kết quả.

## Quy tắc đã trả giá mới có

1. **Thầy dịch sẽ tối ưu đúng cái cổng đo được.** Codex từng thay máy móc `", "` → `" . "`
   để qua cổng đếm câu, và thay mù `cậu` → `ngươi` để né cổng xưng hô ("một ngươi bé").
   Luôn đọc tay vài chục dòng mỗi lô, đừng tin số của cổng một mình.
2. **Ngưỡng của cổng phải hiệu chỉnh từ dữ liệu tham chiếu**, không được bịa: xem
   `docs/hachimi_rhythm_research.md`.
3. **Giao lô nhỏ**: một phiên thầy 100 dòng thì tốt, 500 dòng thì nó copy bản cũ cho gần
   nửa lô. Chạy nhiều phiên song song, mỗi phiên một shard riêng.
4. **Ghi tiếng Việt bằng Python `ensure_ascii=True`**, đừng đẩy qua dòng lệnh PowerShell.
5. Mỗi vòng train đi từ base `ngocdang83/HachimiMT-60-zh-vi`, không chồng lớp lên vòng trước.
