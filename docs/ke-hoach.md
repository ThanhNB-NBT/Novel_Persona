# Kế hoạch kỹ thuật: App đọc tiểu thuyết mạng Trung → Việt (dịch bằng LLM)

> ⚠️ **Pháp lý:** nội dung Qidian/Fanqie/JJWXC có bản quyền. Dùng cá nhân/nội bộ; phát hành công khai có rủi ro DMCA/khóa store.

**Trạng thái:** P0 (schema + worker Python + adapter Shuhaige) đã có code trong repo. Tài liệu này mô tả chi tiết kỹ thuật của toàn hệ thống, phần đã làm lẫn phần sắp làm.

> 📌 Nguồn crawl đã chuyển từ **Fanqie → Shuhaige** (shuhaige.net mở full chương free; Fanqie web khóa VIP sau 10 chương — xem mục §"Dọn schema" & migration 007). Các phần mô tả Fanqie phía dưới giữ lại làm bối cảnh lý do chọn nguồn.

---

## 0. Stack cụ thể

| Thành phần | Công nghệ | Ghi chú |
|---|---|---|
| Mobile app | Flutter 3.x (Dart 3), Material 3 | Android + iOS, 1 codebase |
| State/DI | `flutter_riverpod` 2.x (codegen `riverpod_generator`) | Provider graph, autoDispose |
| Routing | `go_router` | Deep-link `novel/:id/chapter/:index` |
| Backend-as-a-service | Supabase (Postgres 15, Auth, Realtime, Storage) | Region Singapore |
| SDK app | `supabase_flutter` | Auth + PostgREST + Realtime channel |
| Worker | Python 3.11+, chạy 2 process (`crawl`, `translate`) | Railway/Fly.io/VPS |
| HTTP crawl | `curl_cffi` (impersonate Chrome TLS fingerprint) | Vượt anti-bot tốt hơn httpx/requests |
| Config worker | `pydantic-settings` (đọc `.env`) | Xem `worker/novelworker/config.py` |
| Retry | `tenacity` (exponential backoff 2→30s, 3 lần) | Bọc quanh call LLM |
| LLM client | `openai` SDK trỏ base_url OpenRouter/Fireworks/NVIDIA | 1 client cho cả 3 provider |
| Model dịch | DeepSeek V4 Flash (`deepseek/deepseek-v4-flash` qua OpenRouter) | Fallback: Fireworks / NVIDIA NIM (cùng model) |
| Queue | Bảng `translation_jobs` trong Postgres + `FOR UPDATE SKIP LOCKED` | Không cần Redis/RabbitMQ giai đoạn này |
| Fonts đọc | Literata / Noto Serif (bundle trong app) | Serif tiếng Việt đủ dấu |

Nguyên tắc chọn: mọi thứ chạy được free-tier khi dev; không thêm hạ tầng (Redis, message broker, search engine) chừng nào Postgres còn gánh được.

---

## 1. Kiến trúc & luồng dữ liệu

```
┌─────────────┐   PostgREST/RLS    ┌──────────────────────┐   service_role   ┌──────────────────┐
│ Flutter App │◄──────────────────►│ Supabase             │◄────────────────►│ Worker (Python)  │
│             │   Realtime WS      │ Postgres 15          │                  │ ├─ crawl proc    │
│             │◄───────────────────│ Auth · Realtime      │                  │ └─ translate proc│
└─────────────┘                    └──────────────────────┘                  └────────┬─────────┘
                                                                                      │ curl_cffi + proxy
                                                                             Fanqie / Qidian / JJWXC
                                                                                      │ OpenAI-compatible API
                                                                             OpenRouter / Fireworks / NIM
```

Ba ranh giới bảo mật rõ ràng:

1. **App → Supabase:** chỉ dùng `anon key` + JWT user, mọi truy cập qua RLS. App không giữ secret nào khác, không gọi trực tiếp nguồn hay LLM.
2. **App kích hoạt dịch:** qua RPC `request_translation(novel_id, up_to)` (SECURITY DEFINER, bắt buộc `auth.uid()`), là điểm duy nhất user ghi được vào pipeline.
3. **Worker → Supabase:** dùng `service_role key`, bypass RLS, là bên duy nhất ghi vào `novels/chapters/comments/translation_jobs`.

---

## 2. Database (đã implement: `supabase/migrations/001_schema.sql`)

### 2.1 Điểm kỹ thuật đáng chú ý

- **Enum thay vì text tự do:** `novel_status`, `translation_status` (`none→queued→translating→done|failed`), `job_type`, `job_status`, `term_type`, `term_scope` — ràng buộc ở tầng DB, app không cần validate.
- **Chống job trùng bằng partial unique index** (không cần logic app):
  ```sql
  create unique index uq_job_chapter_active on translation_jobs (chapter_id)
    where status in ('pending','running') and chapter_id is not null;
  ```
  Nhiều user cùng bấm đọc 1 truyện → insert job thứ 2 vỡ unique → worker `enqueue()` nuốt lỗi duplicate. Dịch 1 lần, dùng chung.
