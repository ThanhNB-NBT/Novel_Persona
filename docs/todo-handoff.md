# Handoff (2026-07-05, cập nhật 2026-07-06)

> **Tối ưu 2026-07-06:** `handle_patch` phân trang (vá đủ truyện >1000 chương); `reset_orphan_chapters` → SQL RPC (migration 024, hết trần 1000 dòng); audit định kỳ chỉ quét chương dịch sau watermark (giảm egress, audit full vẫn qua lệnh `audit`/nút Quét lỗi); `reprioritize` + `queue_sample_chapters` gom update theo lô; migration 025 index `chapters(translated_at) where done` + `novels(chapter_count_translated desc)`. Còn treo: phân trang mục lục app cho truyện >2000 chương; Realtime→Broadcast khi user tăng.

> **STATUS: cả 3 task 11/13/14 ĐÃ XONG (2026-07-06).** Chi tiết plan gốc giữ lại bên dưới làm tham chiếu.
> - **Task 14 (latency):** migration 022 `model_health` + RPC `bump_model_health`; `db.record_model_call` gọi trong `FallbackChain.complete`; tab Token (admin) có khối "SỨC KHỎE MODEL" (latency TB / %OK / chấm sống-chậm-chết).
> - **Task 13 (chấm điểm):** `python -m novelworker.main quality [--novel <id>]` — metric len-ratio (~3x là bình thường vì tính KÝ TỰ), glossary adherence, lặp cụm 2+ từ, mất đoạn, còn Hán. In bảng per-model + list chương tệ.
> - **Task 11 (crawl xếp hạng):** migration 023 `novels.source_rank`; `biquge.fetch_ranking` (parse `/top.html` 总点击, rank=thứ tự xuất hiện); `sync.discover_ranking` (set source_rank, ưu tiên hoàn thành, dịch metadata+chương mẫu); wire trong `main.py` vòng crawl; app "Đề cử" xếp theo `source_rank` (homeSectionsProvider `byRank` + fetchNovelPage recommended). ddxs không có ranking → giữ discover_latest.
> - CHƯA làm (nếu muốn nâng): bắt SỐ lượt xem cụ thể (shuhaige chỉ cho thứ hạng, không cho số); lọc cứng >500 chương lúc discovery (hiện chỉ ưu tiên hoàn thành + hot).
>
> Bối cảnh chung xem `docs/ke-hoach.md`, `docs/crawl-multisource.md`, memory `novel-project-state.md`. Skill UI: `flutter-novel-ui`.

## Bối cảnh nhanh
- **App** Flutter (`app/`): Riverpod + go_router + Supabase, cấu trúc phẳng (`lib/data.dart` = data/provider, `lib/screens/*`, `lib/widgets.dart`, `lib/theme.dart`). Chạy trên Android (target Windows đã bỏ): `flutter run -d <device> --dart-define-from-file=.env` (dart=`C:\flutter\bin`).
- **Worker** Python (`worker/`): chạy Docker (`docker compose up -d --build` trong `worker/`). venv host: `E:\Novel_Project\.venv` (chạy `../.venv/Scripts/python.exe`, cần `PYTHONIOENCODING=utf-8`). Model chính: `mistralai/mistral-small-4-119b-2603` (NVIDIA NIM), fuse chất lượng nằm trong `FallbackChain` (providers.py).
- **DB**: Supabase, migration mới → thêm file `supabase/migrations/0xx_*.sql` rồi `supabase db push --linked`. Mới nhất: 020.
- **Nguồn đang bật**: `shuhaige` (biquge, www.shuhaige.net, id 4) + `ddxs` (dingdian, www.dingdian-xiaoshuo.com, id 8).
- Đã xong gần đây: font Hurricane, "Mới cập nhật" loại truyện hoàn thành + bỏ chip trạng thái, discovery dịch sẵn 1-3 chương (sync.py `discover_latest` gọi `queue_sample_chapters`), màn Nhật ký lỗi (`errorlog.dart`+`screens/errors.dart`, route `/errors`), hoàn thiện sửa-dịch trong reader (ô đỏ + ⟨⟩ theo từ + gợi ý glossary). **Sửa TRỰC TIẾP chương hiện ngay** qua RPC `edit_chapter_vi` (migration 021, string-replace không LLM/không queue) + `ref.invalidate(chapterProvider)`; vẫn lưu glossary cho chương dịch sau; snackbar có action "Áp cả truyện" (tùy chọn, gọi `request_patch`). Fix RLS `bump_glossary_version` (migration 020).

---

## Task 11 — Crawl theo bảng xếp hạng + bắt điểm đánh giá/lượt xem

