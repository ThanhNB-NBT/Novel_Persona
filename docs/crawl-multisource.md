# Thiết kế: Crawl nhiều nguồn (multi-source)

> Trạng thái: **Pha 1 đã code** (2026-07-04) — nền đa nguồn. Pha 2-5 còn thiết kế.
> Quyết định đã chốt: dedup nhẹ (`dedup_key`+`is_canonical`) · auto-discovery từ trang ranking · làm theo pha.
>
> **Pha 1 done:** migration `013_multisource.sql` (schema + seed) · `crawler/biquge.py` (BiqugeAdapter config-driven, tổng quát hoá shuhaige) · `crawler/registry.py` · `build_adapters()` động từ DB trong `main.py` · `base.py` giữ session/`_get` dùng chung · `shuhaige.py` đã xoá (thành 1 dòng sources template=biquge). Test: `worker/test_biquge.py`.
> **Pha 2 — nửa dedup ĐÃ code (2026-07-04):** `dedup_key()` (chuẩn hoá title+author), `recompute_canonical()` (chọn bản meta_priority nhỏ nhất, hoà→nhiều chương), `backfill_dedup_keys()` (chạy 1 lần lúc crawler start, tự lành truyện cũ) trong `crawler/sync.py`; wire `dedup_key`+recompute vào `add_novel` & `discover_latest`; `discover_latest` chuyển METADATA-ONLY (bỏ tải mục lục/chương — doc §3.5); app `data.dart` thêm `.eq('is_canonical', true)` vào 3 provider Khám phá (novels/search/homeSections). Test `worker/test_dedup.py`.
> **Pha 2 — discovery ĐÃ code (2026-07-04, có trần):** `DingdianAdapter.fetch_latest` quét `/category/{c}.html` (phân trang `_2/_3…`) → danh sách slug (nhẹ). `discover_latest` rewrite: truyện MỚI → gọi `fetch_novel_meta` lấy đủ metadata → upsert+dedup → enqueue dịch metadata (chỉ canonical); truyện đã có: bỏ qua. **Trần `settings.discover_new_per_cycle=50`** truyện mới/nguồn/chu kỳ (cầu chì chống tràn + đốt token; API free chỉ rate-limit nên đặt rộng). Test live: ddxs lấy 25 truyện unique + enrich ok. `BiqugeAdapter.fetch_latest` vẫn `[]` (shuhaige homepage hay timeout + là 盗版 nên discovery ít cần).
>
> **Pha 2 — theo dõi chương mới truyện ĐÃ CÓ (2026-07-04):** "Mới cập nhật" phải gồm cả truyện cũ vừa ra chương, không chỉ truyện mới. `sync_chapter_list` chỉ bump `last_chapter_at`+`updated_at` KHI thật có chương mới (trước đây bump mỗi lần soi → nhiễu sort). `refresh_canonical_updates(adapter, limit)` soi mục lục truyện canonical của nguồn (không chỉ tủ sách), xoay vòng theo cột mới `novels.last_checked_at` (NULL/cũ nhất trước, migration `015`), trần `settings.refresh_per_cycle=60`/nguồn/chu kỳ. Nguồn nhóm này KHÔNG cho tín hiệu update rẻ (ddxs trang truyện 2.9KB không có 最新章节/update_time; shuhaige trang truyện = cả mục lục) → đành fetch 1 trang mục lục/truyện (stub, không tải nội dung). main.py gọi trong nhánh discovery-cycle sau sync_followed_novels.
> **Sức khoẻ nguồn — TỰ TẮT nguồn chết (2026-07-04):** dùng cột `sources.last_ok_at`/`fail_count` sẵn có (013), không migration mới. `SourceAdapter._get` đếm `fetch_ok`/`fetch_err`. Cuối mỗi chu kỳ discovery, `main._eval_source_health`: có ≥1 fetch OK → `mark_source_ok` (reset fail); TOÀN fetch fail → `mark_source_fail` (fail_count++, tự `enabled=false` khi ≥`source_fail_limit=5` chu kỳ). Đo theo "toàn fail" nên KHÔNG tắt oan nguồn còn sống (shuhaige homepage flaky nhưng trang truyện OK → luôn có fetch_ok). Test `test_health.py`.
> **Cache bìa — Storage bucket ĐÃ làm (2026-07-04):** migration `017_covers_bucket.sql` (bucket public `covers`). `SourceAdapter.fetch_bytes(url)` tải nhị phân (không đụng bộ đếm health). `sync.cache_cover(adapter, novel_id, external_url)`: tải bìa ngoài → `db.upload_cover` lên Storage → trả public URL; idempotent (URL đã storage → bỏ qua), ảnh <100 byte/lỗi → giữ hotlink cũ. Gọi trong `add_novel` + `discover_latest` (`_cache_cover_and_update`). Bìa hết phụ thuộc hotlink CDN nguồn (ddxs mượn CDN quanben5, dễ chết). Test `test_cover.py`.
> **Chưa làm (cố ý — YAGNI cho tool 2-3 người):** Pha 4 UI quản lý nguồn + probe tự động (thêm nguồn cực hiếm, đã probe tay đủ) · Pha 5 fallback domain (nguồn chết đã tự tắt là đủ) · nhóm 新笔趣阁 (biến thể article/pagination). Bật lại nguồn tự-tắt: sửa `enabled=true` trong bảng sources rồi restart worker.
>
> **Probe thật CẢ 12 nguồn "Có" — 2026-07-04** (chạy BiqugeAdapter với book_id thật lấy từ homepage). Kết luận: **chỉ `shuhaige` drop-in; 11 nguồn còn lại đều lệch khuôn, KHÔNG "1 dòng INSERT".**
>
> | Nguồn | Kết quả probe | Vướng |
> |---|---|---|
> | **shuhaige** ✅ | meta + 3419 chương đúng thứ tự 1→N + nội dung hán 0.86 | (đang chạy, đủ dùng) |
> | xsbique, uuxs, xslou | nội dung trong `<article class="font_max">` + **phân trang** `第(1/N)页` (URL `{cid}_2.html`); **mục lục trên trang truyện bị CẮT** (xsbique: 115 link cho truyện 448 chương — chỉ hiện block "最新章节") | cần content-by-class + gộp trang chương + **phân trang MỤC LỤC** |
> | qiushubang | nội dung `div#content` OK nhưng mục lục cũng chỉ hiện ~50 chương mới nhất (đảo thứ tự); có watermark inline chữ fullwidth trong text | mục lục cắt + rác inline |
> | 521danmei | parse được (content `div#acontent`, id không phải attr đầu → đã sửa regex) NHƯNG là **BL có tag H** | cần lọc nội dung, không hợp app phổ thông |
> | biqulao | timeout lặp | hạ tầng chập chờn |
> | **ddxs** (dingdian-xiaoshuo.com) ✅ | probe SÂU 2026-07-04: khuôn RIÊNG 顶点 nhưng SẠCH — mục lục đầy đủ 1→N ở `/n/{slug}/xiaoshuo.html` (367 ch, không phân trang), nội dung `div.articlebody` hán 0.87. **ĐÃ THÊM** qua `DingdianAdapter` (template `dingdian`, migration 014). | book_id = slug chữ; meta từ `<title>`/description (không og:) |
> | quanben5, kujiang, faloo | probe sâu: faloo = **font-obfuscation + VIP + anti-crawl** (title mojibake); kujiang = homepage 41 byte (JS-render/chặn, cần headless); quanben5 = timeout lặp (hạ tầng chập chờn) | KHÔNG cứu bằng HTTP thường |
> | ikshu8 | mobile `m.xikshu8.com`, không dò được link truyện qua regex thường | cần khảo sát riêng |
>
> → Bài học chốt: khảo sát "truy cập được + có metadata" KHÁC "cùng khuôn HTML shuhaige". Điểm chết chung của nhóm 新笔趣阁 (xsbique/uuxs/xslou/qiushubang): **trang truyện chỉ liệt kê chương MỚI NHẤT, không phải mục lục đầy đủ** → muốn đủ chương phải crawl phân trang mục lục. Đây là code không nhỏ + từng site còn wart khác → **CHƯA làm** (chỉ nếu shuhaige+ddxs thiếu hàng; 1 biến thể mở được 3-4 site, cần content-by-class + gộp trang chương + phân trang mục lục).
>
> **Nguồn đang bật (2 khuôn, 2 template):** `shuhaige` (biquge) · `ddxs` (dingdian, thêm 2026-07-04 sau probe sâu). Thêm truyện ddxs: `add --book-id <slug> --source ddxs` (slug lấy từ URL `/n/{slug}/`). Adapter mới: `crawler/dingdian.py`, test `test_dingdian.py`.
>
> Cải tiến phụ đã làm khi probe: content regex trong `biquge.py` cho phép `id` không nằm attr đầu (`<div class=x id=content>`), tổng quát hơn, shuhaige vẫn pass.