- **Claim job an toàn khi nhiều worker:** RPC `claim_next_job(worker_id)` dùng `FOR UPDATE SKIP LOCKED` — pattern queue chuẩn trong Postgres, không có race, worker chết không giữ lock (row lock nhả theo transaction). Job `chapter` chỉ được claim khi `content_zh` đã có (điều kiện `exists` ngay trong query) → translator không bao giờ nhận chương crawler chưa tải xong.
- **Ưu tiên:** `priority int` (nhỏ = trước): metadata truyện mới = 10, chương user yêu cầu = 50, comment batch = 80. Index `(status, priority, created_at) where status='pending'` cho câu lấy job O(log n).
- **Glossary versioning:** bảng `novel_glossary_version` + trigger tăng version mỗi khi thêm/sửa term. Mỗi chương lưu `glossary_version` tại thời điểm dịch → câu query "chương nào dịch bằng glossary cũ, cần vá" là 1 phép so sánh version, không cần diff nội dung.
- **Realtime:** `alter publication supabase_realtime add table chapters, novels` — app subscribe UPDATE trên `chapters` filter theo `novel_id`.

### 2.2 RLS (đã có policy)

| Bảng | anon/authenticated | Ghi |
|---|---|---|
| `novels/chapters/comments/sources` | SELECT tự do (duyệt trước khi login) | chỉ service role |
| `glossary_terms` | SELECT khi `approved` | user INSERT với `created_by = auth.uid()`, global bắt buộc `approved=false` (chờ duyệt) |
| `library/reading_progress/term_edit_history/profiles` | ALL, ràng `user_id = auth.uid()` | — |
| `translation_jobs` | không policy → chỉ service role | qua RPC |

### 2.3 Vận hành quanh queue (scale cá nhân 1-2 user)

- **Job reaper: ✅ đã làm trong worker** (`db.requeue_stale_jobs`, gọi mỗi 60s trong translator) — job `running` quá `STALE_JOB_MINUTES` (máy sập/ngủ giữa chừng) trả về `pending`, hết lượt retry thì `failed`. Không cần pg_cron.
- **Chống đốt tiền: ✅ cầu chì `MAX_CHAPTERS_PER_DAY`** trong worker (mặc định 200 chương/ngày ≈ $1-2 kịch trần) thay cho quota per-user — với 1-2 người dùng, quota theo user là thừa.
- Cân nhắc sau: xóa `content_zh` của chương đã dịch lâu ngày để tiết kiệm dung lượng (chỉ cần khi DB gần đầy free tier — 500MB chứa được cỡ vài nghìn chương cả gốc lẫn dịch).

---

## 3. Worker (đã implement: `worker/novelworker/`)

```
novelworker/
├─ config.py            # pydantic-settings, đọc .env
├─ db.py                # supabase-py client (service role) + thao tác chung
├─ main.py              # entrypoint: `python -m novelworker.main crawl|translate`
├─ crawler/
│  ├─ base.py           # SourceAdapter ABC + dataclass NovelMeta/ChapterRef/CommentItem
│  ├─ shuhaige.py       # ShuhaigeAdapter (curl_cffi) — nguồn hiện dùng
│  └─ sync.py           # discovery / sync mục lục / tải chương / sync tủ sách
└─ translator/
   ├─ providers.py      # TranslationProvider (OpenAI-compatible) + tenacity retry
   ├─ prompts.py        # system prompt dịch chương/metadata/comment + glossary injection
   └─ worker.py         # vòng lặp claim job → handler theo type
```

### 3.1 Vòng đời job (state machine)

```
pending ──claim_next_job──► running ──ok──► done
   ▲                          │
   │ attempts < max (3)       ├─ lỗi thường ──► finish_job(ok=False) → pending (retry) | failed
   └──────────────────────────┤
                              └─ MissingContentError (chưa có content_zh)
                                 ──► defer_job() → pending, KHÔNG tính attempt
```

- Retry 2 tầng: tenacity retry bên trong 1 lần gọi LLM (lỗi mạng/5xx thoáng qua), attempts của job cho lỗi bền hơn. `failed` chung cuộc → chương hiện nút "Dịch lại" trong app (app gọi lại `request_translation`).
- Translator: chạy `TRANSLATOR_CONCURRENCY` luồng song song (mặc định 2), mỗi luồng tự claim job (atomic nên nhiều luồng/nhiều máy không giành nhau). Main thread làm housekeeping mỗi 60s: reaper job kẹt + kiểm tra cầu chì chi phí ngày (xem 2.3). Chạy nhiều máy: mỗi máy `WORKER_ID` riêng.

### 3.2 Crawl process (lịch chạy trong `main.py crawl`)

