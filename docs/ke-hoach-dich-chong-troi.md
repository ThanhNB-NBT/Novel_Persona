# Kế hoạch chống "trượt chất lượng" khi dịch nhiều chương

**Ngày lập:** 2026-07-15
**Vấn đề:** chất lượng dịch ổn ở các chương đầu, trượt dần khi dịch sâu vào truyện.
**Phạm vi:** `worker/novelworker/translator/`, glossary trong Supabase, evaluator. Không đổi model, không fine-tune, không thêm hạ tầng.
**Quan hệ với `toi-uu-worker.md`:** kế thừa các quyết định đã chốt (within-chunk constraint, không relationship memory, model pin, quality fuse). File này chỉ giải MỘT bài: vì sao chương 100 tệ hơn chương 5, và chặn từng đường trôi.

---

## 1. Chẩn đoán: 4 đường trôi trong pipeline hiện tại

Model KHÔNG "mệt dần" — mỗi chương là một request độc lập. Cái trôi là **trạng thái tích lũy** giữa các chương. Soi code hiện tại thấy 4 đường:

### D1 — Glossary phình một chiều, không có dọn rác (nghi phạm số 1)

- Mỗi chunk, `_analyze_names` + `GLOSSARY_JSON` đẻ suggestion (`approved=false`), `get_glossary` load TẤT CẢ (duyệt + gợi ý) và inject vào prompt bất cứ khi nào term_zh xuất hiện. Thực đo n1380: **270 term sau 122 chương** và còn tăng.
- *Đã có sẵn (migration 063, đừng làm lại):* `unique (novel_id, term_zh)`, upsert `ignore_duplicates` (first-win ở tầng insert), `get_glossary` ưu tiên approved > gợi ý cũ nhất. Comment "bảng không có unique constraint" trong `worker.py` là comment CŨ — nên xoá cho khỏi lừa người sau.
- Lỗ hổng còn thật: **first-win khoá cứng bản ĐẦU TIÊN kể cả khi nó sai**. Suggestion sai (phiên âm sai, giới tính sai trong `note`, danh từ chung nhận nhầm thành tên riêng) lọt vào từ chương nào là sống vĩnh viễn từ chương đó; suggestion sau mâu thuẫn bị **lặng lẽ vứt** (`ignore_duplicates`) — không ai biết từng có xung đột để duyệt lại. Glossary là bộ nhớ duy nhất tích lũy vô hạn, chỉ có cửa vào không có cửa kiểm → entropy chỉ tăng. Đây đúng nghĩa "chương đầu ổn (glossary sạch/rỗng), chương sau trượt (glossary bẩn dần)".

### D2 — Chuỗi SUMMARY = trò "tam sao thất bản"

- `prev_summary` là dòng SUMMARY do **model tự viết** ở chương trước, chương sau lại viết summary mới trong khi đang đọc summary cũ → lỗi nhỏ (sai tên, sai quan hệ, sai sự kiện) khuếch đại dần. Văn liệu gọi đây là *iterative generation drift / broken telephone* — đúng cơ chế mà nghiên cứu về sinh truyện dài và dịch tài liệu dài đã chỉ ra.
- SUMMARY không có ràng buộc gì: không giới hạn độ dài, không bắt dùng tên theo glossary, không validate. Một summary lạc đề ở chương 40 → chương 41 dịch với ngữ cảnh sai.
- Chương dịch lại lẻ (audit requeue) lấy summary của bản dịch cũ có thể đã hỏng.

### D3 — `prev_tail` lây giọng bẩn

- Đuôi 350 ký tự của bản dịch chương trước được đưa vào prompt "nối tiếp đúng giọng văn". Nếu chương trước dính convertese/xưng hô sai (lint hiện chỉ cảnh báo, không chặn), chương sau được **lệnh bắt chước** đúng cái sai đó. Trôi giọng có tính lây lan một chiều.

### D4 — Style bible sinh từ chương "bất kỳ được dịch đầu tiên"

