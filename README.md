# Novel Reader — Backend

Ứng dụng đọc tiểu thuyết mạng Trung → Việt. Repo này chứa schema Supabase + worker crawl/dịch.
Kế hoạch tổng thể: xem `docs/ke-hoach.md`.

**Dịch:** engine mặc định là **Hachimi** (model CT2 60M chạy local trên worker, không tốn token);
LLM chỉ dùng khi truyện được ghim provider hoặc khi Hachimi fallback. Script/dataset
fine-tune model Hachimi nằm ở `worker/hachimi_finetune/` (không đi kèm production).

```
supabase/migrations/   # schema + RLS + RPC (001 gốc, 002+ là migration tuần tự)
worker/                # Python worker (crawler + translator)
app/                   # Flutter app (Riverpod + go_router + Supabase)
docs/                  # kế hoạch, thiết kế multi-source, khảo sát nguồn, handoff
```

## 1. Setup Supabase

1. Tạo project tại https://supabase.com (chọn region Singapore cho gần VN).
2. `supabase link` rồi `supabase db push --linked` để chạy toàn bộ `supabase/migrations/` theo thứ tự (hoặc dán từng file vào SQL Editor).
3. **Authentication > Providers**: bật Google và Apple (P1 mới cần cho app, chưa cần ngay).
4. Lấy **Settings > API**: `Project URL` và `service_role key` cho worker.

## 2. Chạy backend worker (Docker — cách chính)

Backend là job worker kéo hàng đợi từ Supabase (không phải web API). Chạy nền
bằng Docker Compose: 2 service `crawler` + `translator`, tự khởi động lại khi lỗi.

```bash
cd worker
cp .env.example .env             # rồi điền SUPABASE_* + API key LLM vào .env
docker compose up -d --build     # bật cả 2 service chạy nền
docker compose logs -f           # xem log (Ctrl+C để thoát log, service vẫn chạy)
docker compose down              # tắt
```

`restart: unless-stopped` ⇒ máy/Docker khởi động lại là worker tự lên. Deploy
Railway/Fly.io/VPS: cùng `docker-compose.yml` này, đặt biến môi trường trên dashboard
thay cho file `.env`.

Muốn chạy trực tiếp bằng Python (dev, không Docker):

```bash
python -m venv .venv && .venv\Scripts\activate   # Linux/Mac: source .venv/bin/activate
pip install -r requirements.txt
python -m novelworker.main crawl       # terminal 1: sync mục lục + tải chương
python -m novelworker.main translate   # terminal 2: dịch
```

## 3. Vận hành & kiểm thử

**Thêm truyện:** lấy `book_id` từ URL `shuhaige.net/<book_id>/`, rồi:

```bash
python -m novelworker.main add --book-id 59979         # trong Docker: docker compose exec crawler python -m novelworker.main add --book-id 59979
python -m novelworker.main request --novel 1 --up-to 10  # giả lập app bấm "Đọc" (không cần app/auth)
python -m novelworker.main cost                          # thống kê token LLM đã dùng
python -m novelworker.main redich --novel 1 --engine hachimi  # dịch lại chương đã done bằng engine khác
```

Các lệnh khác: `audit`, `quality`, `meta` (xem `python -m novelworker.main -h`).

`request` xếp chương vào hàng đợi → crawler tải `content_zh` → translator dịch;
theo dõi cột `translation_status` (`queued → translating → done`) trong bảng
`chapters` (Supabase Table Editor).

**Resilience:** translator chết giữa chừng → sau `STALE_JOB_MINUTES` (mặc định 10)
reaper tự trả job kẹt về hàng đợi khi có worker chạy lại. Chương tải lỗi (nguồn
đổi cấu trúc) bị đánh `failed`, không retry vô hạn.

**Self-check test:** chạy từng file trong `worker/test/` (không cần mạng/LLM):
`PYTHONPATH=. python test/test_worker_helpers.py` (tương tự cho các test khác).
Test app Flutter: `cd app && flutter test`.

## 4. Nguồn truyện & chiến lược crawl

Đa nguồn, cấu hình trong bảng `sources` (DB) — adapter theo *khuôn* (template):

- `biquge` (`crawler/biquge.py`) — đang chạy nguồn **shuhaige** (www.shuhaige.net).
- `xinbiquge` (`crawler/biquge.py`) — nguồn **xsbique**.
- `dingdian` (`crawler/dingdian.py`) — nguồn **ddxs** (www.dingdian-xiaoshuo.com).
- Thêm nguồn cùng khuôn = 1 dòng INSERT vào `sources`. Khuôn mới = viết adapter kế
  thừa `SourceAdapter` (`crawler/base.py`) + đăng ký vào `crawler/registry.py`.
  Chi tiết: `docs/crawl-multisource.md`.

