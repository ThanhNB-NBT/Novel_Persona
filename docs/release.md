# Phát hành bản mới (Android APK + iOS IPA)

Đẩy 1 tag `v*` lên GitHub → Actions tự build **APK ký sẵn** + **IPA (chưa ký)** rồi
gom vào **cùng 1 GitHub Release**. App Android có nút *Kiểm tra cập nhật* (Cài đặt)
đọc release mới nhất qua API; iPhone tải `.ipa` từ trang release cài qua SideStore.

Workflow: [`.github/workflows/android-release.yml`](../.github/workflows/android-release.yml)

## Các bước

1. **Tăng version** trong [`app/pubspec.yaml`](../app/pubspec.yaml):

   ```yaml
   version: 1.0.5+6
   #        ▲     ▲
   #        │     └── build number — PHẢI tăng, không Android không nhận là bản mới
   #        └──────── version name (khớp phần sau chữ v của tag)
   ```

2. **Commit + tag + push** (tag phải khớp version name):

   ```bash
   git add app/pubspec.yaml
   git commit -m "Bump v1.0.5"
   git tag v1.0.5
   git push origin main v1.0.5
   ```

3. Vào tab **Actions** trên GitHub xem build. Xong (~10–15 phút) sẽ có Release mới ở
   mục **Releases** kèm `GacTruyen-v1.0.5.apk` + `GacTruyen-v1.0.5.ipa`, release notes
   tự sinh từ commit.

Chạy workflow bằng nút **Run workflow** (workflow_dispatch) = **chỉ test build**, KHÔNG
tạo release (không có tag).

## Lưu ý

- **Release là immutable** — đã publish thì không đính thêm file được. Workflow cố tình
  build đủ APK + IPA rồi mới tạo release một phát. Nếu 1 job (apk/ipa) fail thì không
  ra release; sửa lỗi rồi **xoá tag cũ, tag lại**:

  ```bash
  git tag -d v1.0.5 && git push origin :refs/tags/v1.0.5   # xoá local + remote
  git tag v1.0.5 && git push origin v1.0.5                 # tag lại
  ```

- **Quên tăng build number** (`+6`) → APK vẫn build nhưng app cũ không thấy bản mới khi
  bấm *Kiểm tra cập nhật* (Android so versionCode). Version name trùng cũng gây khó lần
  khi debug.

- **Tag phải nằm trên commit đã có version bump.** Tag rồi mới sửa pubspec là APK mang
  version cũ. Thứ tự đúng: commit bump → tag → push.

## Secrets cần có (Settings → Secrets → Actions)

| Secret | Dùng để |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore ký APK (base64 của `upload-keystore.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | mật khẩu store + key (alias `upload`) |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | nhúng vào app lúc build |

> ⚠️ **BACKUP keystore.** `upload-keystore.jks` bị gitignore. Mất keystore = **không
> update được app đã cài** (Android chặn cài đè APK khác chữ ký) — người dùng phải gỡ
> cài lại. Giữ file + mật khẩu ở nơi an toàn ngoài repo.

## iPhone

Cài `.ipa` (chưa ký) qua SideStore — xem [`app/IPHONE.md`](../app/IPHONE.md).
