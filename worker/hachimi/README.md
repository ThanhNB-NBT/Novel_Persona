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
cd ~/code/Novel_Project/worker && PYTHONPATH=. python3 hachimi/pipeline/09_gate_rhythm_gold.py
```

| Việc | Lệnh |
|---|---|
| **Kiểm eval khoá + rò rỉ (chạy trước mọi lần đo)** | `PYTHONPATH=. python3 hachimi/eval/run_suite.py check` |
| **Đo một model CT2 trên tập khoá** | `PYTHONPATH=. python3 hachimi/eval/run_suite.py score models/hachimi-ct2` |
| Sinh booster xưng hô + 枪 | `python 07_make_booster_v3.py` |
| Gom pool câu chuỗi phẩy từ DB | `python 08_make_rhythm_pool.py [số dòng]` |
| Chấm bản thầy viết | `python 09_gate_rhythm_gold.py [file.jsonl]` |
| Sàng replay dạy sai nhịp | `python 10_screen_replay_rhythm.py` |
| Nghiệm thu một lô corpus trước khi train | `python 14_gate_corpus.py <lo.jsonl>` |
| Hiệu chỉnh ngưỡng cổng từ lô đã biết là tốt | `python 14_gate_corpus.py <lo.jsonl> --calibrate` |
| Chấm độ căn khớp bằng LaBSE (máy nhà, ~1,8 GB) | `python 15_score_labse.py vao.jsonl ra.jsonl` |
| Dựng cặp train doc-level (bậc 2, ngữ cảnh) | `python 16_make_doclevel.py <chuong.jsonl> <ra.jsonl> --ctx 2` |
| Lắp corpus doc-level trộn kaihe+teacher (bậc 2) | `python 17_build_doclevel_corpus.py` |
| Dựng gói Kaggle v3 | `python prepare_teacher_v3_pack.py` |
| Đo model trên eval khoá | `cd ../eval && python evaluate_hachimi_teacher_v2.py` |
| Đo ảnh hưởng cách chia câu | `cd ../eval && python evaluate_teacher_v2_split.py` |
| Sinh bó DictDis (term đa nghĩa/jargon, contrastive) | `python make_dictdis_probe.py` |
| Train DictDis (vá v5 + replay chống-quên, CPU ~38ph) | `python train_dictdis_probe.py --dictdis-repeat 16 --replay-n 4000 --epochs 2` |
| So 2 model CT2 trên câu DictDis tươi | `python eval_dictdis.py <ct2_A> <ct2_B>` |
| Sinh booster ngày tháng/giờ/số (chặn xáo trộn thứ tự) | `python 21_make_date_booster.py --n 2400` |
| Sinh booster tên nhân vật nhất quán | `python 22_make_name_booster.py --n 800` |
| Lấy câu thành ngữ/phương ngữ từ kaihe để oversample | `python 23_mine_idiom_gold.py --per-term 40` |

Vòng patch 22/08: DictDis bổ sung 班/服/数一数二/十有八九/重塑/黄皮子 (audit 48 chương),
train gộp thêm booster bằng `--extra-jsonl` (mặc định đã trỏ date+name+idiom):
`python train_dictdis_probe.py --dictdis-repeat 12 --replay-n 4000 --epochs 2`
— chạy xong BẮT BUỘC `eval_dictdis.py` + đọc tay chương thật trước khi swap model.

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
6. **DictDis vá term đa nghĩa/jargon (đô thị + võng du) bằng THÊM DATA, không đổi kiến trúc** — và là ngoại lệ của quy tắc 5: nó *vá* lên chính v5, không train lại từ base. Marian 57M tự chọn nghĩa theo cue trong câu (人头→mạng, 输出→sát thương, 秒杀→flash sale, chứ không phải "đầu người/xuất khẩu/giết tức thì"). Trần thực tế ~27 term: `--dictdis-repeat 16 --epochs 2` là BẮT BUỘC (thấp hơn = loãng per-term / sập domain), `--replay-n 4000` giữ giọng tự nhiên; đổi lại prose cứng-nhẹ vài câu là giá cố hữu, và ~3 lỗ vặt (自摸-mạt chược, 隐身-offline, 抓人) đổi chỗ theo seed. Đã đo và bác hướng "model to hơn": NLLB-600M chậm 8× CPU + zero-shot dở hơn (chưa có gu). Luôn `eval_dictdis.py` **và đọc tay chương thật** trước khi deploy; deploy phải copy TRỌN BỘ dir CT2 (bản vá khác v5 cả file phụ), không swap mỗi `model.bin`.