## 1. Mục tiêu & phạm vi

App cần crawl **2 thứ khác nhau** từ nhiều nguồn tiếng Trung:

| Luồng | Tần suất | Lấy gì | Phục vụ |
|---|---|---|---|
| **A. Discovery / Metadata** | định kỳ, tự động | tên, tác giả, bìa, mô tả, thể loại, trạng thái, số chương | tab **Khám phá** |
| **B. Nội dung chương** | lazy (khi user đọc) | `content_zh` → dịch | màn Đọc |

Luồng B đã ổn (lazy, không tải thừa). Trọng tâm bản thiết kế này là **làm luồng A cho nhiều nguồn mà không loạn/trùng/chết**, dựa trên khảo sát 93 nguồn (xem [docs/nguon-crawl.md](docs/nguon-crawl.md)).

Nguyên tắc bao trùm: **giữ interface `SourceAdapter` hiện tại** (nó tốt), chỉ đổi cách *cấu hình & điều phối* adapter. Không viết lại từ đầu.

## 2. Vấn đề của kiến trúc hiện tại khi lên nhiều nguồn

| # | Hiện tại | Vấn đề khi ≥10 nguồn |
|---|---|---|
| 1 | `ADAPTERS = [ShuhaigeAdapter()]` hardcode trong `main.py`; mỗi nguồn 1 class | 85 nguồn ≠ 85 class. Phần lớn cùng khuôn HTML biquge → lặp code khổng lồ |
| 2 | Mỗi `(source, source_novel_id)` là 1 dòng `novels` riêng | Cùng truyện trên 10 site → Khám phá đầy bản trùng |
| 3 | `fetch_latest()` trả `[]`, thêm truyện thủ công theo id | Khám phá không tự đầy — trái mục tiêu "tự động crawl" |
| 4 | `sources` chỉ có `name/base_url/enabled` | Không lưu được: khuôn nào, selector riêng, độ ưu tiên, domain dự phòng, sức khoẻ |
| 5 | Bìa hotlink thẳng từ nguồn | Nguồn chết/chặn hotlink → bìa hỏng hàng loạt ở Khám phá |

