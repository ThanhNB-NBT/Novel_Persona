# Novel Persona — ứng dụng đọc

Ứng dụng đọc tiểu thuyết mạng Trung → Việt. Repo này chứa **mã nguồn ứng dụng Flutter** và
quy trình phát hành. Phần backend (worker crawl/dịch, schema Supabase, hạ tầng) nằm ở kho
riêng.

## 📱 Tải app

**<https://novel-persona.novelnbt.workers.dev>** — trang tải, tự lấy bản phát hành mới nhất
qua GitHub API nên không phải sửa tay mỗi lần tag.

Cài trực tiếp APK từ [Releases](https://github.com/ThanhNB-NBT/Novel_Persona/releases) cũng
được; iOS thì xem [`app/IPHONE.md`](app/IPHONE.md).

Ứng dụng tự kiểm bản mới qua GitHub Releases của chính kho này (`app/lib/update.dart`), nên
**đường dẫn kho không được đổi** — đổi là mọi bản đã cài mất kênh cập nhật.

## Chạy thử

```bash
cd app
flutter pub get
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Bốn giá trị `--dart-define` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ENDPOINT_CONFIG_URL`,
`ENDPOINT_ALLOWED_HOSTS`) lúc phát hành được lấy từ GitHub Secrets — xem
`.github/workflows/android-release.yml`.

## Phát hành

Đẩy tag `v*` lên `main`:

```bash
git tag v1.0.10 && git push origin v1.0.10
```

Workflow chạy `flutter analyze` trước, rồi build APK (ký sẵn bằng keystore trong Secrets) và
IPA, cuối cùng tạo GitHub Release kèm file. Keystore **không** nằm trong kho — mất là không
cập nhật được app đã cài, nhớ giữ bản sao.

## Cấu trúc

```
app/lib/screens/    # màn hình theo tab
app/lib/widgets.dart # widget dùng chung
app/lib/theme.dart   # bảng màu Thanh Tân / Dạ Lam — đừng hardcode màu
app/lib/update.dart  # kiểm bản mới qua GitHub Releases
```

Model dữ liệu dùng `Map` (`Rec`), **không** thêm codegen/freezed.
