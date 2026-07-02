# Kế hoạch: Ứng dụng đọc tiểu thuyết mạng Trung → Việt (dịch bằng LLM)

**Stack đã chốt:** Flutter (Android + iOS) · Supabase (DB/Auth/Realtime/Storage) · Backend worker riêng (crawl + dịch) · DeepSeek qua OpenRouter/Fireworks (+ NVIDIA NIM free làm dự phòng)

> ⚠️ **Lưu ý pháp lý:** Nội dung Qidian/Fanqie/JJWXC có bản quyền. Crawl + dịch + phân phối công khai có rủi ro pháp lý (DMCA, khóa store). Nếu phát hành rộng, cân nhắc giới hạn người dùng, không thu phí nội dung, và chuẩn bị cơ chế gỡ truyện theo yêu cầu.

---

## 1. Kiến trúc tổng thể

```
┌─────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│ Flutter App │◄───►│ Supabase             │◄───►│ Worker Backend  │
│ (iOS/Andr.) │     │ Postgres · Auth      │     │ (Node/Python,   │
│             │     │ Realtime · Edge Fn   │     │  Railway/VPS)   │
└─────────────┘     └──────────────────────┘     └───────┬─────────┘
                                                          │
                                              ┌───────────┴───────────┐
                                              │ Crawl: Qidian, Fanqie,│
                                              │ JJWXC (proxy pool)    │
                                              │ Dịch: DeepSeek qua    │
                                              │ OpenRouter/Fireworks  │
                                              └───────────────────────┘
```

**Phân vai:**

- **Flutter app**: chỉ đọc/ghi Supabase (qua RLS), không bao giờ gọi trực tiếp web nguồn hay LLM. Nghe Realtime để biết chương mới dịch xong.
- **Supabase**: nguồn dữ liệu duy nhất. Postgres lưu toàn bộ (không có offline, đúng yêu cầu). Auth Google/Apple. Edge Functions cho tác vụ nhẹ (ví dụ: nhận request "dịch tiếp truyện X" rồi đẩy vào hàng đợi).
- **Worker backend**: 2 tiến trình — **Crawler** (đồng bộ nguồn theo lịch) và **Translator** (consumer hàng đợi dịch). Chạy trên Railway/Fly.io/VPS. Dùng `pgmq` hoặc bảng `translation_jobs` trong chính Supabase làm queue (khỏi cần Redis giai đoạn đầu).

**Vì sao Supabase thay vì Firebase:** truyện cần query quan hệ nặng (lọc thể loại + trạng thái + sắp xếp theo đánh giá + join tủ sách + tiến độ đọc) — Postgres làm việc này tự nhiên, Firestore rất gượng và tốn tiền theo lượt đọc. Realtime của Supabase đủ cho việc báo "chương mới dịch xong".

---

## 2. Schema cơ sở dữ liệu (Postgres/Supabase)

