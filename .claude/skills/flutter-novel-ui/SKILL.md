---
name: flutter-novel-ui
description: >-
  Build or edit the Flutter UI of THIS novel-reader app (E:\Novel_Project\app).
  Use this skill whenever you touch anything under app/lib/screens or app/lib/widgets.dart —
  adding a screen, tweaking a widget, changing colors/spacing/typography, wiring a provider or
  route, or fixing reader/library/detail UI. Encodes the "Thanh Tân/Dạ Lam" design system,
  the Riverpod + go_router + Supabase conventions, and the shared widgets so UI stays consistent
  instead of getting re-tweaked every round. Do NOT use for the Python worker, DB migrations,
  or generic web design.
---

# Flutter Novel UI

UI cho app đọc truyện dịch (Trung→Việt). Mục tiêu của skill: **code UI nhất quán ngay lần đầu**, không phải chỉnh tới chỉnh lui. Trước khi thêm cái mới, hãy dùng lại thứ đã có.

## Trước khi sửa

1. Đọc file đang sửa + `app/lib/theme.dart` (design tokens) + `app/lib/widgets.dart` (widget dùng chung).
2. Có `.codegraph/` → dùng `codegraph explore "<symbol>"` thay vì grep để định vị nhanh.
3. Sửa xong LUÔN chạy: `cd app && flutter analyze <file...>`. Không kết thúc khi còn warning do mình tạo ra.

## Design system (theme.dart — đừng hardcode màu)

Hai bảng màu, tự đổi theo `themeMode`: sáng **"Thanh Tân"** (trắng lạnh ngả xanh, nhấn xanh dương `#3576F5`), tối **"Dạ Lam"** (nền xanh đêm, nhấn xanh băng). Nguyên tắc: **tránh trắng/đen tuyền**, bo tròn nhiều (12–20), viền mảnh thay vì đổ bóng nặng.

Lấy màu từ `ColorScheme`, KHÔNG viết `Color(0x...)` trong screen:

| Cần | Dùng |
|-----|------|
| Nhấn / nút chính | `cs.primary`, chữ trên nền nhấn `cs.onPrimary` |
| Nền nhấn nhạt | `cs.primaryContainer` / `cs.onPrimaryContainer` |
| Chữ chính | `cs.onSurface` · Chữ phụ/icon xám | `cs.onSurfaceVariant` |
| Nền thẻ | `cs.surface` · Viền | `cs.outlineVariant` |
| Lỗi | `cs.error` |

```dart
final cs = Theme.of(context).colorScheme;
final t  = Theme.of(context).textTheme;
```

Chữ: **Plus Jakarta Sans** qua `textTheme` — `displaySmall/headlineSmall/titleLarge/titleMedium/bodyLarge/bodyMedium/labelLarge/labelMedium/labelSmall`. Đừng đặt `fontSize`/`fontFamily` tay; chọn bậc trong textTheme rồi `.copyWith()` nếu cần chỉnh nhẹ. Chữ đọc truyện là ngoại lệ — dùng `readerFontStyle()` trong `reader_settings.dart`.

Thành phần đã style sẵn trong theme (dùng thẳng, không tự vẽ lại): `FilledButton`, `OutlinedButton`, `TextButton`, `InputDecoration`, `Card`, `NavigationBar`, `Dialog`, `SnackBar`, `FloatingActionButton`. Bán kính chuẩn 12–18.

## Widget dùng chung (widgets.dart — ưu tiên tái dùng)

- `Cover(url:, width:, aspect: 1.4, label:)` — bìa truyện, có placeholder gradient + chữ cái đầu. Dùng `Hero(tag: 'cover-${n['id']}', child: Cover(...))` để chuyển cảnh mượt.
- `NovelListRow(n:, onTap:, trailing:)` — 1 dòng truyện cho danh sách tìm kiếm/lọc.
- `ProgressRibbon(value)` — thanh tiến độ đọc mảnh (0..1).
- `TagChip(label, color:)` — chip trạng thái nhỏ.
- `SectionHeader(title, onMore:)` — tiêu đề mục kiểu editorial.
- `RowDivider()` — kẻ ngăn giữa các dòng.

Cần cái mới lặp lại ≥2 nơi → thêm vào `widgets.dart`, đừng nhân bản inline.

## Kiến trúc (bám theo cái đang có)

