# Cài app lên iPhone (không cần Mac, không tốn $99)

## Bức tranh tổng thể

Apple không cho cài app ngoài App Store một cách tự do, nên phải đi vòng:

```
┌─ GitHub Actions (macOS runner) ─┐      ┌─ PC Windows ─┐      ┌─ iPhone ─┐
│ build Flutter → novel_reader.ipa │ ───► │ tải .ipa về  │ ───► │ SideStore │
│ (file .ipa CHƯA ký)              │      │              │      │ ký + cài  │
└──────────────────────────────────┘      └──────────────┘      └───────────┘
```

- **Build cần macOS** → thuê chùa máy Mac của GitHub Actions (workflow đã có sẵn).
- **Cài cần chữ ký Apple** → SideStore ký bằng Apple ID miễn phí ngay trên iPhone.
- Chữ ký free chỉ sống **7 ngày** → SideStore tự gia hạn (không cần bật PC).

Vai trò từng công cụ:

| Công cụ | Ở đâu | Làm gì | Cài mấy lần |
|---|---|---|---|
| Workflow `ios-unsigned.yml` | GitHub | Build ra file `.ipa` | chạy lại mỗi khi update app |
| [iloader](https://github.com/nab138/iloader) | PC Windows | Cài SideStore lên iPhone qua cáp | **1 lần duy nhất** |
| [SideStore](https://sidestore.io) | iPhone | Ký + cài `.ipa`, tự gia hạn 7 ngày | 1 lần (do iloader cài) |
| StosVPN | iPhone (App Store) | VPN loopback để SideStore tự ký không cần PC | 1 lần |

---

## Phần A — Chuẩn bị (1 lần)

1. **iPhone**: iOS 16+ bình thường, không cần jailbreak.
2. **Apple ID**: dùng ID chính được; cẩn thận hơn thì tạo 1 Apple ID phụ chỉ để ký app
   (SideStore chỉ dùng ID để xin chứng chỉ dev free từ Apple).
3. **PC Windows**: cài **iTunes** (bản từ apple.com, không phải Microsoft Store —
   iloader cần driver usbmuxd của iTunes).
4. **GitHub**: vào repo → Settings → Secrets and variables → Actions, thêm 2 secret:
   - `SUPABASE_URL` — lấy trong `app/.env`
   - `SUPABASE_ANON_KEY` — lấy trong `app/.env`

## Phần B — Cài SideStore lên iPhone (1 lần)

> Bước này làm đúng theo hướng dẫn của iloader/SideStore — UI của chúng đổi theo
> version, dưới đây là khung; chỗ nào lệch thì tin theo app + docs chính chủ:
> https://docs.sidestore.io

1. Tải **iloader** bản Windows: https://github.com/nab138/iloader/releases
2. Cắm iPhone vào PC bằng cáp, mở iloader, bấm **Trust** trên iPhone khi được hỏi.
3. Trong iloader chọn **Install SideStore**, đăng nhập Apple ID khi được hỏi.
   (iloader tự lo pairing file — thứ SideStore cần để tự ký về sau.)
4. Trên iPhone: Cài đặt → Cài đặt chung → **VPN & Quản lý thiết bị** → tin cậy
   chứng chỉ Apple ID của bạn.
5. Bật **Developer Mode**: Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển
   → bật, iPhone khởi động lại.
6. Cài **StosVPN** từ App Store (miễn phí), mở 1 lần cho nó xin quyền VPN.
7. Mở SideStore, đăng nhập Apple ID → xong phần nền móng, **từ giờ không cần PC nữa**.

## Phần C — Build + cài app (lặp lại mỗi lần update app)

1. **Build**: GitHub → tab **Actions** → workflow **"iOS unsigned IPA (sideload)"**
   → **Run workflow** → đợi ~15 phút.
2. **Tải**: mở run vừa xong → mục Artifacts → tải `novel_reader-ipa` → giải nén
   được `novel_reader.ipa`.
3. **Chuyển sang iPhone**: qua iCloud Drive / Google Drive / Zalo gửi file — miễn là
   file `.ipa` mở được trong app **Tệp (Files)** trên iPhone.
4. **Cài**: bật StosVPN → mở SideStore → tab My Apps → nút **+** → chọn
   `novel_reader.ipa` → đợi ký + cài. Bản mới đè lên bản cũ, dữ liệu đăng nhập giữ nguyên.

Lưu ý: chỉ thay đổi **code Flutter** mới cần làm phần C. Sửa worker/prompt dịch/DB
không đụng gì tới app trên iPhone.

## Phần D — Gia hạn 7 ngày (tự động)

Chữ ký free hết hạn sau 7 ngày → app không mở được cho tới khi refresh. SideStore
refresh được ngay trên iPhone (cần StosVPN đang bật). Tự động hoá:

1. Mở app **Phím tắt (Shortcuts)** → tab **Tự động hoá** → **+**.
2. Chọn sự kiện **Bộ sạc** → "Được kết nối" → Chạy ngay lập tức.
3. Hành động: **Mở ứng dụng** → SideStore. (SideStore mở nền sẽ tự refresh app sắp hết hạn.)

Từ đó mỗi lần cắm sạc là chữ ký được gia hạn ngầm — quên hẳn chuyện 7 ngày.

## Sự cố thường gặp

| Triệu chứng | Nguyên nhân / cách xử |
|---|---|
| App không mở, hiện popup "không thể xác minh" | Chữ ký hết hạn — bật StosVPN, mở SideStore → Refresh All |
| SideStore báo lỗi khi ký | StosVPN chưa bật, hoặc pairing file hỏng → cắm PC chạy lại iloader để nhập pairing file mới |
| Build GitHub fail | Xem log bước đỏ trong Actions; hay gặp nhất là thiếu/sai 2 secret Supabase |
| Cài báo "maximum App IDs" | Apple ID free bị giới hạn 10 App ID/7 ngày — đợi vài ngày; cài đè app cũ (cùng bundle id) thì KHÔNG tốn thêm |
| Apple revoke chứng chỉ | Hiếm với ID free; mở SideStore refresh lại là xong |

## Chi phí GitHub Actions

- Repo **public**: build không giới hạn.
- Repo **private**: 2.000 phút free/tháng nhưng macOS tính **x10** → ~200 phút thật
  ≈ 1-2 lần build/tháng. Update app thường xuyên thì nên public repo
  (an toàn: key Supabase nằm trong Secrets + `.env` không commit, RLS bảo vệ dữ liệu).
