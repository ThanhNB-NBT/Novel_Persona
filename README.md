# Novel Reader — Backend P0

Ứng dụng đọc tiểu thuyết mạng Trung → Việt. Repo này chứa schema Supabase + worker crawl/dịch.
Kế hoạch tổng thể: xem `ke-hoach-app-doc-truyen.md` (tài liệu đã tạo trước đó).

```
supabase/migrations/001_schema.sql   # toàn bộ schema + RLS + RPC
worker/                              # Python worker (crawler + translator)
```

## 1. Setup Supabase

1. Tạo project tại https://supabase.com (chọn region Singapore cho gần VN).
2. Mở **SQL Editor** → dán toàn bộ `supabase/migrations/001_schema.sql` → Run.
3. **Authentication > Providers**: bật Google và Apple (P1 mới cần cho app, chưa cần ngay).
4. Lấy **Settings > API**: `Project URL` và `service_role key` cho worker.

## 2. Chạy worker

```bash
cd worker
python -m venv .venv
.venv\Scripts\activate          # Windows (Linux/Mac: source .venv/bin/activate)
pip install -r requirements.txt
copy .env.example .env           # rồi điền key thật vào .env
```

Chạy 2 tiến trình ở 2 terminal:

```bash
python -m novelworker.main crawl       # discovery truyện mới + tải chương
python -m novelworker.main translate   # dịch metadata / chương / bình luận
```

## 3. Luồng hoạt động

1. Crawler quét Fanqie mỗi `CRAWL_INTERVAL_MIN` phút → upsert `novels` → tạo job dịch **metadata** (priority cao) → truyện hiện lên app với tên/giới thiệu tiếng Việt.
2. User (hoặc bạn, test bằng SQL) gọi RPC `request_translation(novel_id, 10)` → 10 chương đầu vào queue.
3. Crawler thấy chương `queued` chưa có `content_zh` → tải nguyên văn từ nguồn.
4. Translator dịch từng chương (kèm glossary của truyện), ghi `content_vi`, `status='done'` → app nhận qua Realtime.
5. App gọi lại `request_translation(novel_id, 20)` khi user đọc gần hết (còn ≤3 chương) — cứ thế nới dần.

Test nhanh không cần app:

```sql
-- giả lập user bấm "Đọc" (chạy trong SQL Editor với 1 user đã đăng nhập, hoặc tạm sửa hàm bỏ check auth khi dev)
select request_translation(1, 10);
```

## 4. Điểm cần kiểm chứng khi chạy thật (đã đánh dấu TODO trong code)

- **Endpoint Fanqie** (`worker/novelworker/crawler/fanqie.py`): Fanqie đổi API/chống bot thường xuyên; nếu 403 thì điền `FANQIE_COOKIE`, nặng hơn thì thêm proxy (`HTTP_PROXY_URL`).
- **Mã hóa font Fanqie**: một số chương trả về ký tự bị tráo (private-use unicode). Code đã có hook `decode_obfuscated()` + cảnh báo log; khi gặp cần bổ sung bảng map.
- **Bình luận Fanqie**: nằm ở API app, chưa triển khai (P2) — hiện trả rỗng.

## 5. Tiếp theo (P1)

- Project Flutter: auth Google/Apple, tab Khám phá (đọc `novels` where `meta_translated`), chi tiết truyện, trình đọc + Realtime, tủ sách.
- Deploy worker lên Railway/Fly.io (2 process: crawl + translate).

> ⚠️ Nội dung nguồn có bản quyền — dùng cá nhân/nội bộ; phát hành công khai có rủi ro pháp lý.