Mỗi vòng (interval = `CRAWL_INTERVAL_MIN`, mặc định 45'):

1. `discover_latest()` — quét bảng "mới nhất" của nguồn → upsert `novels` + mục lục → enqueue job `metadata` (priority 10) cho truyện chưa dịch metadata. Sleep 1s giữa các truyện.
2. `sync_followed_novels()` — mọi truyện nằm trong ≥1 tủ sách: fetch lại mục lục, phát hiện chương mới. Sleep 2s/truyện.
3. `ensure_chapters_fetched()` — chương `queued` mà `content_zh IS NULL` → tải nguyên văn, sleep 1.5s/chương.

Tách crawl và translate thành 2 process độc lập: crawl bị chặn/proxy chết không kéo sập pipeline dịch và ngược lại.

---

## 4. Crawler — chi tiết từng nguồn

### 4.1 Kỹ thuật chống chặn (đã dùng trong FanqieAdapter)

- **`curl_cffi` với `impersonate="chrome"`**: giả TLS/JA3 fingerprint của Chrome thật — đây là lớp anti-bot đầu tiên của Bytedance/Tencent, requests/httpx thuần bị nhận diện ngay.
- Cookie thật từ trình duyệt qua env `FANQIE_COOKIE` khi bị 403; proxy xoay qua `HTTP_PROXY_URL` (dạng `http://user:pass@host:port`, cắm dịch vụ residential proxy khi cần).
- Rate limit thủ công (sleep giữa request) + luôn set `Referer`. Cache: `content_zh` lưu trong DB nghĩa là không bao giờ crawl lại chương đã tải.

### 4.2 Fanqie (✅ đã chạy thật, smoke pass 2026-07)

- **Metadata + mục lục:** GET HTML trang `/page/{book_id}`, parse bằng BeautifulSoup:
  - Tiêu đề `<h1>`, giới thiệu `.page-abstract-content`, bìa `meta[og:image]`, trạng thái `span.info-label-yellow` (chứa "完结" = hoàn thành).
  - Mục lục: các `div.chapter-item` → `a[href="/reader/{chapter_id}"]`, thứ tự trong trang = thứ tự chương.
- **Nội dung chương:** trang web reader `/reader/{chapter_id}` → parse `__INITIAL_STATE__.reader.chapterData.content`. (API app `novel.snssdk.com/.../reader/full/v1` **đã chết** — trả 200 body rỗng, kiểm chứng 2026-07.)
- **Font obfuscation:** content web reader bị tráo chữ nhưng theo **bảng tĩnh cố định** (codepoint 58344–58715 ↔ 372 ký tự, cộng đồng crawler đã giải) — nhúng sẵn `_FQ_CHARSET` trong `fanqie.py`, decode offline không cần tải font. Ký tự ngoài bảng (hiếm) → bù bằng file map `FANQIE_FONT_MAP`; sót ≤10 thay `□`, sót nhiều raise để không dịch rác.
- **Discovery "truyện mới":** Fanqie không có API công khai ổn định → `fetch_latest()` trả rỗng. Luồng chính là **thêm truyện theo book_id** (số trong URL `fanqienovel.com/page/<id>`). Bổ sung parse trang rank sau nếu thật sự cần.
- **Chương VIP:** cần đăng nhập — crawler chỉ lấy được chương miễn phí; chương VIP trả rỗng → báo lỗi rõ.
- Bình luận: nằm ở API app riêng, để P2 — hiện trả rỗng.

### 4.3 Vì sao chưa làm Qidian/JJWXC ngay (và độ khó từng nguồn)

Lý do thực dụng: P0 mới có 1 adapter (Fanqie) và **chưa chạy thật lần nào** — endpoint, cookie, font map đều là giả định cần kiểm chứng bằng lệnh `smoke` trước. Thêm nguồn lúc này là nhân đôi phần chưa chắc chạy. Kiến trúc đã sẵn cho việc thêm sau: mỗi nguồn chỉ là 1 class con `SourceAdapter` (5 method: `fetch_latest / fetch_novel_meta / fetch_chapter_list / fetch_chapter / fetch_comments`), pipeline/queue/dịch không đụng tới.

Độ khó thực tế của từng nguồn (đã khảo sát tool cộng đồng):

| Nguồn | Độ khó | Ghi chú kỹ thuật |
|---|---|---|
| **Fanqie** | Trung bình | Free hoàn toàn; API JSON; đôi khi font obfuscation (đã xử lý) |
| **JJWXC** | **Dễ** (chương free) | HTML tĩnh, encoding `gb18030`; nhiều crawler mã nguồn mở (Scrapy) tải chương **non-VIP**. Chủ yếu ngôn tình/đam mỹ. **Chương VIP bị chặn** — chỉ crawl được chương miễn phí |
| **Qidian** | **Khó nhất** | Font obfuscation riêng + CSS đảo thứ tự đoạn + JS fingerprint; nhiều chương VIP tính phí. Không đáng công cho nhu cầu cá nhân |

Lưu ý chung: JJWXC/Qidian có **paywall** (chương VIP trả phí) — crawler cộng đồng gần như chỉ lấy được chương free. Fanqie miễn phí toàn bộ nên là nguồn "sạch" nhất để tự động hóa.

**Kết luận cho quy mô cá nhân:** làm Fanqie chạy ổn trước (dùng `smoke` kiểm chứng). Cần nguồn 2 → thêm **JJWXC** (dễ, bù mảng ngôn tình/đam mỹ Fanqie yếu). **Qidian bỏ khỏi scope** trừ khi cần đúng một truyện chỉ Qidian có → khi đó dùng API mobile `m.qidian.com` hoặc Playwright headless chỉ cho truyện đó.

### 4.4 Các nguồn tiểu thuyết mạng TQ khác (nếu sau này mở rộng)

Xếp theo mức hữu ích cho app này:

- **纵横中文网 (Zongheng)** — nam tần huyền huyễn/đô thị/game, nhiều chương free, chống bot nhẹ hơn Qidian. Ứng viên tốt sau JJWXC.
- **17K小说网** — lâu đời, kho lớn, khá dễ crawl.
- **飞卢 (Faloo)** — truyện hệ thống/nhịp nhanh, cập nhật dày.
- **刺猬猫 / SFACG** — thiên nhị nguyên/khinh tiểu thuyết (light novel).
- **书旗、掌阅、塔读、逐浪、黑岩** — các nền tảng đọc phổ thông khác.

Fanqie (miễn phí, kho khổng lồ của ByteDance) + JJWXC gần như phủ hết nhu cầu phổ biến; các nguồn còn lại chỉ thêm khi muốn thể loại/tác giả cụ thể.

---

## 5. Tầng dịch LLM

### 5.1 Provider abstraction (đã code)

`TranslationProvider` = 1 client `openai` với `base_url` tùy provider — OpenRouter, Fireworks, NVIDIA NIM đều nói chuyện OpenAI-compatible nên đổi provider chỉ là đổi env `LLM_PROVIDER`, pipeline không đổi. `LLMResult` trả kèm `prompt_tokens/completion_tokens` → ghi vào từng chương để tính tiền.

| Ưu tiên | Provider | Model (đang set trong `.env`) | Vai trò |
|---|---|---|---|
| 1 | NVIDIA NIM | `deepseek-ai/deepseek-v4-flash` | **Chính — free** (có rate-limit RPM, đủ cho 1-2 người đọc) |
| 2 | Fireworks | `accounts/fireworks/models/deepseek-v4-flash` | Dự phòng khi NIM lỗi/rate-limit |
| 3 | OpenRouter | `deepseek/deepseek-v4-flash` | Dự phòng cuối |

**Fallback tự động (✅ đã code):** `LLM_PROVIDER=nvidia,fireworks,openrouter` — `get_provider()` trả về `FallbackChain`: gọi NIM trước, lỗi/429 thì chuyển Fireworks rồi OpenRouter **ngay trong cùng lần dịch**, job không fail oan. Provider chưa điền API key tự bị bỏ qua. Với NIM là chính, chi phí gần như $0; chỉ tốn tiền những lúc NIM nghẽn.

Đổi model = sửa `.env`, không đụng code. Chương ~3.000 chữ Hán ≈ 4–5k token in + 5–6k out. Tham số: `temperature=0.3`, `max_tokens=8192`. Cột `model_used` từng chương ghi model *tại thời điểm dịch* — chương cũ hiện model cũ là bình thường.


### 5.2 Prompt design (đã code trong `prompts.py`)

System prompt dịch chương gồm 4 khối:

1. Quy tắc văn phong: Hán-Việt cho tên riêng, xưng hô theo thể loại (ta–ngươi vs tôi–cậu), giữ số đoạn, cấm tóm tắt/bình luận.
2. **Glossary injection:** term của truyện + term global approved, format `- 林松 → Lâm Tùng (KHÔNG dịch thành 'rừng Tùng')` — đưa cả bản sai đã gặp giúp model né chính xác lỗi cũ.
3. User message: tùy chọn `[Ngữ cảnh chương trước: ...]` + tiêu đề + nội dung.
4. **Side-channel trích tên riêng:** yêu cầu dòng cuối `GLOSSARY_JSON: [{"zh","vi","type"}]` — worker bóc bằng regex, lưu làm term gợi ý (`approved=false`) phục vụ bottom sheet sửa từ trong app. Đây là cách lấy mapping zh↔vi mà không tốn call LLM riêng.

Parse output phòng thủ: `_extract_json()` xử lý cả JSON bọc ```` ```json ````, JSON lẫn text, cân bằng ngoặc có xét escape/string — vì DeepSeek không có JSON mode ổn định qua mọi provider.

### 5.3 Việc còn thiếu (P2)

- **Tóm tắt liên chương:** sau khi dịch chương N, gọi LLM (hoặc kèm luôn trong cùng call, thêm 1 dòng `SUMMARY:`) sinh tóm tắt ~100 chữ, lưu cột `summary_vi`; bơm vào prompt chương N+1 (`prev_summary` đã có sẵn trong `build_chapter_user` nhưng chưa được truyền).
- **Chương quá dài (>10k chữ):** cắt theo ranh giới đoạn thành các mảnh ~6k chữ, dịch tuần tự cùng glossary + tóm tắt mảnh trước, nối lại. Ngưỡng đặt trong config.
- **Vá chương cũ khi có term mới:** job type mới `patch` — với chương `glossary_version < version hiện tại`: nếu term có `wrong_vi` thì string-replace trực tiếp (rẻ, không gọi LLM), đánh dấu version mới; chỉ dịch lại bằng LLM khi user bấm "Dịch lại".

---

## 6. Flutter app (P1 — chưa code)

### 6.1 Cấu trúc project

```
lib/
├─ main.dart                    # Supabase.initialize, ProviderScope
├─ router.dart                  # go_router: /discover /novel/:id /novel/:id/read/:index /library /settings
├─ core/ (supabase client, theme, constants)
├─ features/
│  ├─ discover/    # tab Mới đăng + Hot, filter thể loại/trạng thái, search
│  ├─ novel_detail/
│  ├─ reader/      # màn đọc + theme + glossary sheet
│  ├─ library/
│  └─ settings/
└─ data/
   ├─ models/      # freezed: Novel, Chapter, Comment, GlossaryTerm, Progress
   └─ repositories/ # NovelRepo, ChapterRepo, GlossaryRepo, ProgressRepo
```

Model dùng `freezed` + `json_serializable`; repository là lớp duy nhất chạm `supabase_flutter`, provider Riverpod bọc trên.

### 6.2 Realtime "chương hiện dần"

```dart
final chapterUpdates = supabase
  .channel('chapters:$novelId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public', table: 'chapters',
    filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
                                 column: 'novel_id', value: novelId),
    callback: (payload) => ref.invalidate(chapterListProvider(novelId)),
  ).subscribe();