**Chiến lược "ít mà chất":** nguồn có bảng xếp hạng (shuhaige) chỉ discovery từ
ranking (lượt đọc = bộ lọc chất lượng); truyện đang-ra dưới `DISCOVER_MIN_CHAPTERS`
(mặc định 200) bị ẩn, đủ chương thì tự hiện lại; tối đa `DISCOVER_NEW_PER_CYCLE`
(10) truyện mới + `SAMPLE_CHAPTERS` (1) chương đọc thử mỗi nguồn mỗi chu kỳ.
Nội dung chương KHÔNG crawl sẵn hàng loạt — chỉ tải khi user đọc/yêu cầu dịch.

> ⚠️ Nội dung nguồn có bản quyền — dùng cá nhân/nội bộ; phát hành công khai có rủi ro pháp lý.

## 5. Chạy app Flutter (`app/`)

Yêu cầu: Flutter SDK (repo dev tại `C:\flutter`), file `app/.env` (gitignored) chứa:

```
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_ANON_KEY=<anon key>
```

Chỉ build cho **Android** (đã bỏ target Windows desktop).

**Android (emulator):**

```bash
cd app
flutter pub get
flutter emulators                                      # xem danh sách AVD
flutter emulators --launch Medium_Phone_API_36.1       # bật emulator, chờ boot xong
flutter run -d emulator-5554 --dart-define-from-file=.env
```

Máy thật: bật USB debugging, cắm cáp, `flutter devices` lấy device id rồi
`flutter run -d 1e2fb47 --dart-define-from-file=.env`.

**Cài bản release lên máy Android đang cắm cáp** (dùng hằng ngày, không cần PC chạy kèm):

```bash
cd app
flutter run --release --dart-define-from-file=.env
```

Lệnh trên build + cài + mở app luôn; rút cáp thoải mái, app nằm lại máy như cài từ store.
(Nhiều thiết bị thì thêm `-d <device-id>`. Chỉ muốn lấy file APK: `flutter build apk --release --dart-define-from-file=.env` → `build/app/outputs/flutter-apk/app-release.apk`.)

**Không muốn cắm USB (Gỡ lỗi qua Wi-Fi / Wireless debugging):**
Phù hợp khi không có cáp hoặc tránh bị app ngân hàng chặn do bật USB debugging (Android 11+ cùng mạng Wi-Fi):

1. **Ghép đôi (chỉ làm 1 lần đầu):**
   - Trên điện thoại: *Cài đặt* → *Tùy chọn nhà phát triển* → *Gỡ lỗi không dây* (bật) → chọn *Ghép nối thiết bị bằng mã ghép nối*.
   - Lấy `IP:PORT_PAIR` trong popup và chạy trên PC:
     ```bash
     adb pair <IP:PORT_PAIR>   # Ví dụ: adb pair 192.168.4.239:37129
     # Nhập mã 6 số hiển thị trên điện thoại
     ```
2. **Kết nối (làm mỗi lần bật lại Wi-Fi debugging):**
   - Đóng popup, lấy `IP:PORT_CONNECT` ở màn hình Gỡ lỗi không dây chính và kết nối:
     ```bash
     adb connect <IP:PORT_CONNECT>   # Ví dụ: adb connect 192.168.4.239:43933
     adb devices                     # Kiểm tra: hiện 192.168.4.239:43933 device là xong
     ```
3. **Chạy app:**
   ```bash
   cd app
   flutter run -d <IP:PORT_CONNECT> --dart-define-from-file=.env
   # Hoặc nếu adb đã connect, chỉ cần:
   flutter run --dart-define-from-file=.env
   ```
   *(Chi tiết cách xử lý lỗi mạng/firewall xem thêm tại [`app/ANDROID_WIFI_DEBUG.md`](app/ANDROID_WIFI_DEBUG.md)).*

**iPhone**: xem `app/IPHONE.md` — build IPA bằng GitHub Actions (workflow "iOS unsigned IPA",
bấm Run workflow trên tab Actions) rồi cài qua SideStore.

Đăng ký trong app đã tắt; repo không giữ tài khoản hoặc mật khẩu mẫu.
Tài khoản admin có màn **Quản trị** trong Cài đặt: thống kê kho, hàng đợi worker,
tìm/ẩn/xoá truyện, sức khỏe model LLM, báo cáo lỗi từ người đọc.

## 6. Vận hành thực tế

- Worker production chạy trên VPS (Docker Compose, `restart: unless-stopped`); cập nhật bằng `git pull` + rebuild.
- Model Hachimi CT2 đặt ở `worker/models/hachimi-ct2/` trên host (gitignored), mount read-only vào container translator.
- Backup DB: cron trên VPS `pg_dump` Supabase → giữ bản trên đĩa VPS + đẩy lên R2.
- **Phương án nếu sau này bỏ Supabase cloud:** hồ sơ tham khảo cho Supabase self-host nằm
  trong `infra/`. Đây mới là bản chuẩn bị, chưa dựng hoặc kiểm chứng; nếu chuyển sang database
  khác giao thức thì app/worker còn cần một lớp API tương thích. Chi tiết: `infra/FAILOVER.md`.