## 3. Kiến trúc đề xuất

### 3.1. Adapter theo KHUÔN, nạp động từ DB

**Nhận ra cốt lõi:** `shuhaige` chính là một biquge-clone. Các nguồn nhóm "Có" (biqulao, xsbique, ddxs, uuxs, quanben5…) cùng khuôn. → Không viết adapter per-site, viết **adapter per-template**:

```
crawler/
  base.py        # SourceAdapter (giữ nguyên interface 5 method)
  biquge.py      # BiqugeAdapter(base_url, config)  ← tổng quát hoá shuhaige.py
  faloo.py       # FalooAdapter   (khuôn khác)
  sfacg.py       # SfacgAdapter   (light novel, khuôn khác)
  ...            # thêm khuôn mới CHỈ khi HTML thật sự khác
  sync.py
  registry.py    # TEMPLATE_REGISTRY = {"biquge": BiqugeAdapter, "faloo": FalooAdapter, ...}
```

`main.py` dựng adapter **từ bảng `sources`** lúc khởi động, không hardcode:

```python
def build_adapters() -> dict[str, SourceAdapter]:
    rows = db.sb().table("sources").select("*").eq("enabled", True).execute().data
    out = {}
    for s in rows:
        cls = TEMPLATE_REGISTRY.get(s["template"])
        if not cls:
            log.warning("Chưa hỗ trợ template '%s' (nguồn %s)", s["template"], s["name"])
            continue
        out[s["name"]] = cls(base_url=s["base_url"], config=s["config"], source_row=s)
    return out
```

