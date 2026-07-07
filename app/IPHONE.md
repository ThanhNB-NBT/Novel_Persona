# Cài & duy trì app trên iPhone (không cần Mac, không tốn $99)

> Viết lại 2026-07-07 sau khi cài thành công thật. Ghi cả các lỗi đã gặp + cách xử.

## Bức tranh tổng thể

```
GitHub Actions (máy Mac ảo)  →  PC Windows        →  iPhone
build ra novel_reader.ipa       tải .ipa về,          SideStore ký + cài,
(file CHƯA ký)                  cài SideStore 1 lần    LocalDevVPN giữ chữ ký
```

- Build iOS bắt buộc máy Mac → thuê chùa GitHub Actions.
- Cài app cần chữ ký Apple → SideStore ký bằng Apple ID free, ngay trên iPhone.
- Chữ ký free sống **7 ngày** → refresh trong SideStore (mục "Cách refresh" cuối file).

Công cụ và vai trò:

| Công cụ | Ở đâu | Cài mấy lần |
|---|---|---|
| Workflow `ios-unsigned.yml` | GitHub Actions | chạy lại mỗi lần đổi code Flutter |
| iTunes | PC Windows | 1 lần (chỉ cần driver USB của nó) |
| iloader | PC Windows | 1 lần (để cài SideStore) |
| SideStore | iPhone | 1 lần (iloader cài) |
| LocalDevVPN | iPhone (App Store) | 1 lần |

---

## PHẦN 1 — Chuẩn bị PC (1 lần)

### 1a. Cài iTunes (chỉ cần driver USB của nó)
- Tải iTunes bản 64-bit từ apple.com (KHÔNG dùng bản Microsoft Store).
- Cài xong, nếu hiện cảnh báo "problem with your audio configuration" → **bấm OK, kệ nó** (iTunes than về âm thanh, không liên quan iPhone).

### 1b. ⚠️ Lỗi hay gặp: iPhone chỉ hiện "cho phép đọc ảnh/video", KHÔNG có hộp "Tin cậy"
Nguyên nhân: iTunes cài thiếu **Apple Mobile Device USB Driver** → iPhone chỉ được
nhận làm "thiết bị ảnh" (WPD), không có tầng data để pairing. iTunes/iloader đều
không thấy máy.

Cách kiểm tra (PowerShell):
```powershell
Get-PnpDevice -FriendlyName "*Apple*","*iPhone*" | Select FriendlyName, Class, Status
```
- Chỉ thấy `Apple iPhone | WPD` → THIẾU driver (lỗi).
- Thấy `Apple Mobile Device USB Driver | USB | OK` → ĐÃ đúng.

Cách sửa (bung driver từ bộ cài iTunes rồi nạp tay):
```bash
# 1. Bung iTunes64Setup.exe (cần 7-Zip)
"C:\Program Files\7-Zip\7z.exe" x iTunes64Setup.exe -o itunes_x
# 2. Bung tiếp MSI chứa driver
"C:\Program Files\7-Zip\7z.exe" x itunes_x\AppleMobileDeviceSupport64.msi -o amds
# → được amds\usbaapl64.inf + .sys + .cat
```
```powershell
# 3. Nạp driver (cần quyền admin — sẽ hiện UAC, bấm Yes)
pnputil /add-driver "amds\usbaapl64.inf" /install
# 4. Quét lại thiết bị
pnputil /scan-devices
```
Sau đó **rút–cắm lại cáp**, mở khoá iPhone → hộp **"Tin cậy máy tính này?"** hiện ra
→ Tin cậy + nhập mã.

## PHẦN 2 — Build file IPA (mỗi lần đổi code Flutter)

1. GitHub repo → Settings → Secrets and variables → Actions → thêm 2 secret
   (lấy từ `app/.env`): `SUPABASE_URL`, `SUPABASE_ANON_KEY`. (Chỉ làm 1 lần đầu.)
2. Tab **Actions** → workflow **"iOS unsigned IPA (sideload)"** → **Run workflow**
   → đợi ~4–15 phút tới khi Status = **Success**.
3. Mở run vừa xong → mục **Artifacts** → tải **novel_reader-ipa** (là file .zip).
4. **Giải nén** .zip → được `novel_reader.ipa` (SideStore chỉ nhận .ipa, không nhận .zip).

## PHẦN 3 — Cài SideStore lên iPhone (1 lần)

1. Tải **iloader** (Windows) từ github.com/nab138/iloader/releases.
2. Cắm iPhone, mở iloader → nếu "No devices found" thì mở khoá iPhone, bấm
   **Refresh**. (Vẫn không thấy → xem lại PHẦN 1b.)
