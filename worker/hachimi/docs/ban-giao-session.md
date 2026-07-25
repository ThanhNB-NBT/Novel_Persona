# Bàn giao sang session mới — 25/07/2026

Dán nguyên phần dưới vào session mới.

---

Tiếp tục dự án dịch truyện Trung→Việt ở `E:\Novel_Project`. Trả lời bằng tiếng Việt.
Trạng thái tới cuối 25/07:

## Đang chạy production (VPS 103.72.57.133, đã deploy + push)

- **Engine dịch: Hachimi teacher-v4** (CT2 57M) ở `worker/models/hachimi-ct2/`, bản backup
  cũ ở `/root/model_backup/hachimi-ct2-20260725` trên VPS.
- **beam 6 + n-best 6**: beam search trả 6 giả thuyết, chấm bằng cổng chất lượng của dự án
  (`hachimi_engine._rank_penalty`) rồi lấy bản ít lỗi nhất. Đo 12 chương: đại từ hiện đại
  81→64, quote lệch 3→2, thời gian +1,6%.
- **Hachimi dịch TẤT CẢ**: nội dung chương, tiêu đề chương, tiêu đề truyện, mô tả truyện.
  Tác giả tra bảng Hán-Việt, thể loại theo map cố định.
- **LLM (`qwen/qwen3-next-80b-a3b-instruct` qua NVIDIA NIM) chỉ còn 3 việc phụ**: trích tên
  riêng đắp glossary (20 chương đầu mỗi truyện), vá chữ Hán sót khi bảng tra bó tay, và
  đoán tên gốc tiếng Trung khi search truyện ở crawler.
- worker_settings đã trả về bình thường: `crawl_interval_min=45`, `max_chapters_per_day=1000`.
  `TRANSLATOR_CONCURRENCY=1` giữ nguyên (đo được CT2 bão hoà ở 2 luồng, thêm core vô ích).

## Việc đang treo, cần quyết

**Dọn glossary.** Có 41.000 term: 167 duyệt tay, **10.649 gợi ý đang được cưỡng chế**
(chính nhóm này giữ tên riêng nhất quán — nhờ nó `玛利亚` mới luôn ra "Maria"), và
**30.184 gợi ý nằm im** chỉ hiện ở màn Thuật ngữ. Chủ dự án muốn dọn; tôi đề nghị xoá
30.184 cái nằm im và giữ phần đang cưỡng chế. Chưa xoá gì cả.

## Chưa commit (cố ý)

Toàn bộ `app/` (15 file .dart, pubspec, hanviet.tsv), `AGENTS.md`, `README.md`,
`docs/toi-uu-worker.md`. Đó là việc của chủ dự án từ trước, không liên quan deploy worker.

## Bản đồ mã nguồn

- `worker/hachimi/` — hub duy nhất cho finetune: `pipeline/` (script còn chạy),
  `data/{gold,replay,eval_locked,source}`, `eval/` (harness + báo cáo), `packs/`, `docs/`,
  `archive/`. Đọc `worker/hachimi/README.md` và `docs/luong-dich.md` trước khi sửa gì.
- Thước đo chuẩn: `hachimi/eval/evaluate_hachimi_teacher_v2.py` (2 tập khoá) và
  `evaluate_hachimi_vnext_e_fullchapters.py` (12 chương, 6 thể loại).
- `hachimi/eval/benchmark_nim_models.py` — chấm model NIM bằng đúng luồng production.
- `hachimi/eval/benchmark_analyze_names.py` — chọn model cho việc trích tên.

## Kết luận đã đo, đừng làm lại

- Data nhịp câu **đã bão hoà**: +62% gold (2.478→4.012 dòng) mà câu/cảnh không nhích (3,5→3,4).
- Booster vài chục dòng **không đè nổi prior** của model — kể cả khi thêm đúng câu cần dạy.
- Lỗi ánh xạ cố định (冷却时间→CD, 高校, tên riêng) phải sửa ở **glossary**, không phải data.
- Không model NIM miễn phí nào thay được Hachimi: con nhanh nhất (llama-4-maverick, 22-24s/
  chương) có similarity 0,61 so với 0,72 của Hachimi; các con mạnh hơn thì 87-224s/chương.
- Thêm core VPS vô ích: CT2 bão hoà ở 2 luồng (1 core 14,4s → 2 core 9,7s → 4 core 10,5s).

## Bẫy đã dính, đừng dính lại

1. **Deploy**: image bake code — phải `docker compose build crawler` TRƯỚC `up -d
   --force-recreate`, nếu không container chạy code cũ.
2. **Git**: cây commit phải TỰ ĐỦ. Đã một lần commit `worker.py` gọi hàm nằm trong file
   chưa commit → production `AttributeError` toàn bộ job.
3. **PowerShell**: đừng sửa file .py bằng `Get-Content -Raw | Set-Content -Encoding UTF8`
   — nó double-encode hết tiếng Việt.
4. **Codex qua MCP**: giao 100 dòng/phiên. Lô 500 dòng thì nó copy bản cũ cho gần nửa lô;
   lô 200 thì bỏ dở. Chạy nhiều phiên song song, mỗi phiên ghi shard riêng.
5. **Cổng đo được thì thầy tối ưu được**: Codex từng thay máy móc `", "`→`" . "` để qua cổng
   đếm câu. Luôn đọc tay vài chục dòng mỗi lô.
