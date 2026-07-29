# Luồng lưu trữ dự phòng — Supabase self-host (warm standby)

Mục tiêu: khi ngừng dùng Supabase cloud, VPS chạy được **Supabase self-host** (cùng
stack: Postgres + Auth + PostgREST + Realtime + Storage) nên worker và app **không phải
viết lại code** — chỉ đổi đích kết nối.

Kiểu chuyển: **warm** — stack dựng sẵn, đứng im; lúc cần thì restore bản dump mới nhất,
lật đích worker + app, xong trong vài phút. KHÔNG replication trực tiếp.

Vì sao phải là self-host chứ không phải Postgres trần: app dựa vào cả 4 mặt của Supabase
— PostgREST (`.table()`), Auth+RLS (`signInWithPassword`), Realtime (chương live-update,
thông báo), Storage (bìa). Postgres trần thiếu cả 4 → phải viết lại app + worker.

---

## 0. Chuẩn bị 1 lần (dựng stack, để im)

Cần: 1 VPS **≥ 4GB RAM** (stack đã trim ~2–3GB; chung máy với worker 2GB thì chật, nên
tách con riêng cho DB). Docker + docker compose.

```bash
# clone stack chính chủ, GHIM ref để override khớp (bump ref thì soi lại override)
git clone --depth 1 --branch <PINNED_REF> https://github.com/supabase/supabase.git
cd supabase/docker
cp /path/to/infra/selfhost/.env.example .env          # rồi điền key (xem .env.example)
cp /path/to/infra/selfhost/docker-compose.override.yml .   # trim service ngốn RAM
docker compose up -d
docker compose ps                                     # tất cả healthy?
```

> **CHƯA TEST trên máy thật.** `docker-compose.override.yml` chỉ profile-disable được
> `studio` + `functions` (2 service không ai phụ thuộc). Muốn bỏ tiếp `analytics` +
> `vector` + `imgproxy` (phần ngốn RAM thật) phải **sửa tay `docker-compose.yml` gốc** —
> Compose merge KHÔNG xoá được `depends_on` nên override làm không nổi. Các dòng cần xoá
> ghi ở cuối file override. Trên box thật: `docker compose config` rồi `docker compose ps`,
> mọi service phải `healthy` và KHÔNG thấy analytics/vector chạy.

Sinh key (điền vào `.env`):
- `JWT_SECRET`: chuỗi ngẫu nhiên ≥ 32 ký tự.
- `ANON_KEY`, `SERVICE_ROLE_KEY`: JWT ký bằng `JWT_SECRET` ở trên. Sinh tại
  https://supabase.com/docs/guides/self-hosting/docker#generate-api-keys hoặc script jwt.
- `POSTGRES_PASSWORD`, `DASHBOARD_PASSWORD`: đặt mật khẩu riêng.

**Key self-host KHÁC key cloud** — app + worker phải nhận key mới lúc chuyển (mục 3, 4).

---

## 1. Nạp dữ liệu (restore từ dump có sẵn)

Cron đêm (`/root/backup/backup.sh` trên VPS worker) đã dump `public` + `auth` mỗi ngày →
`/root/backup/novel-YYYY-MM-DD.sql.gz` + R2 bucket `novel-backup`. Dùng chính bản đó:

```bash
# lấy dump mới nhất (từ đĩa VPS worker hoặc R2), rồi nạp vào Postgres self-host
LATEST=$(ls -t /root/backup/novel-*.sql.gz | head -1)
zcat "$LATEST" | docker exec -i supabase-db psql -U postgres -d postgres
```

> Muốn mất DATA ÍT NHẤT lúc chuyển: chạy `backup.sh` **ngay trước khi chuyển** để có
> dump nóng, rồi restore bản đó (thay vì bản đêm qua).

Dump gồm `auth.users` (email + hash mật khẩu bcrypt) nên user đăng nhập lại được bằng
đúng mật khẩu cũ. RLS/policy theo trong schema `public`.