```sql
-- Nguồn crawl
sources (id, name, base_url, lang, crawl_interval_min, enabled)

-- Truyện: đủ metadata như yêu cầu
novels (
  id, source_id, source_novel_id, source_url,
  title_zh, title_vi,                 -- tên gốc + tên dịch
  author_zh, author_vi,
  cover_url,
  description_zh, description_vi,     -- giới thiệu
  genres text[],                      -- thể loại (đã dịch)
  tags text[],
  status,                             -- 'ongoing' | 'completed' | 'hiatus'
  chapter_count_source int,           -- số chương hiện có ở nguồn
  chapter_count_translated int,       -- số chương đã dịch xong
  rating_source numeric, rating_count int,   -- đánh giá từ nguồn
  word_count bigint,
  last_chapter_at timestamptz,        -- chương mới nhất bên nguồn
  meta_translated bool default false, -- metadata đã dịch chưa
  created_at, updated_at
)

-- Chương
chapters (
  id, novel_id, chapter_index int, 
  title_zh, title_vi,
  content_zh text,                    -- raw crawl (có thể xoá sau khi dịch để tiết kiệm)
  content_vi text,                    -- bản dịch
  translation_status,                 -- 'none'|'queued'|'translating'|'done'|'failed'
  translated_at, model_used, token_cost,
  UNIQUE(novel_id, chapter_index)
)

-- Bình luận crawl từ nguồn (dịch để user chọn truyện)
comments (
  id, novel_id, source_comment_id,
  username, content_zh, content_vi,
  likes int, posted_at, translation_status
)

-- Hàng đợi dịch
translation_jobs (
  id, type,               -- 'metadata' | 'chapter' | 'comment_batch'
  novel_id, chapter_id,
  priority int,           -- truyện mới đăng = ưu tiên cao
  status, attempts, error, created_at, started_at, done_at
)

-- Glossary sửa lỗi dịch (tính năng "Lâm Tùng vs rừng Tùng")
glossary_terms (
  id, novel_id,           -- null = áp dụng toàn cục
  term_zh,                -- 林松
  wrong_vi,               -- "rừng Tùng" (bản dịch sai đã gặp)
  correct_vi,             -- "Lâm Tùng"
  term_type,              -- 'person'|'place'|'sect'|'item'|'skill'|'other'
  created_by uuid,        -- user đề xuất
  scope,                  -- 'user'|'novel'|'global'
  approved bool,          -- global cần duyệt, novel-level áp dụng ngay
  usage_count int, created_at
)

-- Lịch sử sửa từ của user (để học và hoàn tác)
term_edit_history (id, user_id, chapter_id, glossary_term_id, before, after, created_at)

-- Người dùng & tủ sách
profiles (id → auth.users, display_name, avatar_url, settings jsonb)
library (user_id, novel_id, added_at, PRIMARY KEY(user_id, novel_id))
reading_progress (user_id, novel_id, chapter_index, scroll_offset, updated_at)
```

**RLS:** `novels/chapters/comments/glossary(global,approved)` đọc công khai (authenticated); `library/reading_progress/term_edit_history` chỉ chủ sở hữu; ghi vào bảng nội dung chỉ qua service role (worker).

---

## 3. Pipeline crawl & đồng bộ nguồn

1. **Discovery (mỗi 30–60 phút / nguồn):** crawler quét trang "mới cập nhật / mới đăng" của Qidian, Fanqie, JJWXC → upsert `novels` (metadata tiếng Trung) → tạo job `metadata` priority cao cho truyện **mới đăng**.
2. **Dịch metadata trước:** worker dịch tên truyện, tác giả, giới thiệu, thể loại → set `meta_translated = true` → app hiển thị ngay ở tab "Mới cập nhật" để bạn **xem trước rồi mới chọn tải**.
3. **Dịch bình luận:** khi user mở trang chi tiết truyện lần đầu (hoặc kèm luôn bước 2 cho truyện hot), crawl 20–50 bình luận nổi bật → job `comment_batch` → dịch gộp 1 lần gọi LLM (rẻ) → hiển thị để hỗ trợ quyết định.
4. **Theo dõi chương mới:** với truyện đã có trong ít nhất 1 tủ sách, crawler kiểm tra định kỳ `chapter_count_source`; có chương mới → cập nhật + (nếu user đang đọc sát đầu tiến độ) tự đẩy job dịch.
5. **Chống chặn:** rate-limit theo domain, proxy xoay vòng, user-agent thật, cache HTML. Mỗi nguồn 1 adapter riêng (`QidianAdapter`, `FanqieAdapter`, `JjwxcAdapter`) cùng interface: `fetchLatest()`, `fetchNovelMeta()`, `fetchChapterList()`, `fetchChapter()`, `fetchComments()`.

---

## 4. Pipeline dịch lazy (đúng luồng bạn mô tả)

```
User bấm "Đọc truyện" ──► Edge Function tạo jobs chương 1–10 (priority cao)
        │
        ▼
Worker dịch tuần tự, xong chương nào ghi content_vi + status='done'
App nghe Realtime trên chapters ──► chương hiện dần, user đọc được ngay từ ch.1
        │
User đọc tới chương N, còn lại < 4 chương đã dịch (ví dụ đọc ch.6–7/10)
        │
        ▼
App gọi Edge Function "extend" ──► tạo jobs tới chương 20 (rồi 30, 40, ...)
```