→ **Thêm 1 site biquge-clone = 1 dòng INSERT vào `sources`, KHÔNG code.**

`ShuhaigeAdapter` hiện tại → regex/logic của nó thành **mặc định của `BiqugeAdapter`**. `shuhaige` trở thành 1 dòng `sources` với `template='biquge'`, `config` rỗng (dùng toàn mặc định).

### 3.2. Cấu hình khuôn (`sources.config` jsonb)

Mỗi khuôn có selector mặc định trong class; `config` chỉ override phần *khác*. Ví dụ biquge:

```jsonc
{
  "novel_path":    "/{book_id}/",              // trang truyện
  "chapter_path":  "/{book_id}/{chapter_id}.html",
  "content_sel":   "div#content",              // block nội dung chương
  "list_link_re":  "/{book_id}/(\\d+)\\.html", // regex link chương trong mục lục
  "latest_path":   "/xclass/1/1.html",         // trang ranking/mới cập nhật (cho discovery)
  "ad_markers":    ["请记住本站", "手机版"],      // dòng rác cần lọc ở cuối chương
  "encoding":      "utf-8"
}
```

Site nào giống hệt mặc định thì `config = {}`. Site lệch (vd đường dẫn `/book/{id}/`) chỉ ghi field khác.

### 3.3. Thay đổi schema

**Bảng `sources`** (migration mới, không phá dữ liệu cũ — đều có default):

```sql
alter table sources add column if not exists template text not null default 'biquge';
alter table sources add column if not exists config jsonb not null default '{}';
alter table sources add column if not exists meta_priority int not null default 100; -- nhỏ = ưu tiên metadata cao khi trùng
alter table sources add column if not exists fallback_domains text[] not null default '{}';
alter table sources add column if not exists last_ok_at timestamptz;
alter table sources add column if not exists fail_count int not null default 0;
-- 'enabled' đã có sẵn
```

**Bảng `novels`** (cho chống trùng):

```sql
alter table novels add column if not exists dedup_key text;
alter table novels add column if not exists is_canonical boolean not null default true;
create index if not exists idx_novels_dedup on novels (dedup_key);
create index if not exists idx_novels_canonical on novels (is_canonical) where is_canonical;
```

Query Khám phá (app) lọc thêm `is_canonical` — **đúng pattern `hidden` đã có**:
`.eq('is_canonical', true).eq('hidden', false)`
Áp vào: `novelsProvider`, `homeSectionsProvider`, `searchProvider`.

### 3.4. Chống trùng (dedup) — thuật toán

**Khoá trùng** = chuẩn hoá `title_zh` + `author_zh`:

```python
def dedup_key(title_zh: str, author_zh: str | None) -> str:
    def norm(s: str) -> str:
        s = unicodedata.normalize("NFKC", s or "")
        s = re.sub(r"[\s\W_]+", "", s)      # bỏ khoảng trắng, dấu câu, ký tự đặc biệt
        return s.lower()
    return f"{norm(title_zh)}|{norm(author_zh)}"
```

**Chọn bản canonical:** sau mỗi lần upsert 1 truyện, tính lại cả nhóm cùng `dedup_key`:
- Bản `is_canonical=true` = bản có `sources.meta_priority` **nhỏ nhất** (nguồn metadata tốt nhất), tie-break theo `chapter_count_source` lớn hơn.
- Các bản còn lại `is_canonical=false` → vẫn **đọc được** (nếu ai đó có link) nhưng **không hiện ở Khám phá**, và **không tốn token dịch metadata**.