- `_init_style_bible` chạy ở chương đầu tiên ĐƯỢC DỊCH, không phải chương 1 (đã lưu `src_chapter` nhưng chưa có gì dùng nó). Truyện dịch từ giữa (user nhảy chương) mang style bible kém đại diện suốt đời.
- Ngoài ra: không ai ĐO trượt. Lint chỉ chạy khi gọi eval thủ công; production không lưu điểm lint theo chương → trượt dần là cảm nhận của người đọc, không có đường trend để bắt sớm.

## 2. Đối chiếu nghiên cứu (repo + paper, 2026-07-15)

Điểm chung của các hệ dịch/viết truyện dài làm tốt:

| Nguồn | Cơ chế chống trôi | Bài học cho repo |
|:--|:--|:--|
| [Loong (arXiv 2605.30274)](https://arxiv.org/html/2605.30274) — agent dịch tài liệu dài | 3 loại memory: Essence (tóm tắt toàn cục), Exemplars (cặp câu đã dịch), Entities (glossary có thuộc tính); **retrieval có trần cố định** (top-4) thay vì tích lũy vô hạn; lọc nhiễu chủ động trước khi đưa vào context | Trần + chọn lọc + LỌC RÁC memory quan trọng hơn thêm memory. Repo đã có trần (80 term) nhưng chưa có lọc rác |
| [DOME (NAACL 2025)](https://aclanthology.org/2025.naacl-long.63.pdf), [Lost in Stories (arXiv 2603.05890)](https://arxiv.org/html/2603.05890v1) — sinh truyện dài | Trôi dài hạn đến từ memory bẩn + xung đột ngữ cảnh; cần phát hiện **mâu thuẫn** giữa fact mới và memory cũ thay vì ghi đè tự do | Suggestion mới mâu thuẫn với term đã dùng nhiều chương → không được im lặng ghi thêm |
| [NexusSum (arXiv 2505.24575)](https://arxiv.org/html/2505.24575v1) — tóm tắt truyện dài | Tóm tắt phân tầng, nén định kỳ có kiểm soát thay vì chuỗi tóm tắt nối đuôi | Rolling synopsis nén mỗi K chương thay vì chain summary từng chương |
| [GalTransl](https://github.com/GalTransl/GalTransl), [LLM Novel Translator](https://github.com/qw02/llm-novel-translator), [noveltrans](https://github.com/YuBing-link/noveltrans) — repo dịch truyện/galgame | GPT dictionary chọn lọc theo đoạn (repo đã học); noveltrans: pipeline **entity consistency** đối chiếu glossary người dùng, glossary user luôn thắng máy | Phân cấp niềm tin: term user duyệt > term máy dùng lâu > suggestion mới |
| [Refinement study (arXiv 2605.13368)](https://arxiv.org/pdf/2605.13368), [WMT23 literary (aclanthology 2023.wmt-1.41)](https://aclanthology.org/2023.wmt-1.41/) | Refine mù không cải thiện fidelity; lỗi nghĩa cần constraint cụ thể + câu nguồn | Khớp hướng repo đã đi (targeted revise, không self-reflection chung) — giữ nguyên |

Kết luận: **không cần thêm cơ chế mới nào to** (không vector DB, không agent). Cần làm sạch và chặn trôi ở 4 đường D1–D4, toàn bộ bằng Python + SQL sẵn có.

## 3. Kế hoạch — 5 gói, xếp theo tác động/công sức

### G1 — Vệ sinh glossary (D1, ưu tiên cao nhất)

*(Dedupe + unique + first-win insert + ưu tiên approved khi load: ĐÃ CÓ từ migration 063 — phần dưới chỉ là cái còn thiếu.)*

1. **Migration** (số kế tiếp trong `supabase/migrations/`): thêm cột `first_chapter int`, `hit_count int default 0`, `conflict_vi text` vào `glossary_terms`.
2. **Lộ xung đột thay vì lặng lẽ vứt:** suggestion mới trùng term_zh nhưng khác `correct_vi` → ghi `conflict_vi` (kèm chương phát hiện) để màn Thuật ngữ hiện cho user chọn; term đang dùng không tự đổi. `approved=true` bất khả xâm phạm (giữ như hiện nay). Xoá comment cũ sai về unique constraint trong `worker.py`.
3. **Lọc rác đầu vào** (trước khi insert suggestion — hiện `_valid_suggested_zh` chỉ chặn rác hiển nhiên):
   - Loại term 1 chữ Hán thuộc danh sách chữ phổ thông (đại từ, hư từ); loại term là từ phổ thông thuần (đối chiếu: nếu `hanviet.han_viet(zh)` khác xa `vi` VÀ type=other VÀ không viết hoa → nghi từ chung, bỏ).
   - `reconcile` đã có — thêm: person/place/sect mà `vi` không qua được reconcile ở mức "cố phiên âm" thì hạ xuống `note='nghi sai'`, không inject vào prompt cho tới khi user duyệt.
4. **Ưu tiên khi inject** (`_build_glossary_block`): thứ tự hiện tại (approved trước, gợi ý theo created_at) đã hợp lý; chỉ bổ sung `hit_count desc` trong nhóm gợi ý để khi chạm trần 80, cái bị rơi là term ít gặp chứ không phải tên nhân vật chính.

**Gate:** dịch lại 10 chương giữa truyện n1380 (chương 100+) — tên nhân vật/thuật ngữ khớp 100% với 50 chương đầu; số term trong DB ngừng tăng tuyến tính theo chương.

### G2 — Chặn tam sao thất bản của SUMMARY (D2)

1. **Ràng buộc SUMMARY trong prompt:** tối đa 2–3 câu, CHỈ sự kiện + trạng thái nhân vật cuối chương, tên riêng phải theo glossary, không bình luận. Validate máy: dài quá 400 ký tự → cắt; chứa chữ Hán → bỏ (dùng summary chương trước).
2. **Rolling synopsis theo truyện** (`novels.synopsis_vi`, migration cùng đợt G1): mỗi 10 chương, MỘT lượt LLM nén `synopsis cũ + 10 summary gần nhất` thành synopsis ≤600 ký tự. Prompt dịch inject `[Bối cảnh truyện đến nay: synopsis]` + `[Chương trước: prev_summary]`. Chain lỗi ở một chương không còn phá cả chuỗi — synopsis được nén lại từ nhiều nguồn, sai lẻ bị pha loãng thay vì khuếch đại.
3. Chương dịch lại lẻ (audit requeue): dùng synopsis + summary của chương N-1 hiện có như cũ, nhưng **không ghi đè** summary chuỗi nếu chương đó cũ hơn watermark hiện tại (tránh summary bản dịch lại đè lệch chuỗi).

**Gate:** dịch liên tiếp 15 chương corpus n1380 c50–64, summary chương 64 vẫn đúng tên + sự kiện khi đối chiếu tay với bản zh.

### G3 — prev_tail chỉ lấy từ bản sạch (D3)

- Sau khi chương dịch xong, chạy lint nhanh (tái dùng rule của `eval_translation.py`, thuần regex, 0 LLM call) → lưu `chapters.lint_score int` (0 = sạch).
- `_tail()` chỉ trả đuôi khi `lint_score` của chương trước ≤ ngưỡng (vd ≤2); bẩn hơn → bỏ tail, chỉ dùng summary. Mất chút mượt nối chương còn hơn ra lệnh cho model bắt chước văn bẩn.

**Gate:** không còn ca "chương N sạch nhưng chương N+1 lặp đúng tật của chương N-1".

### G4 — Style bible đúng nguồn + tái tạo (D4)

- `src_chapter > 1` và chương 1 đã có `content_zh` → tái tạo style bible từ chương 1 (một lần, khi housekeeping rảnh). Đã có sẵn `src_chapter` từ trước — giờ mới dùng.
- User sửa style trong DB/app → worker không đụng (đã đúng, giữ).
- **Lưu ý cho form sửa style trong app (chưa có, 2026-07-15):** khi làm form cho user sửa `novels.translation_style` thủ công, PHẢI xoá key `src_chapter` khỏi JSON trước khi update lên Supabase. Nếu giữ lại `src_chapter > 1`, housekeeping (`_refresh_one_style_bible` trong `worker.py`) sẽ tái tạo style bible từ chương 1 và đè mất bản user sửa tay.

### G5 — Nhìn thấy trượt: trend lint theo chương

- `lint_score` (G3) + `model_used` đã có → RPC nhỏ trả trung bình lint theo bucket 10 chương cho một truyện; vẽ ở màn admin hoặc chỉ cần query tay lúc đầu.
- Audit định kỳ thêm điều kiện: bucket sau tệ hơn bucket trước ≥X → log cảnh báo "truyện N đang trượt" thay vì đợi người đọc phát hiện.

**Gate tổng (định nghĩa "xịn, ổn áp"):** trên corpus 65 chương hiện có + 15 chương mới giữa truyện: (a) 0 hard-fail (Hán sót/cụt/mất đoạn/phiên âm nguyên chương), (b) lint trung bình bucket chương 100+ KHÔNG tệ hơn bucket chương 1–10 quá 20%, (c) tên riêng nhất quán 100% giữa chương đầu và chương sâu, (d) người đọc thật xác nhận đọc liền mạch 10 chương liên tiếp không vấp lỗi xưng hô/tên.

## 4. Thứ tự làm và ước lượng

| Bước | Gói | Đụng file | Ghi chú |
|:--|:--|:--|:--|
| 1 | G1.1–G1.2 migration cột mới + lộ xung đột | migration mới, `worker.py`, `db.py` | Nền của mọi thứ; user push migration |
| 2 | G1.3–G1.4 lọc rác + hit_count sort | `worker.py`, `prompts.py`, `hanviet.py` | Kèm regression test |
| 3 | G3 lint_score + tail gating | `worker.py`, tách rule lint ra module dùng chung | Rẻ, hiệu quả ngay |
| 4 | G2 summary constraint + rolling synopsis | `prompts.py`, `worker.py`, migration (cột synopsis_vi, gộp với bước 1) | +1 call/10 chương |
| 5 | G4 style bible từ chương 1 | `worker.py` housekeeping | Nhỏ |
| 6 | G5 trend + cảnh báo | RPC/SQL, `worker.py` audit | Sau cùng |
| 7 | Đo gate tổng trên corpus | `eval_translation.py` | User chạy `--fresh` (agent bị chặn gửi corpus ra NVIDIA) |

Không làm: vector DB, relationship memory (đã gỡ ở §14.13 — không khôi phục), fine-tune, model local, exemplar retrieval (chỉ xét sau khi G1–G3 chạy mà giọng vẫn trôi — khi đó lấy 2–3 đoạn user đã duyệt của chính truyện đó làm few-shot, không cần embedding).

## 5. Kiểm thử & đánh giá chất lượng — 3 tầng, đo TRƯỚC/SAU từng bước

Không có tầng nào ở đây phải xây mới từ đầu — tận dụng hạ tầng test/eval sẵn có, chỉ thêm case cho phần code mới.

### Tầng 1 — Regression tự động (chạy sau MỖI bước code, 0 API call)

```powershell
$env:PYTHONIOENCODING='utf-8'
E:\Novel_Project\.venv\Scripts\python.exe -m py_compile <file đã sửa>
E:\Novel_Project\.venv\Scripts\python.exe -m pytest worker\test
```

Test mới bắt buộc kèm theo từng gói:
- G1: xung đột ghi vào `conflict_vi` chứ không đổi term đang dùng; bộ lọc rác KHÔNG giết term hợp lệ (tên 1 chữ như 朕 vẫn qua nếu là person, danh từ chung bị chặn); sort `hit_count` không đẩy term approved ra khỏi trần 80.
- G2: SUMMARY quá dài/chứa Hán bị loại đúng cách; synopsis nén giữ tên theo glossary; chương requeue không ghi đè summary mới hơn watermark.
- G3: `lint_score` tính đúng trên bản đã strip meta; tail bị bỏ khi chương trước bẩn, giữ khi sạch.

### Tầng 2 — Eval máy trên corpus cố định (trước/sau MỖI gói, so số với baseline)

Corpus 65 chương (`worker/corpus_translation/`, §14.14 toi-uu-worker.md) đã có **baseline: 65 cảnh báo, trong đó 4 mất tự xưng**. Quy trình mỗi gói:

```powershell
cd E:\Novel_Project\worker
python eval_translation.py --fresh 65 --from-dir corpus_translation --out eval_out_g<N>
```

- `--fresh` dịch MỚI bằng pipeline sau thay đổi → so `index.html` với baseline: tổng cảnh báo, hard-fail, mất tự xưng, và **median + worst case theo truyện** (không lấy 1 chương đẹp làm bằng chứng).
- **Ai chạy:** lượt `--fresh` là của user (agent bị chặn gửi nội dung truyện ra NVIDIA — §13.2); agent chuẩn bị lệnh + đọc kết quả. `--existing`/re-lint local thì agent tự chạy được.
- Riêng gate trượt-theo-độ-sâu (D1): corpus có n1380 c50–69 (giữa truyện) vs 3 truyện c1–15 (đầu truyện) — so lint hai nhóm này chính là phép đo "chương sâu có tệ hơn chương đầu không".
- Kỷ luật đo: **một thay đổi → một lượt đo**, ghi vào bảng dưới; gói nào làm số xấu đi thì revert gói đó, không gộp 3 gói rồi đo một lần.

| Số đo (65 chương) | Baseline | Sau G1 | Sau G3 | Sau G2 | Mục tiêu |
|:--|--:|--:|--:|--:|--:|
| Tổng cảnh báo lint | 65 | | | | giảm ≥30% |
| Hard-fail (Hán/cụt/mất đoạn) | 0 | | | | giữ 0 |
| Mất tự xưng | 4 | | | | ≤2 |
| Lint nhóm giữa truyện (n1380 c50+) vs nhóm c1–15 | chưa tách | | | | chênh ≤20% |
| Tên riêng lệch giữa các chương cùng truyện | chưa đo | | | | 0 |

### Tầng 3 — Đọc tay + trend production (gate cuối, máy không thay được)

- Lint chỉ bắt lỗi đo được bằng regex; sai nghĩa/gượng văn máy mù → user đọc **10 chương liên tiếp ở bucket sâu** (n1380 c50+) bản mem-mới, chấm đạt/không theo 5 trục của Q0 (§Pha Q0 toi-uu-worker.md).
- Sau deploy VPS: theo dõi `lint_score` trend theo bucket 10 chương (G5) trên chương dịch mới thật ít nhất 3–5 ngày; trend đi ngang = chống trôi có tác dụng, trend vẫn dốc xuống = quay lại chẩn đoán.

## 6. Nguồn tham khảo đợt rà 2026-07-15

- [Loong: Long Document Translation Agent — adaptive context selection](https://arxiv.org/html/2605.30274)
- [What Does LLM Refinement Actually Improve? (document-level literary translation)](https://arxiv.org/pdf/2605.13368)
- [LLMs leverage document-level context for literary translation, but critical errors persist — WMT 2023](https://aclanthology.org/2023.wmt-1.41/)
- [DOME: Dynamic Hierarchical Outlining with Memory-Enhancement — NAACL 2025](https://aclanthology.org/2025.naacl-long.63.pdf)
- [Lost in Stories: Consistency Bugs in Long Story Generation](https://arxiv.org/html/2603.05890v1)
- [NexusSum: Hierarchical LLM Agents for Long-Form Narrative Summarization](https://arxiv.org/html/2505.24575v1)
- [SCORE: Story Coherence and Retrieval Enhancement](https://arxiv.org/html/2503.23512v1)
- [GalTransl — GPT dictionary chọn lọc](https://github.com/GalTransl/GalTransl)
- [LLM Novel Translator — auto-generating glossary xuyên chương](https://github.com/qw02/llm-novel-translator)
- [noveltrans — entity consistency pipeline, glossary user thắng máy](https://github.com/YuBing-link/noveltrans)
- [TranslateBooksWithLLMs — resume + giữ format sách dài](https://github.com/hydropix/TranslateBooksWithLLMs)
- [SakuraLLM — glossary/GPT dictionary cho truyện](https://github.com/SakuraLLM/SakuraLLM)