3. Nhập **Apple ID + mật khẩu** ở khung bên trái → **Login** (2FA thì nhập mã 6 số).
4. Mục INSTALLERS → bấm **SideStore (Stable)**. KHÔNG cần LiveContainer (app chỉ có 1).
5. Đợi ~1–2 phút → icon **SideStore** hiện trên iPhone.

## PHẦN 4 — Chuẩn bị iPhone (1 lần)

1. **Tin cậy chứng chỉ**: Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị →
   mục DEVELOPER APP (Apple ID của bạn) → **Tin cậy**.
2. **Bật Developer Mode**: Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển
   → bật → iPhone khởi động lại → bật lại lần nữa + nhập mã.
3. **Cài LocalDevVPN** từ App Store (nhà phát triển **Coxson Engineering LLC**).
   ⚠️ KHÔNG phải "StosVPN" (cái này không có trên App Store VN) và KHÔNG phải mấy app
   "Super VPN / Fast VPN Proxy". Mở LocalDevVPN → cho phép quyền VPN → bấm **Connect**.

## PHẦN 5 — Cài file .ipa bằng SideStore (mỗi lần có bản mới)

### 5a. Đưa file .ipa vào iPhone
KHÔNG copy được qua cáp (Explorer chỉ thấy ảnh/video — giới hạn cứng của iOS).
Dùng đám mây:
- PC: upload `novel_reader.ipa` lên **Google Drive**.
- iPhone: mở Google Drive → file đó → ⋯ → **Mở trong…** → **Lưu vào Tệp** (Files).
- (Thay thế: gửi qua **Telegram** cho chính mình cũng được; Zalo đôi khi chặn .ipa.)

### 5b. Cài
1. Bật **LocalDevVPN** (Connect).
2. SideStore → đăng nhập **Apple ID** (cùng ID với iloader) nếu chưa.
   ⚠️ Login quay mãi không vào? → SideStore Settings → **Anisette Server** → đổi sang
   server khác → thử lại. Đây là lỗi server Anisette quá tải, KHÔNG phải do VPN.
   ĐỪNG bấm Login liên tục (spam dễ bị Apple tạm khoá Apple ID vài giờ) — bấm 1 lần,
   đợi ~30s, thất bại thì đổi server rồi mới bấm lại.
3. Tab **My Apps** → nút **+** → chọn file `novel_reader.ipa` trong Tệp → ký + cài.
4. Xong → icon **Gác Truyện** trên màn hình chính. Bản mới đè bản cũ, giữ nguyên đăng nhập.

## PHẦN 6 — ⭐ Cách refresh sau 7 ngày (QUAN TRỌNG)

Chữ ký Apple ID free hết hạn sau **7 ngày** → app không mở được cho tới khi refresh.
SideStore refresh ngay trên iPhone, KHÔNG cần PC.

### Refresh tay (khi cần)
1. Bật **LocalDevVPN** (Connect).
2. Mở **SideStore** → tab **My Apps** → nút **Refresh All** (hoặc kéo xuống để refresh).
3. Đợi vài giây → chữ ký gia hạn thêm 7 ngày.

### Refresh tự động (làm 1 lần, khỏi lo quên) — khuyến nghị
1. iPhone → app **Phím tắt (Shortcuts)** → tab **Tự động hoá** → **+**.
2. Sự kiện: **Bộ sạc** → "Được kết nối" → **Chạy ngay** (tắt "Hỏi trước khi chạy").
3. Hành động: **Mở ứng dụng** → chọn **SideStore**.
→ Từ đó mỗi lần cắm sạc, SideStore mở nền và tự refresh. Nhớ để **LocalDevVPN luôn
   Connect** thì refresh nền mới chạy được.

> Mẹo: cắm sạc hằng đêm = app không bao giờ hết hạn. Lỡ để quá 7 ngày, app không mở
> được cũng KHÔNG mất dữ liệu — chỉ cần bật VPN + Refresh All là sống lại.

## Sự cố nhanh

| Triệu chứng | Xử lý |
|---|---|
| App không mở, popup "không thể xác minh" | Chữ ký hết hạn → bật LocalDevVPN → SideStore → Refresh All |
| SideStore login quay mãi | Đổi Anisette Server trong Settings; đừng spam Login |
| SideStore/iloader không thấy iPhone | PHẦN 1b — thiếu Apple Mobile Device USB Driver |
| Cài .ipa lỗi giữa chừng | LocalDevVPN chưa Connect, hoặc pairing hỏng → cắm PC chạy lại iloader |
| "Maximum App IDs" | Apple ID free giới hạn 10 App ID/7 ngày → đợi; cài đè app cũ KHÔNG tốn thêm |

## Chi phí build (GitHub Actions)

- Repo **public** (Novel_Persona đang public): build **không giới hạn**.
- Repo private: macOS runner tính x10 → ~200 phút thật/tháng (~1–2 lần build).