**Mục tiêu:** ưu tiên crawl truyện trên bảng xếp hạng nguồn, lượt xem cao, >500 chương, ưu tiên **hoàn thành**. "Đề cử" (Khám phá) xếp theo lượt xem thay vì số chương.

**ĐÃ ĐIỀU TRA (2026-07-05):**
- **shuhaige** CÓ trang xếp hạng: `GET /top.html` = 点击排行 (xếp theo lượt xem, HTML chứa 排行/点击/字数/完结); `GET /quanben/` = truyện hoàn thành. → bắt được **lượt xem + hoàn thành + xếp hạng**.
- **ddxs** KHÔNG có (`/top.html`, `/quanben/`, `/wanben/` đều 404) — chỉ có category. → ddxs giữ discovery theo category như hiện tại (nguồn phụ).

**CHƯA LÀM — cần làm:**
1. **Inspect HTML thật của `shuhaige.net/top.html` + `/quanben/`** để viết regex bóc: link truyện (`/{book_id}/`), tên, và con số lượt xem (点击). Dùng adapter probe:
   ```python
   # trong worker/, PYTHONIOENCODING=utf-8 ../.venv/Scripts/python.exe
   from novelworker import db
   from novelworker.crawler.biquge import BiqugeAdapter
   s = db.sb().table('sources').select('*').eq('id',4).single().execute().data
   a = BiqugeAdapter(base_url=s['base_url'], config=s.get('config') or {}, source_row=s)
   html = a._get('/top.html'); print(html[:5000])  # xem cấu trúc, tìm block xếp hạng + số 点击
   ```
2. **Migration** (0xx): thêm vào `novels`: `source_clicks bigint`, `source_rank int` (nullable). Index `(source_clicks desc)` cho query Đề cử.
3. **Adapter biquge** (`crawler/biquge.py`): thêm `fetch_ranking(kind: str) -> list[RankItem]` parse `/top.html` (kind='hot') + `/quanben/` (kind='completed'), trả `(source_novel_id, clicks, rank, title_zh?)`. `NovelMeta` hoặc dataclass mới. `fetch_latest` của biquge hiện trả `[]` — có thể để `fetch_latest` gọi `fetch_ranking` để discovery tự đầy.
4. **sync.discover_latest / discover_ranking** (`crawler/sync.py`): pull từ ranking, **ưu tiên**: hoàn thành (status='completed') > lượt xem cao; **lọc** chapter_count >= 500 (số chương phải lấy từ mục lục hoặc từ 字数 làm proxy — lưu ý shuhaige meta KHÔNG cho số chương nếu chưa sync mục lục). Cập nhật `source_clicks`/`source_rank` khi upsert. Sample chapters đã tự chạy (task 12).
   - Cầu chì token: discovery + sample chapters × nhiều truyện = tốn. Giữ trần `discover_new_per_cycle` (config, mặc định 50) và cân nhắc giảm khi bật ranking (thêm ít truyện chất lượng thay vì nhiều).
5. **App** (`app/lib/data.dart`): `homeSectionsProvider` — mục **"Đề cử"** (recommended) hiện = `byLength` (chapter_count_source). Đổi sang sort theo `source_clicks` desc (fallback chapter_count nếu null). `fetchNovelPage(SectionKind.recommended)` → `.order('source_clicks', ascending:false, nullsFirst:false)`.

**Gotcha:** shuhaige là web 盗版 tĩnh, có thể đổi cấu trúc; cô lập trong adapter. Số chương >500 khó biết trước khi sync mục lục — có thể sync mục lục cho truyện ranking rồi lọc.

---

## Task 13 — Chấm điểm dịch tự động (metric)

**Mục tiêu:** lệnh worker quét chương `done`, chấm metric khách quan (không tốn LLM), báo cáo — để tự soi chất lượng khi làm một mình.

**Plan:**
1. `worker/novelworker/main.py`: thêm mode `quality` (giống `audit`/`cost`). Quét chương done (paged như `worker.scan_bad_chapters`), mỗi chương chấm:
   - `han_ratio(content_vi)` (worker.py) — kỳ vọng ~0.
   - **Tỉ lệ độ dài** `len(vi)/len(zh)` — kỳ vọng ~1.3–1.8; cờ đỏ nếu <1.0 hoặc >2.6.
   - **Số đoạn**: `content_vi.count('\n')` vs `content_zh.count('\n')`.
   - **Bám glossary**: với term có `term_zh` xuất hiện trong `content_zh` → kiểm `correct_vi` có trong `content_vi` KHÔNG, và `wrong_vi` (nếu có) KHÔNG xuất hiện. Tính % tuân thủ.
   - **Lặp từ**: regex bắt từ/cụm lặp sát nhau (lỗi user từng than) — vd `\b(\w+)\s+\1\b` (unicode), hoặc chữ cuối câu trùng đầu câu sau.