```python
def recompute_canonical(key: str) -> None:
    rows = db.sb().table("novels")
        .select("id, source_id, chapter_count_source")
        .eq("dedup_key", key).execute().data
    if not rows: return
    prio = {s["id"]: s["meta_priority"] for s in _sources_cache()}
    winner = min(rows, key=lambda n: (prio.get(n["source_id"], 999),
                                      -(n["chapter_count_source"] or 0)))
    for n in rows:
        want = (n["id"] == winner["id"])
        db.sb().table("novels").update({"is_canonical": want}).eq("id", n["id"]).execute()
```

*Ghi chú:* chỉ dịch metadata cho bản canonical → tiết kiệm. Nếu canonical đổi (nguồn tốt hơn xuất hiện sau), bản mới sẽ được enqueue dịch metadata.

### 3.5. Luồng discovery (metadata-only)

`fetch_latest()` cho khuôn biquge = parse trang ranking (`latest_path`). Pipeline trong `sync.discover_latest`:

```
for meta in adapter.fetch_latest(limit):
    key = dedup_key(meta.title_zh, meta.author_zh)
    novel = upsert_novel({... , dedup_key: key})   # KHÔNG tải chương ở đây
    recompute_canonical(key)
    if novel mới & novel.is_canonical & chưa meta_translated:
        enqueue("metadata", novel.id, priority=10)   # dịch tên/mô tả → hiện Khám phá
```

**Quan trọng:** discovery chỉ đụng metadata. Không tải mục lục/chương ở bước này (truyện chẳng ai đọc mà tải 4000 chương là phí). Mục lục + chương vẫn **lazy** như luồng B hiện tại.

### 3.6. Luồng nội dung chương (giữ nguyên)

Không đổi: `ensure_chapters_fetched` tải `content_zh` cho chương đã `queued`; translator dịch. Chỉ cần đảm bảo adapter đúng nguồn được chọn (registry theo `source.name`).

### 3.7. Sức khoẻ nguồn + fallback

Trong vòng crawl:
- Fetch OK → `sources.last_ok_at = now`, `fail_count = 0`.
- Fetch lỗi (SSL/timeout/403) → thử lần lượt `fallback_domains`; vẫn lỗi → `fail_count++`.
- `fail_count >= N` (vd 5) → `enabled = false` + log cảnh báo (hiện ở tab Worker quản trị).

Khảo sát cho thấy nhóm site này domain hay chết/SSL lỗi → không thể "set & forget".

### 3.8. Cache bìa (pha sau)

Hiện hotlink `cover_url` thẳng từ nguồn. Rủi ro: nguồn chết/chặn hotlink → Khám phá mất bìa hàng loạt. **Pha 3:** tải bìa về Supabase Storage bucket `covers/`, lưu URL storage. Khớp ghi chú scale (đẩy dữ liệu nặng khỏi phụ thuộc nguồn ngoài).

## 4. Thay đổi code cụ thể

| File | Thay đổi |
|---|---|
| `supabase/migrations/012_multisource.sql` | **mới** — cột `sources` + `novels` ở §3.3 |
| `worker/novelworker/crawler/base.py` | `SourceAdapter.__init__(base_url, config, source_row)`; thêm helper build URL từ config |
| `worker/novelworker/crawler/biquge.py` | **mới** — tổng quát hoá `shuhaige.py` thành `BiqugeAdapter(base_url, config)`, implement `fetch_latest` (ranking) |
| `worker/novelworker/crawler/shuhaige.py` | **xoá** — shuhaige thành 1 dòng `sources` template=biquge |
| `worker/novelworker/crawler/registry.py` | **mới** — `TEMPLATE_REGISTRY` |
| `worker/novelworker/crawler/sync.py` | thêm `dedup_key()`, `recompute_canonical()`; `discover_latest` metadata-only |
| `worker/novelworker/db.py` | helper sức khoẻ nguồn (mark_ok/mark_fail), cache `sources` |
| `worker/novelworker/main.py` | `build_adapters()` động từ DB; vòng crawl round-robin theo `crawl_interval` từng nguồn |
| `app/lib/data.dart` | thêm `.eq('is_canonical', true)` vào 3 provider Khám phá |
| seed | INSERT ~8 nguồn nhóm "Có" vào `sources` (biqulao, xsbique, ddxs, uuxs, quanben5… + shuhaige) |