```

Cuối chương đang đọc hiển thị trạng thái chương kế lấy từ `translation_status` (queued → "Trong hàng đợi", translating → spinner "Đang dịch…", done → nút sang chương).

### 6.3 Luồng dịch lazy phía app

- Bấm "Thêm vào tủ & đọc": insert `library` + gọi `rpc('request_translation', {novel_id, up_to: 10})`.
- Trong reader, mỗi lần chuyển chương: `if (maxTranslatedIndex - currentIndex <= 3) rpc('request_translation', up_to: currentIndex + 10)`. Ngưỡng 3 và batch 10 đặt trong remote config (bảng `app_config` hoặc hằng số buổi đầu). Server tự chống trùng job nên app cứ gọi thoải mái (idempotent).
- Progress: debounce 2s ghi `reading_progress (chapter_index, scroll_offset)` — scroll_offset là tỉ lệ 0–1 của vị trí cuộn.

### 6.4 Reader rendering

- Chế độ cuộn dọc: `ListView` các đoạn văn (`SelectableText.rich` từng đoạn — cần selectable cho tính năng sửa từ). Chế độ lật trang: `PageView` + tự phân trang bằng `TextPainter.layout` theo kích thước màn + font hiện tại (tính lại khi đổi font/cỡ chữ).
- Theme đọc: 4 preset (Sáng `#FAF6EF`, Sepia `#F4E8D0`, Xám ấm `#2B2B28`, AMOLED `#000`), lưu trong `profiles.settings` jsonb + cache local bằng `shared_preferences` để mở app không chớp theme.
- **Sửa từ (glossary):** long-press từ/cụm → tra list term gợi ý (đã lưu từ GLOSSARY_JSON) tìm `correct_vi`/`wrong_vi` khớp chuỗi được chọn → bottom sheet hiện `term_zh` gợi ý + ô nhập bản đúng + chọn loại + phạm vi → insert `glossary_terms` (RLS cho phép) + `term_edit_history`. Bản vá chương cũ do worker xử lý (mục 5.3), app chỉ cần invalidate cache chương.

