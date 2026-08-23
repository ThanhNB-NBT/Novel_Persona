# Gác Truyện — Flutter App

Ứng dụng đọc tiểu thuyết mạng Trung → Việt (Flutter + Riverpod + go_router + Supabase).

## 1. Chuẩn bị

1. Tạo file `app/.env` (gitignored):
   ```env
   SUPABASE_URL=https://<project>.supabase.co
   SUPABASE_ANON_KEY=<anon key>
   ```
2. Cài đặt dependencies:
   ```bash
   flutter pub get
   ```

## 2. Chạy ứng dụng

### Cách 1: Gỡ lỗi qua Wi-Fi (Wireless Debugging — Không cần cắm cáp)
> Thích hợp khi không có cáp hoặc tránh bị app ngân hàng chặn do bật USB debugging. Yêu cầu Android 11+ cùng router Wi-Fi với PC.

1. **Ghép đôi thiết bị (chỉ làm 1 lần đầu):**
   - Trên điện thoại: *Cài đặt* → *Tùy chọn nhà phát triển* → *Gỡ lỗi không dây* (bật) → chọn *Ghép nối thiết bị bằng mã ghép nối*.
   - Nhìn popup lấy `IP:PORT_PAIR` và mã 6 chữ số:
     ```bash
     adb pair <IP:PORT_PAIR>     # Ví dụ: adb pair 192.168.4.239:37129
     # Nhập mã ghép nối khi được hỏi
     ```

2. **Kết nối (làm mỗi lần bật lại Wi-Fi debugging):**
   - Đóng popup, lấy `IP:PORT_CONNECT` ở màn hình Gỡ lỗi không dây chính:
     ```bash
     adb connect <IP:PORT_CONNECT>   # Ví dụ: adb connect 192.168.4.239:43933
     adb devices                     # Kiểm tra thấy thiết bị online
     ```

3. **Chạy app:**
   ```bash
   flutter run -d <IP:PORT_CONNECT> --dart-define-from-file=.env
   # Hoặc nếu chỉ có 1 thiết bị kết nối:
   flutter run --dart-define-from-file=.env
   ```

*(Chi tiết xem thêm tại [`ANDROID_WIFI_DEBUG.md`](ANDROID_WIFI_DEBUG.md)).*

---

### Cách 2: Cắm cáp USB
```bash
flutter devices                                      # Lấy ID thiết bị
flutter run -d <device_id> --dart-define-from-file=.env
```

### Cách 3: Chạy trên Android Emulator
```bash
flutter emulators --launch <tên_emulator>
flutter run -d emulator-5554 --dart-define-from-file=.env
```

## 3. Phím tắt hữu ích khi chạy `flutter run`
- **`r`**: Hot Reload (cập nhật code UI ngay lập tức không mất state).
- **`R`**: Hot Restart (khởi động lại app và reset state).
- **`h`**: Xem danh sách phím tắt trợ giúp.
- **`q`**: Thoát phiên debug.