## 4b. Chiến lược model dịch (song song, giữ nhất quán)

**Vấn đề:** dùng nhiều model free song song cho nhanh, nhưng không được lệch văn phong/sai term trong 1 truyện.

**Nhận định:** term KHÔNG lệch dù khác model — vì tên riêng/thuật ngữ chốt trong **glossary dùng chung cả truyện** (pass phân tích chạy trước khi dịch) + `summary_vi` chương trước, đều truyền qua DB. Model chỉ khác **văn phong**.

**Giải pháp — ghim model theo truyện (không theo luồng):**
- `model = free_pool[novel_id % len(free_pool)]` với `free_pool = ["nvidia", "openrouter"]`. Mọi chương của 1 truyện đi cùng 1 model → văn phong xuyên suốt. Truyện khác nhau → model khác nhau → **song song giữa các truyện**.
- Chain mỗi truyện: `[model_ghim, model_free_kia, fireworks]` — fallback khi model chính nghẽn (đổi model giữa truyện chỉ xảy ra khi hết quota, chấp nhận được).
- **Metadata (Khám phá):** ngắn, độc lập, không cần nhất quán → dịch song song tự do (kế thừa model theo novel_id cũng được, không quan trọng).

**Hạn mức thực tế (quan trọng khi cân tải):**
- OpenRouter `:free` = **theo tài khoản** (thêm API key vô ích); 20 req/phút; 50 req/ngày (chưa nạp) hoặc **1000 req/ngày nếu từng nạp ≥ $10**. 1 chương = nhiều chunk = nhiều request → OpenRouter chỉ tải ~100-200 chương/ngày kể cả bản 1000. → **nvidia NIM là engine chính cho chương**; OpenRouter hợp cho metadata + lane phụ.
- `max_chapters_per_day`: nâng 200 → **500** (cầu chì chống bug app spam; trần cứng thật vẫn là quota từng model).
- Fireworks (trả phí) giữ làm **lưới cuối**, chỉ chạy khi cả 2 free chết.

**Config đổi:** tách `llm_free_pool` (rải theo truyện) + `llm_fallback` (fireworks). `_consume_loop` chọn model theo `job.novel_id`, không theo slot.

## 4c. Quản lý nguồn + tự kiểm tra khi thêm (probe)

**Vòng đời nguồn** — dùng `sources.status` (thay chỉ `enabled`):
`active` (đang crawl) · `paused` (admin tắt tay) · `candidate` (mới thêm, chờ probe) · `rejected` (probe trượt, giữ hồ sơ).

**Phân loại sức khoẻ** — `sources.health_status` trả lời "còn cứu được không":

| health_status | Nghĩa | Xử lý |
|---|---|---|
| `ok` | tốt | crawl bình thường |
| `degraded` | lỗi tạm (timeout/5xx/SSL) | còn khả năng — thử lại, cảnh báo nhẹ |
| `blocked` | 403/Cloudflare | fetcher thường không kham — cần headless/proxy |
| `dead` | DNS lỗi/404/domain bán/nội dung đổi | hết cứu — tự tắt |

Kèm `last_error` (text lý do) + `last_error_at`.