---

## 7. Auth

- Supabase Auth email/password (P1); Google/Apple sign-in để sau (cần cấu hình OAuth + Apple Developer).
- Trigger `handle_new_user` (đã có) tạo `profiles` khi đăng ký.
- Khách anon: duyệt + đọc chương đã dịch sẵn thoải mái (RLS cho SELECT), nhưng `request_translation` raise nếu chưa login; cầu chì tổng `MAX_CHAPTERS_PER_DAY` trong worker chặn nốt trường hợp app bug spam request (mục 2.3).

---

## 8. Deploy & vận hành

### 8.1 Worker lên Railway (hoặc Fly.io)

- 1 Dockerfile (python:3.11-slim + `pip install -r requirements.txt`), 2 service cùng image khác command: `python -m novelworker.main crawl` và `... translate`. Scale translate = tăng replica (claim atomic nên an toàn).
- Env: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `LLM_PROVIDER`, `NVIDIA_API_KEY`, `NVIDIA_MODEL`, `CRAWL_INTERVAL_MIN`, `HTTP_PROXY_URL`, `WORKER_ID` (đặt khác nhau mỗi replica).
- Healthcheck đơn giản: worker touch 1 row `heartbeat` mỗi vòng; alert khi stale (kiểm bằng pg_cron + gửi webhook, hoặc nhìn dashboard).

### 8.2 Observability

- Logging: `logging` chuẩn Python → stdout → log viewer của Railway. Thêm Sentry (`sentry-sdk`) cho exception ở P3.
- **Dashboard chi phí bằng SQL** (chạy trong Supabase, sau này vẽ trong app admin):
  ```sql
  select date_trunc('day', translated_at) d, model_used,
         count(*) chapters,
         sum(prompt_tokens) p_tok, sum(completion_tokens) c_tok
  from chapters where translation_status='done' group by 1,2 order by 1 desc;
  ```
- Giám sát crawler: đếm job `failed` theo ngày + log 403/429 theo domain → biết khi nào cần thay cookie/proxy.

### 8.3 Chi phí hàng tháng ước tính

Supabase Free→Pro ($0–25) · Railway ~$5–10 · proxy $0 (chưa cần) → $10–30 · DeepSeek theo lượng đọc (vài $/nghìn chương).

---

## 9. Testing

- **Worker:** pytest (`worker/test_worker_helpers.py` đã có — test `_extract_json`, parser `__INITIAL_STATE__`, `_chapters_from_payload`). Bổ sung: contract test cho mỗi adapter chạy với HTML/JSON fixture đã lưu (không gọi mạng trong CI); test tích hợp queue bằng Supabase local (`supabase start`).
- **Chất lượng dịch:** giữ bộ ~20 chương chuẩn (đã người duyệt) làm eval; khi đổi model/prompt chạy lại và so (tỉ lệ term glossary được tuân thủ — check bằng string match; độ dài/số đoạn khớp bản gốc). Dữ liệu `term_edit_history` sau này chính là nguồn eval tự sinh.
- **Flutter:** widget test cho reader pagination + golden test theme; integration test luồng đọc với Supabase local.

---

## 10. Roadmap (điều chỉnh theo hiện trạng)