---

## 2. Mirror ảnh bìa (bucket covers)

Dump SQL **không** chứa file bìa (nằm ở object storage). Copy 1 lần cloud → self-host qua
S3 (cả hai đầu đều nói S3). Đã có rclone trên VPS.

```bash
# remote nguồn: Supabase cloud Storage S3 (Project Settings → Storage → S3 connection)
# remote đích:  Storage self-host (S3 endpoint http://<vps>:8000/storage/v1/s3)
rclone copy cloud-storage:covers selfhost-storage:covers --progress
```

Cấu hình 2 remote `s3` trong `~/.config/rclone/rclone.conf` (access key/secret + endpoint
mỗi đầu). Chạy lại lệnh này định kỳ nếu muốn bìa mới cũng có sẵn trước khi chuyển.

---

## 3. Chuyển WORKER sang self-host

Worker đọc đích từ `worker/.env` (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`). Đổi 2 dòng
rồi restart:

```bash
cd /root/Novel_Project/worker
sed -i 's#^SUPABASE_URL=.*#SUPABASE_URL=http://<vps-selfhost>:8000#' .env
sed -i 's#^SUPABASE_SERVICE_ROLE_KEY=.*#SUPABASE_SERVICE_ROLE_KEY=<service_role_key_selfhost>#' .env
docker compose up -d --force-recreate
docker compose logs -f --tail=50        # thấy claim job + heartbeat là OK
```

Quay lại cloud = đổi ngược 2 dòng, restart. (Giữ 1 bản `.env.cloud` và `.env.selfhost`
để copy cho nhanh.)

---

## 4. Chuyển APP sang self-host (không cần build lại)

App đọc `{url, anonKey}` từ file JSON tĩnh lúc mở (biến build `ENDPOINT_CONFIG_URL`).
Lật kho = sửa file JSON đó rồi mở lại app.

File JSON (đặt trên R2 public hoặc GitHub raw — **độc lập với Supabase**):

```json
{ "url": "http://<vps-selfhost>:8000", "anonKey": "<anon_key_selfhost>" }
```

- Chuyển: đổi nội dung JSON sang url/anonKey self-host → upload đè.
- App lần mở kế tiếp tải JSON, cache lại, `Supabase.initialize` trỏ đích mới.
- Chưa set `ENDPOINT_CONFIG_URL` lúc build → app dùng đích nướng sẵn (hành vi cũ). Muốn
  bật cơ chế runtime, build với `--dart-define ENDPOINT_CONFIG_URL=https://.../endpoint.json`.

> **Đăng nhập lại 1 lần:** token phiên cũ ký bằng JWT secret của cloud → self-host coi là
> chữ ký sai → app tự đăng xuất, user đăng nhập lại (email/mật khẩu cũ vẫn đúng nhờ mục 1).
> Chấp nhận được với warm failover.

---

## 5. Kiểm sau khi chuyển

- [ ] `docker compose ps` self-host: mọi service `healthy`.
- [ ] Worker log: claim được job, dịch xong 1 chương, `finalize_chapter_job` không lỗi.
- [ ] App: đăng nhập lại OK, mở 1 truyện, đọc 1 chương, tủ sách hiện đúng.
- [ ] Realtime: đang mở chương → worker dịch xong → chương tự cập nhật.
- [ ] Bìa hiện (mục 2 đã mirror).
- [ ] Bật lại cron backup trỏ vào Postgres self-host (đổi connection string trong
      `backup.sh`) để bản dự phòng vẫn có backup off-site.

---

## Bỏ qua (thêm khi cần)

- **Replication trực tiếp (hot):** đã chọn warm. Thêm logical replication nếu sau này
  cần mất-0-data lúc chuyển.
- **Adapter đa-DB trong worker:** không cần — hợp đồng API Supabase đã là lớp trừu tượng,
  đổi đích chỉ là đổi URL/key. Chỉ cần nếu rời hẳn Supabase sang DB khác protocol.