2. Output: bảng per-model + per-novel điểm trung bình + list "chương tệ nhất" (kèm lý do) để soi tay. Có thể `--novel <id>` để chấm 1 truyện.
3. Tái dùng `worker.check_translation` + `han_ratio`. Thêm hàm `glossary_adherence(novel_id, zh, vi)` + `repetition_flags(vi)`.
4. (Tùy chọn) lưu điểm vào cột `chapters.quality_score` để app hiện; nhưng bản đầu chỉ cần in báo cáo CLI.

**Lưu ý:** đây là chấm KHÁCH QUAN (metric), không bắt được "dịch có hay không". User đã đồng ý bản metric + đã có nút sửa-dịch tay trong reader để vá lỗi cụ thể.

---

## Task 14 — Token screen: độ sống + latency model

**Mục tiêu:** đo latency + tỉ lệ ok/fail mỗi model → tab **Token** (admin) hiện, chấm màu sống/chậm/chết.

**Plan:**
1. **Migration** (0xx): bảng `model_health (model text primary key, ok_count int default 0, fail_count int default 0, total_latency_ms bigint default 0, last_ok_at timestamptz, last_error text, last_error_at timestamptz, updated_at timestamptz default now())`. RLS: enable + policy SELECT `using (is_admin())` (worker ghi bằng service_role nên bypass).
2. **db.py**: `record_model_call(model, latency_ms, ok, error=None)` — upsert: `ok`→ ok_count++, total_latency_ms += latency, last_ok_at=now; `fail`→ fail_count++, last_error, last_error_at.
3. **providers.py** `FallbackChain.complete`: bọc mỗi `p.complete(...)` bằng đo `time.time()`; thành công → `db.record_model_call(res.model, dt_ms, True)`; exception → `db.record_model_call(p.model, dt_ms, False, str(e))` rồi tiếp provider kế. (Chú ý: fuse `validate` raise cũng tính là fail của model đó — đúng.)
4. **App** `data.dart`: `modelHealthProvider` (FutureProvider) select `model_health`. `admin.dart` `_TokensTab`: dưới bảng token thêm khối "Sức khỏe model": mỗi model hiện **latency TB** (`total_latency_ms/ok_count`), **% thành công** (`ok/(ok+fail)`), **lần OK cuối** (`_elapsed(last_ok_at)`), **chấm màu**: xanh (sống: có OK gần đây + %ok cao), vàng (chậm: latency cao), đỏ (chết: %fail cao hoặc không OK lâu). Dùng `_elapsed`/`_date` sẵn có trong admin.dart.

**Gotcha:** đừng để ghi `model_health` làm chậm đường dịch — chỉ 1 upsert nhẹ/lần gọi, chấp nhận được. Tên model trong `res.model` = model thật đã trả (quan trọng khi FallbackChain đổi provider).

---

## Task phụ (tùy chọn) — sửa đại từ theo NGỮ CẢNH (single-occurrence edit)
Hiện `edit_chapter_vi` (migration 021) replace MỌI chỗ khớp chuỗi trong chương → ổn cho tên
riêng (duy nhất), SAI cho đại từ ("cậu"/"hắn" xuất hiện nhiều chỗ nghĩa khác nhau). Workaround
hiện tại: user nới ⟨⟩ để chọn cụm duy nhất. Muốn "chỉ đổi đúng occurrence đang chọn":
cần map vị trí ký tự của vùng chọn trong reader về offset trong `content_vi` gốc — khó vì
`reader.dart _splitBySentence` tách câu/gộp lại nên block hiển thị KHÔNG phải substring verbatim
của content_vi. Hướng: (a) đổi RPC nhận `p_occurrence int` (thay occurrence thứ N), + reader tính
N bằng cách đếm số lần `wrong` xuất hiện trước vị trí chọn trong content_vi thô; hoặc (b) bỏ
sentence-split khi cần map. Chưa cấp thiết — prompt đã cải để dịch đúng đại từ hơn (2026-07-05:
thêm rule câu-kể-vs-thoại + register thể loại + văn nói, `prompts.py` SYSTEM_CHAPTER XƯNG HÔ).

## Thứ tự đề xuất làm
14 (tự chứa, nhanh) → 13 (tự chứa) → 11 (lớn nhất, cần inspect HTML + migration + đụng cả app). Mỗi task xong: `flutter analyze lib` (app) / smoke import (worker) + rebuild worker Docker nếu đổi worker.