| Giai đoạn | Nội dung | Trạng thái |
|---|---|---|
| **P0** | Schema+RLS+queue, worker crawl/translate, FanqieAdapter, pipeline dịch e2e | ✅ smoke pass (crawl + decode font + dịch NVIDIA NIM, 2026-07) |
| **P0.5** | Job reaper + cầu chì chi phí/ngày + giải mã font Fanqie (map file) + dịch song song N luồng | ✅ code xong |
| **P1** (3–4 tuần) | Flutter: auth email, Khám phá, chi tiết truyện, reader + 4 theme, tủ sách, lazy translate + Realtime; worker chạy trên máy cá nhân (hoặc Railway nếu muốn 24/7) | ✅ xong 2026-07-02 (chi tiết §10.1) |
| **P2** (2–3 tuần) | Glossary UI + vá chương (job `patch`) ✅, tóm tắt liên chương ✅, chunk chương dài ✅, nút dịch lại ✅, ~~dịch bình luận Fanqie~~ (web không có comment, API app cần chữ ký thiết bị — gác lại) | ✅ xong 2026-07-02 |
| **P3** (tùy nhu cầu) | Nguồn 2 ✅ (ShuhaigeAdapter — mở full chương; JJWXC/Qidian bỏ, §10.1), duyệt glossary ✅ (glossary.dart nút duyệt term gợi ý), thông báo local ✅ (notify.dart — không cần FCM, xem §10.1); push từ server khi app kill hẳn: bỏ (cần Firebase) | ✅ |
| **P4** | Fallback đa provider tự động ✅ (`FallbackChain`), dashboard chi phí ✅ (`main.py cost` — thống kê token/model), export eval từ term_edit_history ⬜, Google/Apple sign-in ⬜, cân nhắc store ⬜ | 🔶 |

### 10.1 Nhật ký hiện trạng (2026-07-02)

**P1 hoàn tất:**
- Auth: chỉ đăng nhập, **đăng ký đã tắt** (app gỡ nút + Supabase tắt "Allow new users to sign up"). Tài khoản seed bằng `worker/seed_users.py` (idempotent): `demo1-4@novel.demo` / `Demo@123`, `admin@novel.demo` / `Admin@Novel#2026` (app_metadata.role=admin — hook sẵn cho RLS admin sau này).
- Tủ sách + tiến độ đọc: `app/lib/screens/library.dart`, providers trong `data.dart`; reader tự lưu chương đang đọc khi mở (chưa lưu scroll_offset — cột có sẵn, thêm khi cần); detail có nút bookmark + "Đọc tiếp chương X".
- 4 theme đọc (Sáng/Trắng/Xanh dịu/Tối): popup trong reader, lưu `shared_preferences`.
- Realtime: `chapterProvider` subscribe UPDATE trên chapters — chương dịch xong hiện ngay.

**P2 đã xong:**
- Tóm tắt liên chương: LLM xuất dòng `SUMMARY:` trong cùng call dịch → lưu `chapters.summary_vi` (migration 003) → bơm vào prompt chương kế (`prev_summary`).
- Cầu chì chất lượng dịch (worker): >5% ký tự Hán trong output HOẶC output <30% độ dài gốc → fail để retry/đổi provider (chặn vụ model trả nguyên văn tiếng Trung / trả rỗng).

**Provider (benchmark 2026-07-02):** `LLM_PROVIDER=nvidia,openrouter,fireworks`. NVIDIA `google/diffusiongemma-26b-a4b-it` (đổi 2026-07: sinh token nhanh + độ trễ thấp hơn qwen3.5), chính. OpenRouter `google/gemma-4-31b-it:free`: dịch hay nhất nhóm free nhưng 429 thường xuyên (1/3 OK) — lớp đỡ giữa. Fireworks trả phí — tấm chắn cuối. Các model free khác (qwen3-next, gpt-oss-120b, llama-3.3-70b) 429 liên tục, loại.

**Hạ tầng:** Supabase CLI đã link project — schema mới thêm file `supabase/migrations/00x_*.sql` rồi `supabase db push` (không paste SQL Editor nữa, tránh lặp lỗi drift). Đã vá 2 drift do chạy tay trước đây: trigger `handle_new_user` (002 — fix lỗi 500 khi tạo user), `claim_next_job` (004 — fix vòng lặp claim job chưa có content_zh).

**Dữ liệu:** truyện #1 dịch xong ~10/13 chương xếp hàng (chương 2-3 đã dịch lại sạch tiếng Trung). Chạy nốt: `python -m novelworker.main crawl` + `... translate` (2 cửa sổ, trong `worker/`, venv `E:\Novel_Project\.venv`).

**P2 xong thêm (2026-07-02):**
- Chunk chương dài: `_split_chunks` (worker.py) cắt >10k ký tự theo đoạn văn, dịch tuần tự, summary chunk trước làm ngữ cảnh chunk sau, cầu chì áp per-chunk.
- Job `patch` (migration 005 + `handle_patch`): string-replace `wrong_vi → correct_vi` trên các chương done, không tốn LLM.
- Glossary UI (`app/lib/screens/glossary.dart`, route `/novel/:id/glossary`, icon dịch ở detail): duyệt/bỏ term gợi ý, thêm/sửa/xóa term, nút "vá chương". Nút dịch lại chương trong reader (RPC `retranslate_chapter`). Migration 006: RLS cho user login sửa glossary + RPC `request_patch`/`retranslate_chapter`.