- **Quy tắc prefetch:** `nếu (số chương đã dịch − chương đang đọc) ≤ 3 → dịch thêm 10 chương`. Ngưỡng và batch size để trong config, chỉnh được.
- **Idempotent:** job có `UNIQUE(chapter_id)` khi status chưa done — nhiều user cùng đọc 1 truyện không tạo job trùng, và người sau hưởng bản dịch có sẵn (dịch 1 lần, phục vụ mọi người).
- **Prompt dịch mỗi chương gồm:** (a) hướng dẫn văn phong tiểu thuyết mạng VN (giữ xưng hô ta–ngươi/huynh–đệ theo thể loại, Hán Việt tên riêng), (b) **glossary của truyện đó** (term_zh → correct_vi) bơm vào system prompt, (c) tóm tắt ngắn ngữ cảnh chương trước để mạch dịch nhất quán.
- **Model:** chính = DeepSeek V3/R1-distill qua OpenRouter hoặc Fireworks (rẻ, mạnh tiếng Trung); dự phòng/miễn phí = NVIDIA NIM. Tầng dịch trừu tượng hóa (interface `TranslationProvider`) để đổi model không sửa pipeline; lưu `model_used` từng chương để so chất lượng.
- **Chi phí tham khảo:** chương ~3.000 chữ ≈ 5–6k token vào + 4–5k ra → với giá DeepSeek hiện tại khoảng **$0.003–0.01/chương**; 1.000 chương ≈ vài đô. Retry tối đa 3 lần, quá thì `failed` + hiện nút "Dịch lại" trong app.

---

## 5. Glossary — sửa tên riêng ngay khi đọc

Luồng trong màn hình đọc:

1. User **nhấn giữ / chạm** vào từ hoặc cụm từ dịch sai ("rừng Tùng") → bottom sheet hiện: từ gốc tiếng Trung tương ứng (nếu map được), ô nhập bản đúng ("Lâm Tùng"), chọn loại (tên người/địa danh/môn phái/…), phạm vi (chỉ truyện này / đề xuất toàn cục).
2. Lưu → ghi `glossary_terms` + `term_edit_history`; app **thay thế tức thì** trong các chương đã dịch của truyện đó (find-replace phía server, đánh dấu chương đã vá).
3. Từ đó về sau, mọi job dịch của truyện này bơm glossary vào prompt → **LLM không lặp lại lỗi**. Term dùng nhiều (`usage_count` cao) ở nhiều truyện có thể duyệt lên global — đây chính là cơ chế "thu thập các kiểu dịch để tự tối ưu model" mà không cần fine-tune.
4. Về sau khi dữ liệu đủ lớn: export cặp (bản LLM, bản đã sửa) làm bộ eval/few-shot, thậm chí fine-tune model rẻ.

*Kỹ thuật map từ Việt → từ Trung gốc:* khi dịch, yêu cầu LLM trả kèm bảng tên riêng phát hiện được trong chương (JSON phụ) → lưu sẵn, giúp bottom sheet gợi ý chính xác `term_zh`.

---

## 6. Giao diện (Flutter)

**Nguyên tắc:** hiện đại, tối giản, "sáng đúng lúc – tối đúng chỗ", ưu tiên mắt người đọc. Material 3 + dynamic color, tham khảo bố cục app đọc của chính Qidian/Fanqie (thẻ truyện bìa lớn, tab thể loại, thanh tiến độ đọc).

Màn hình chính:

1. **Khám phá:** tab "Mới đăng" (metadata vừa dịch xong — realtime), "Đang hot", lọc theo thể loại/trạng thái/nguồn, tìm kiếm.
2. **Chi tiết truyện:** bìa, tên Việt (+ tên gốc nhỏ), tác giả, thể loại, trạng thái, số chương nguồn / số chương đã dịch, đánh giá, giới thiệu, **tab bình luận đã dịch**, nút "Thêm vào tủ & bắt đầu dịch".
3. **Trình đọc:** 
   - Theme: Sáng / Tối AMOLED / Sepia / Xám ấm; tự đổi theo hệ thống + tùy chọn hẹn giờ tối.
   - Chỉnh font (có font serif tiếng Việt tốt như Literata/Noto Serif), cỡ chữ, giãn dòng, lề, độ sáng riêng trong app, chế độ cuộn dọc hoặc lật trang.
   - Nhấn giữ từ → sửa glossary (mục 5). Cuối chương: trạng thái chương kế ("Đang dịch…" với progress realtime).
4. **Tủ sách (theo tài khoản):** lưới bìa truyện, badge số chương mới, tiến độ đọc đồng bộ mọi thiết bị.
5. **Cài đặt:** tài khoản, theme, quản lý glossary cá nhân, lịch sử sửa từ.

**Kiến trúc app:** Riverpod (state) + go_router + supabase_flutter; cache bộ nhớ phiên làm việc (không offline theo yêu cầu — thoát app đọc lại từ DB).

---

## 7. Auth & tài khoản

- Supabase Auth: **Sign in with Google + Sign in with Apple** (Apple bắt buộc trên iOS khi có social login).
- Trigger `on auth.users insert` → tạo `profiles`. Mỗi account 1 tủ sách + tiến độ đọc riêng (RLS theo `user_id`).
- Khách chưa đăng nhập: được duyệt/khám phá, muốn thêm tủ sách hoặc kích hoạt dịch thì yêu cầu đăng nhập (chặn lạm dụng chi phí LLM). Thêm rate-limit: mỗi user tối đa X truyện kích hoạt dịch/ngày.

---

## 8. Roadmap

| Giai đoạn | Thời gian gợi ý | Nội dung |
|---|---|---|
| **P0 – Nền móng** | 1–2 tuần | Supabase schema + RLS; worker skeleton + queue; adapter 1 nguồn (chọn Fanqie hoặc JJWXC trước — Qidian chống bot gắt nhất); pipeline dịch chương end-to-end bằng DeepSeek |
| **P1 – MVP** | 3–4 tuần | Flutter: auth Google/Apple, Khám phá + chi tiết truyện (metadata dịch), trình đọc + theme sáng/tối, tủ sách, luồng dịch lazy 10→20 chương với Realtime |
| **P2 – Chất lượng dịch** | 2–3 tuần | Glossary + sửa từ khi đọc + vá chương cũ; dịch bình luận; tóm tắt ngữ cảnh liên chương; nút dịch lại |
| **P3 – Mở rộng** | 2–3 tuần | Thêm 2 nguồn còn lại; proxy pool + giám sát crawler; duyệt glossary global; thông báo đẩy chương mới; polish UI (animation, sepia, hẹn giờ theme) |
| **P4 – Vận hành** | liên tục | Dashboard chi phí token, fallback đa model, export dữ liệu sửa lỗi làm eval, cân nhắc phát hành store |

**Chi phí vận hành ước tính giai đoạn đầu:** Supabase Free/Pro ($0–25/th) + Railway worker (~$5–10/th) + proxy (~$10–30/th nếu cần) + DeepSeek API (theo lượng đọc, vài đô/nghìn chương).

---

## 9. Rủi ro chính & đối sách

- **Chống bot (nhất là Qidian):** bắt đầu bằng nguồn dễ, đầu tư adapter + proxy dần; luôn cache raw để không crawl lại.
- **Bản quyền / store review:** rủi ro lớn nhất khi phát hành công khai — cân nhắc phân phối APK/TestFlight nội bộ trước.
- **Chi phí LLM phình:** lazy translation + dịch-một-lần-dùng-chung + rate-limit user đã khống chế phần lớn; theo dõi `token_cost` từng chương.
- **Chất lượng dịch tên riêng:** glossary là lời giải chính; bổ sung bảng Hán-Việt chuẩn cho tên người làm mặc định.