**Luồng probe (tự kiểm tra, đúng ý "vào tận chương xem đọc được không"):**
1. Admin dán `base_url` + **1 URL truyện mẫu** (bắt buộc — cần truyện thật để test chương) → tạo row `status='candidate'`.
2. Worker (vòng crawl) bắt candidate → **thử lần lượt các khuôn** trong `TEMPLATE_REGISTRY`: với mỗi khuôn, fetch trang truyện + fetch 1 chương → validate (tỉ lệ chữ Hán, độ dài ≥ ngưỡng).
3. Khuôn nào đọc được chương → gán `template` đó, `status='active'`. Không khuôn nào khớp → `status='rejected'` + `last_error` (vd "không khớp khuôn nào — cần viết adapter mới" / "chương 403 — bị chặn bot").
4. Nguồn `rejected` vẫn nằm trong danh sách (hồ sơ "đã thử"), có nút **"Thử lại"** → lật `status='candidate'` để probe lại (phòng site hồi sinh/đổi).

**Trang Quản trị → tab "Nguồn":**
- Danh sách nguồn: tên, domain, template, `health_status` (chấm màu), số truyện, lần OK cuối.
- Nút **Tạm dừng/Bật lại** crawl từng nguồn (`active` ↔ `paused`).
- Nút **Thêm nguồn** (form base_url + URL mẫu + template tuỳ chọn) → tạo candidate.
- Mục **Đã từ chối**: nguồn `rejected` + lý do + nút "Thử lại".
- Badge đếm nguồn `rejected`/`blocked` để admin biết cần soi.

**Thay đổi thêm:**
- Migration: `sources` thêm `status`, `health_status`, `last_error`, `last_error_at`, `probe_novel_id` (URL/id truyện mẫu). Data (jsonb) + RLS admin cho `sources` (đọc/ghi).
- `app/lib/screens/admin.dart`: thêm tab "Nguồn".
- `worker`: hàm `probe_source(candidate)` + xử lý candidate trong vòng crawl.

## 5. Phân pha triển khai

- **Pha 1 — Nền đa nguồn:** migration `sources.template/config` + `BiqugeAdapter` + registry + `build_adapters` động. Chuyển shuhaige sang dạng DB row. Nạp 2-3 nguồn biquge mới, **test crawl thật** (mục lục + 1 chương) trước khi đi tiếp.
- **Pha 2 — Khám phá tự đầy:** `fetch_latest` (ranking) + `dedup_key`/`is_canonical` + lọc `is_canonical` ở app. Bật auto-discovery.
- **Pha 3 — Model dịch song song:** tách `llm_free_pool`/`llm_fallback`, ghim model theo `novel_id`, nâng trần 500 (§4b).
- **Pha 4 — Quản lý nguồn + probe:** `sources.status`/`health_status` + `probe_source` (tự thử khuôn) + tab "Nguồn" trong Quản trị (§4c).
- **Pha 5 — Bền vững:** fallback domain, cache bìa sang Storage. Nguồn chặn bot mạnh (69shu, jjwxc) để riêng (cần Playwright/proxy — chỉ làm nếu thiếu hàng).

*(Pha 3 độc lập với 1-2-4, có thể làm xen bất cứ lúc nào vì chỉ đụng translator.)*

## 6. Rủi ro & lưu ý

1. **Selector biquge không đồng nhất 100%** — dù cùng họ, vài clone lệch nhẹ (đường dẫn, id block). `config` override từng site giải quyết; cần test thật từng nguồn khi thêm.
2. **Ranking page mỗi site khác nhau** — `latest_path` phải cấu hình đúng từng site; vài site không có trang ranking sạch → để `fetch_latest` trả `[]` và thêm tay.
3. **dedup theo title+author có thể sai** — truyện cùng tên khác tác giả, hoặc 1 nguồn thiếu tác giả. Chấp nhận sai số nhỏ; canonical sai thì đổi `meta_priority` hoặc ẩn tay.
4. **Token dịch metadata** — nhiều nguồn discovery = nhiều truyện mới = nhiều job dịch metadata. Chỉ dịch bản canonical đã giảm tải; vẫn nên có trần discovery (vd 30 truyện mới/nguồn/chu kỳ).
5. **Không làm bảng `works` lúc này** (YAGNI) — đọc vẫn từ 1 nguồn. Chỉ nâng lên `works` khi cần đọc nối chương chéo nguồn (nguồn A dừng ở chương 450, lấy tiếp từ B).