**Dịch bình luận Fanqie — tạm gác (khảo sát 2026-07-02):** web fanqienovel.com KHÔNG có bình luận (đã soi network trang /page và /reader — chỉ có `api/reader/full`, `api/reader/directory/detail`, không endpoint comment). Bình luận chỉ có trong app mobile, API `fqnovel.com` yêu cầu chữ ký thiết bị (X-Argus/X-Gorgon) — muốn làm phải sniff traffic từ Android thật/emulator. Hạ tầng phía mình đã sẵn (bảng `comments`, handler `comment_batch`); chỉ thiếu nguồn dữ liệu. → P2 coi như xong, quay lại nếu thật sự cần bình luận.

**Giới hạn crawl Fanqie web + lệnh `scan` (khảo sát 2026-07-02):** web reader fanqienovel.com mở ĐÚNG 10 chương đầu cho gần như MỌI truyện, phần còn lại khóa VIP (`isChapterLock`/`needPay` trong `api/reader/directory/detail`). Quét 720 truyện top đủ thể loại (nam+nữ): median chương mở = 10, chỉ 1 truyện ngoại lệ mở 110/402. → **không có cách "kiếm truyện mở nhiều chương" trên Fanqie web** ngoài trả phí VIP (cần login) hoặc sniff API app (token thiết bị X-Argus). Đã thêm lệnh `python -m novelworker.main scan [--gender 0|1] [--category <id>] [--min-open N]` (fanqie.py: `rank_categories`/`rank_books`/`chapter_lock_stats`) để tự lọc ra các ngoại lệ hiếm mở nhiều chương — chạy được không cần token. **Khảo sát nguồn thay thế (2026-07-02):**
- **Fanqie truyện cũ/hoàn thành:** tuổi truyện KHÔNG đổi giới hạn — truyện completed cũ vẫn mở 10 chương (đã chuyển 付费). Paywall là chính sách nền tảng, không phụ thuộc năm.
- **Web chính thống khác đều freemium như Fanqie:** 17K (`17k.com`, 200 OK), 纵横 (`zongheng.com`), 飞卢 (`b.faloo.com`, 200) — mở phần đầu, VIP phải trả. **Qidian** (`qidian.com`) chặn cứng (HTTP 202 anti-bot ngay request đầu). **JJWXC bỏ** — nữ tần (晋江: ngôn tình/đam mỹ), không hợp thị hiếu.
- **Web mở TOÀN BỘ chương free = web lậu (盗版):** 69书吧 (`69shuba.com`, 200, GBK), 笔趣阁 clones — mở hết chương nhưng là nội dung vi phạm bản quyền. Kỹ thuật khả thi (viết adapter được) nhưng cần cân nhắc pháp lý.
- **QUYẾT ĐỊNH (user 2026-07-02): làm nguồn lậu — chỉ 2-3 người dùng nội bộ, không cho đăng ký.** Đã thêm **ShuhaigeAdapter** (`crawler/shuhaige.py`, nguồn `shuhaige` migration 007): 书海阁 `shuhaige.net` mở TOÀN BỘ chương free, không Cloudflare (khác 69shuba — 69shu chặn CF ở trang `/txt/`), UTF-8, meta `og:*` + `div#intro`. Thêm truyện: `python -m novelworker.main add --source shuhaige --book-id <id>` (id = số trong URL shuhaige.net/<id>/). Đã kiểm chứng end-to-end: truyện 妙手神农 (#2, 4428 chương) → mục lục vào DB (batch upsert `db.upsert_chapter_stubs`, chunk 500) → fetch content_zh OK. Adapter khác nguồn cùng khuôn biquge (ddxsss/trxs/ptwxz) — đổi BASE + regex nếu shuhaige chết.
- **Review repo lncrawl (dipu-bd/lightnovel-crawler) 2026-07-02 — đọc source, không clone:** adapter `sources/zh/69shuba.py` + `shuhaige.py` chỉ dùng `requests`+`BeautifulSoup` (HTTP thuần, KHÔNG cloudscraper/browser/eval — bảo mật sạch). Điểm quan trọng: 69shuba.py **không vượt CF**, chỉ thử nhiều domain mirror (69shu.com, 69xinshu.com, 69shu.pro...). Đã test mirror: trang chủ + `/book/` (mục lục) KHÔNG CF trên mọi mirror sống, nhưng `/txt/` (NỘI DUNG chương) VẪN 403 CF trên tất cả (69shu.com, 69shuba.com). → **lncrawl adapter cũng sẽ ăn 403 ở download_chapter_body như curl thuần** — không có phép màu, chỉ chạy khi 69shu tạm tắt CF hoặc cắm FlareSolverr. Kết luận cuối: nội dung 69shu = ngõ cụt HTTP thuần, bắt buộc browser nền. shuhaige.py của lncrawl (m.shuhaige.net, phân trang) trùng kết luận: shuhaige HTTP thuần chạy tốt — ShuhaigeAdapter của ta (www desktop, 1-trang mục lục) đơn giản hơn.
- **Review 6 repo crawler 69shu (2026-07-02, đọc source không clone) — cơ chế lấy NỘI DUNG chương:**
  - `lncrawl` (dipu-bd): HTTP thuần (requests+bs4) → 403 khi CF bật. Bảo mật sạch.
  - `work_crawler` (kanasimi, CeJS/Node, base `69shuba.cx`): HTTP thuần → cũng 403 ở /txt/. Repo ghi lịch sử đổi domain 69shu 7 lần 2018-2025. Bảo mật sạch (repo lớn uy tín).
  - `NovelDownloader` (RaghavendraGaleppa): **dùng Selenium headless** ("Uses Selenium with delays to avoid detection") — cách DUY NHẤT lấy được /txt/. Cần chromedriver + pandoc.
  - `so-novel` (freeok): Java, có `bundle/rules/cloudflare.json` (cơ chế CF riêng, khả năng webview).
  - `epub-crawler` (evan361425), `pseudonym123/tutorial`: chỉ config/selector, không cơ chế CF.
  - **Test 9 mirror** (com, .cx, www.cx, .top, xinshu, .pro, shubar, yuedu, shubar): trang chủ + `/book/` (mục lục) KHÔNG CF ở tất cả; `/txt/` (nội dung chương) 403 CF ở TẤT CẢ mirror sống (.cx cũng dính). .top là trang parking.
  - **KẾT LUẬN DỨT ĐIỂM:** không mirror/repo/thư viện HTTP nào lấy được nội dung chương 69shu — CF managed chỉ chặn đúng /txt/. Repo lấy được đều dùng browser (Selenium/webview). Tự động hoá 69shu = bắt buộc FlareSolverr/Selenium (Docker/chromedriver mỗi máy). shuhaige HTTP thuần vẫn là lựa chọn đúng (lncrawl cũng crawl shuhaige bằng HTTP thuần).
- **Thông báo local (không Firebase) — `app/lib/notify.dart`:** dùng `flutter_local_notifications` v22 (API named param: `initialize(settings:)`, `show(id:title:body:notificationDetails:)`) + `POST_NOTIFICATIONS` trong AndroidManifest. `ChapterNotifier` nghe Realtime bảng chapters (UPDATE), lọc client: chương chuyển `done` + truyện trong tủ sách user, dedupe theo chapter id/phiên → `_plugin.show()` bắn notification lên thanh hệ thống. Gọi `initNotifications()` + `chapterNotifier.start()` trong `main()`. **Giới hạn (bản chất không-push):** hiện notification khi app foreground OK; app background chỉ nhận trong khoảng OS chưa suspend process/websocket (vài giây–phút); app **kill hẳn thì KHÔNG** (cần FCM/APNs — đã bỏ). init/show bọc try/catch để không chặn app trên nền chưa hỗ trợ (Windows dev). **iOS:** đã `flutter create --platforms=ios .` (deployment target 13.0 ở cả 3 config — iOS 16 chạy tốt, khớp yêu cầu iOS 13 của package); AppDelegate.swift thêm `UNUserNotificationCenter.current().delegate` để hiện notification khi foreground; show bật `presentAlert/presentBanner/presentSound` cho iOS foreground. `flutter analyze` sạch; **chưa build thử trên thiết bị/emulator thật** (iOS cần Mac + Xcode; Android cần thiết bị).
- **Dọn schema novels (migration 008):** bỏ hẳn `tags`, `rating_source`, `rating_count`, `word_count` — không nguồn nào (Fanqie/shuhaige) điền, app không đọc. Giữ `genres` + `last_chapter_at`. ShuhaigeAdapter giờ lấy `last_chapter_at` từ `og:novel:update_time`. shuhaige KHÔNG có bình luận (biquge tĩnh, không khối 评论/form) — bảng `comments`/handler `comment_batch` chỉ dùng cho Fanqie sau này (nếu làm được).
- **Gói VIP tham khảo:** Fanqie 会员 ~19 CNY/tháng (chủ yếu bỏ quảng cáo + short drama; truyện 付费 tính riêng theo chương) — VIP mở chương khóa nhưng cần cookie login, không đáng khi có shuhaige free. **Qidian VIP crawl: về kỹ thuật được nhưng cực nặng** (anti-bot 202 + login tài khoản đã mua chương + font woff động đổi mỗi trang + nội dung付费 tải động/mã hóa) — với shuhaige mở full free thì KHÔNG đáng, bỏ.

## 11. Rủi ro kỹ thuật chính (đã điều chỉnh cho quy mô cá nhân, 1-2 user / 2-3 máy)

- **Font obfuscation Fanqie — ✅ đã giải bằng bảng tĩnh, kiểm chứng chạy thật:** bảng tráo `_FQ_CHARSET` nhúng trong code decode được toàn bộ; ký tự lạ bù bằng `FANQIE_FONT_MAP`, sót ≤10 thay `□`, sót nhiều **từ chối lưu** (không đốt tiền LLM dịch rác). Rủi ro còn lại: Fanqie đổi bảng tráo hoặc cấu trúc trang — adapter đã cô lập nên sửa nhanh.
- **Qidian anti-bot — bỏ khỏi scope:** dùng cá nhân thì Fanqie (+ JJWXC nếu cần) là đủ, không đáng đầu tư.
- **Chi phí LLM — ✅ 4 lớp:** lazy translate + dịch-1-lần-dùng-chung + bắt buộc login + **cầu chì `MAX_CHAPTERS_PER_DAY=200`** trong worker (chạm trần là tạm dừng tới 00:00 UTC, chống bug spam). Token từng chương vẫn ghi vào DB để soi.
- **Job kẹt khi máy sập/ngủ — ✅ reaper trong worker:** 2-3 máy cá nhân hay tắt/ngủ đột ngột; job `running` quá `STALE_JOB_MINUTES=10` tự trả về hàng đợi, máy nào còn sống dịch tiếp. Lưu ý vận hành duy nhất: **mỗi máy đặt `WORKER_ID` khác nhau** trong `.env`.
- ~~Queue nghẽn khi đông user~~ — không tồn tại ở quy mô này; `SKIP LOCKED` vốn đã scale thừa.
