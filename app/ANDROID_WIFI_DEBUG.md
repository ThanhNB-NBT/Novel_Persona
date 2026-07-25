# Chạy `flutter run` qua Wi-Fi (không cắm USB)

> Lý do: bật **USB debugging** làm app ngân hàng / app nhà nước từ chối chạy.
> Android 11+ có **Wireless debugging** là cờ riêng (`adb_wifi_enabled`), phần lớn
> app chỉ dò cờ USB (`adb_enabled`) nên thường lọt.

Yêu cầu: điện thoại Android 11 trở lên, PC và điện thoại **cùng một router Wi-Fi**
(không cần điện thoại phát hotspot).

---

## PHẦN 0 — Chuẩn bị PC (1 lần)

`adb` chưa có trong PATH. Nó nằm ở:

```
C:\Users\ThanhNB\AppData\Local\Android\Sdk\platform-tools\adb.exe
```

Thêm vĩnh viễn vào PATH (PowerShell, chạy 1 lần, mở lại terminal sau đó):

```bash
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Users\ThanhNB\AppData\Local\Android\Sdk\platform-tools", "User")
```

Kiểm tra:

```bash
adb version
```

---

## PHẦN 1 — Ghép đôi (pair) — chỉ làm 1 LẦN cho mỗi máy

### 1a. Bật Wireless debugging trên điện thoại
Settings → **Developer options** → **Wireless debugging** → bật.

(Chưa có Developer options: Settings → About phone → bấm **Build number** 7 lần.)

### 1b. Lấy mã ghép đôi
Trong màn hình Wireless debugging → **Pair device with pairing code**.

Popup hiện 2 thứ, **giữ popup này mở**:
- `IP address & Port` — ví dụ `192.168.1.15:37129` ← đây là **PORT PAIR**
- `Wi-Fi pairing code` — 6 chữ số

### 1c. Ghép trên PC

```bash
adb pair 192.168.1.15:37129
```

Nó hỏi `Enter pairing code:` → gõ 6 số → Enter.
Thành công: `Successfully paired to ...`

> ⚠️ Port trong popup pair **khác** port ở màn hình chính. Dùng nhầm là fail.

---

## PHẦN 2 — Kết nối (làm MỖI LẦN bật lại Wireless debugging)

Đóng popup pair. Ở màn hình **Wireless debugging** chính có dòng
`IP address & Port`, ví dụ `192.168.1.15:41235` ← đây là **PORT CONNECT**.

```bash
adb connect 192.168.1.15:41235
```

```bash
adb devices
```

Thấy `192.168.1.15:41235   device` là xong.

---

## PHẦN 3 — Chạy app

```bash
cd E:\Novel_Project\app; if ($?) { flutter devices }
```

```bash
flutter run
```

Hot reload (`r`), hot restart (`R`) chạy bình thường qua Wi-Fi, chỉ chậm hơn USB
lúc cài APK lần đầu.

---

## Lỗi hay gặp

| Triệu chứng | Nguyên nhân | Cách xử |
|---|---|---|
| `adb pair` treo rồi `failed to connect` | Dùng nhầm port connect thay vì port pair | Mở lại popup "Pair device with pairing code", lấy port trong popup |
| `adb connect` → `connection refused` / timeout | Router bật **AP isolation** (hay gặp ở modem nhà mạng, mạng Guest) | Đổi sang Wi-Fi chính, hoặc tắt AP isolation trong trang admin router |
| Ping không thông | PC đang bật **VPN** chặn traffic LAN | Tắt VPN |
| PC cắm dây LAN, điện thoại Wi-Fi, không thấy nhau | Khác dải IP (192.168.1.x vs 192.168.0.x) | Cho PC đi Wi-Fi cùng router |
| Đang chạy thì rớt kết nối | Điện thoại ngủ / đổi IP (DHCP) | `adb connect` lại; đặt IP tĩnh cho điện thoại trong router nếu rớt nhiều |
| `flutter devices` không thấy máy dù `adb devices` thấy | Flutter cache thiết bị cũ | `adb kill-server` rồi `adb connect` lại |
| App ngân hàng vẫn chặn | App dò cả "Developer options đang bật", không chỉ cờ adb | Không né được — tắt Developer options khi cần dùng bank |

Test nhanh xem mạng có thông không trước khi pair:

```bash
ping 192.168.1.15
```

---

## Tóm tắt cho lần sau

1. Điện thoại: bật Wireless debugging.
2. PC: `adb connect <IP>:<port ở màn hình chính>`
3. `flutter run`

Chỉ phải `adb pair` lại khi đổi PC, quên thiết bị, hoặc reset điện thoại.

---

## Android < 11 (không có Wireless debugging)

Bắt buộc cắm USB **một lần** để bật chế độ TCP:

```bash
adb tcpip 5555
```

Rút dây, rồi:

```bash
adb connect 192.168.1.15:5555
```

Cách này yêu cầu USB debugging bật sẵn → không giải quyết được vấn đề app ngân hàng.