- **State: Riverpod.** Data ở `app/lib/data.dart`. Đọc: `ref.watch(xProvider)` rồi `.when(loading/error/data:)`. Đa số là `FutureProvider.autoDispose`, có tham số thì `.family` (vd `chapterProvider(ChapterKey(...))`, `novelProvider(id)`). State ghi được (cài đặt) là `NotifierProvider` (vd `readerSettingsProvider`). Sau khi đổi dữ liệu server, `ref.invalidate(provider)` để refetch.
- **Điều hướng: go_router** (routes trong `app/lib/main.dart`). Mở truyện ở **bất cứ đâu** → `context.push('/novel/${n['id']}')` (trang thông tin), KHÔNG nhảy thẳng vào đọc. Đọc: `/novel/:id/read/:index`. Đổi chương: `context.pushReplacement(...)`.
- **Supabase:** client toàn cục `sb` (từ `data.dart`). Chưa đăng nhập: `sb.auth.currentUser == null` → `context.push('/login')`. Truy vấn/RPC gói trong provider hoặc hàm ở `data.dart`, không rải vào widget.
- **Local prefs:** `prefs` toàn cục (SharedPreferences) qua helper trong `data.dart` (vd `saveChapterPercent`). Nhớ: `.order()` của supabase-dart **mặc định DESCENDING** — phải `ascending: true` nếu muốn tăng dần.

## Phong cách code (ponytail)

- Diff ngắn nhất chạy được. Không abstraction đầu cơ, không tham số "để dành".
- Comment **tiếng Việt**, ngắn, giải thích *vì sao* (nhìn code là biết *cái gì* rồi). Đánh dấu rút gọn có chủ đích bằng `// ponytail: ...` kèm trần/đường nâng cấp.
- Bám idiom file xung quanh (đặt tên, mật độ comment, cách tách widget con `_TênRiêng extends ConsumerWidget/StatelessWidget`).
- Sửa hành vi logic không tầm thường (parser, phân trang, vòng lặp) → để lại 1 kiểm chứng chạy được.

## Bẫy hay gặp

- Reader (`reader.dart`) tự resolve màu nền qua `s.resolve(platformBrightness)` — trong màn đọc dùng `col.bg/col.fg`, KHÔNG dùng ColorScheme của app.
- `.family` cần key có `==`/`hashCode` đúng (xem `ChapterKey`).
- Ảnh mạng luôn kèm `errorBuilder`/fallback (bìa hỏng rất thường).
- Trước khi khẳng định "xong": chạy `flutter analyze` và, nếu đổi luồng lớn, gợi ý user chạy trên Android (`flutter run -d <device> --dart-define-from-file=.env`) để xem thật — target Windows đã bỏ.

## Bẫy đúng-sai Flutter (lỗi hay mắc — kiểm trước khi báo xong)

- **BuildContext qua async gap:** sau mỗi `await`, TRƯỚC khi dùng `context` (Navigator, ScaffoldMessenger, Theme.of, context.push) phải kiểm `if (!context.mounted) return;`. Trong callback lồng nhau, lưu `final messenger = ScaffoldMessenger.of(context);` TRƯỚC await rồi dùng lại. Đây là lỗi `use_build_context_synchronously` — analyzer bắt, đừng để lọt.
- **supabase-dart thứ tự builder:** `.eq()/.order()/.limit()` là filter builder → phải gọi SAU `.select()`/`.update()`/`.delete()`, KHÔNG gọi ngay sau `.from()` (sẽ không biên dịch). Và `.order()` mặc định **DESCENDING** — muốn tăng dần phải `ascending: true`.
- **Không codegen:** dự án CỐ TÌNH không dùng freezed/build_runner/injectable — model là `Map` (`Rec = Map<String,dynamic>`). Đừng thêm codegen/generated file; đọc field bằng `n['key']` + ép kiểu tại chỗ.
- **setState:** không gọi trong `build`; không gọi sau `dispose` (State đã unmount → dùng `if (mounted)`). Phần nhỏ hay đổi (selection, %) ưu tiên `ValueNotifier` + `ValueListenableBuilder` để KHỎI rebuild cả cây (xem reader.dart `_sel`, `_percent`).
- **Provider `autoDispose`:** widget rời đi là provider huỷ + refetch khi quay lại. Sau khi ghi server (insert/delete/update) phải `ref.invalidate(provider)` để UI khớp; tab trong IndexedStack (giữ sống) thì invalidate lúc mở tab (xem `shell.dart`).
- **RLS admin lệch:** truy vấn bảng có policy admin-đọc-tất-cả (vd `reading_progress`) cho màn cá nhân phải LỌC THẲNG `.eq('user_id', uid)` — nếu không, tài khoản admin thấy (và không xoá được) dữ liệu người khác.
