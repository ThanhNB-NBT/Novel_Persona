import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'errorlog.dart';
import 'hanviet.dart';
import 'notify.dart';
import 'theme.dart';
import 'screens/admin/admin.dart';
import 'screens/account/edit_profile.dart';
import 'screens/cultivation/cultivation.dart';
import 'screens/admin/errors.dart';
import 'screens/novel/glossary.dart';
import 'screens/account/login.dart';
import 'screens/library/notifications.dart';
import 'screens/library/offline_library.dart';
import 'screens/novel/novel_detail.dart';
import 'screens/reader/reader.dart';
import 'screens/reader/reader_settings.dart';
import 'screens/explore/search.dart';
import 'screens/shell.dart';

// Key đặt trong app/.env (đã gitignore), chạy:
//   flutter run -d <android-device> --dart-define-from-file=.env
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  prefs = await SharedPreferences.getInstance();
  AppErrorLog.install(); // bắt lỗi runtime → xem ở màn "Nhật ký lỗi"
  await initNotifications();
  loadHanViet(); // bảng tra Hán-Việt cho form sửa dịch — nạp nền, không chặn khởi động
  chapterNotifier.start(); // thông báo khi chương trong tủ sách dịch xong
  // đăng nhập/xuất → nối lại kênh realtime (kênh mở trước khi login không mang auth)
  sb.auth.onAuthStateChange.listen((s) {
    chapterNotifier.start();
    // có phiên (khôi phục lúc mở app / vừa đăng nhập) → quét chương dịch xong
    // trong lúc app tắt (realtime không sống lúc đó nên phải quét bù)
    if (s.event == AuthChangeEvent.initialSession ||
        s.event == AuthChangeEvent.signedIn) {
      checkMissedChapters();
    }
  });
  // quay lại app từ nền: socket realtime thường đã bị OS ngắt → quét bù luôn
  // (binding giữ observer nên không cần giữ tham chiếu)
  AppLifecycleListener(onResume: checkMissedChapters);
  runApp(const ProviderScope(child: NovelApp()));
}

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, _) => const RootShell()),
  GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
  GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
  GoRoute(path: '/profile/edit', builder: (_, _) => const EditProfileScreen()),
  GoRoute(path: '/offline', builder: (_, _) => const OfflineLibraryScreen()),
  GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
  GoRoute(path: '/errors', builder: (_, _) => const ErrorLogScreen()),
  GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
  GoRoute(path: '/cultivation', builder: (_, _) => const CultivationScreen()),
  GoRoute(
    path: '/admin/novel/:id',
    builder: (_, s) => AdminNovelScreen(novelId: int.parse(s.pathParameters['id']!)),
  ),
  GoRoute(
    path: '/novel/:id',
    builder: (_, s) => NovelDetailScreen(novelId: int.parse(s.pathParameters['id']!)),
  ),
  GoRoute(
    path: '/novel/:id/glossary',
    builder: (_, s) => GlossaryScreen(novelId: int.parse(s.pathParameters['id']!)),
  ),
  GoRoute(
    path: '/novel/:id/read/:index',
    // Transition đổi chương theo chế độ đọc: lật trang giữ trượt NGANG (khớp thao tác
    // vuốt ngang); cuộn dọc dùng fade trung tính (trượt ngang lệch cảm giác cuộn).
    pageBuilder: (context, s) {
      final pageMode =
          ProviderScope.containerOf(context).read(readerSettingsProvider).pageMode;
      return CustomTransitionPage(
        key: s.pageKey,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, anim, _, child) => pageMode
            ? SlideTransition(
                position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                child: child)
            : FadeTransition(opacity: anim, child: child),
        child: ReaderScreen(
          novelId: int.parse(s.pathParameters['id']!),
          chapterIndex: int.parse(s.pathParameters['index']!),
        ),
      );
    },
  ),
]);

/// Bỏ hiệu ứng kéo giãn (stretch) của Material 3, thay bằng vòng glow mờ ở mép
/// khi cuộn hết — nội dung đứng yên, người dùng biết đã hết.
class _GlowScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return GlowingOverscrollIndicator(
      axisDirection: details.direction,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
      child: child,
    );
  }
}

class NovelApp extends ConsumerWidget {
  const NovelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    return MaterialApp.router(
      title: 'Gác Truyện',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _GlowScrollBehavior(),
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: switch (mode) { 1 => ThemeMode.light, 2 => ThemeMode.dark, _ => ThemeMode.system },
      // Đổi theme TỨC THỜI (1 frame) — lerp theme theo từng frame là nguồn khựng
      // (cả cây rebuild mỗi frame). Cái "êm" giao cho lớp scrim bên dưới lo.
      themeAnimationDuration: Duration.zero,
      builder: (_, child) => _ThemeSwitchScrim(child: child!),
      routerConfig: _router,
    );
  }
}

/// Che khoảnh khắc đổi sáng/tối: phủ lớp tối mờ lóe lên nhanh rồi tan chậm.
/// Theme swap 1 frame dưới lớp phủ → không lóe trắng, không khựng kéo dài.
class _ThemeSwitchScrim extends StatefulWidget {
  final Widget child;
  const _ThemeSwitchScrim({required this.child});
  @override
  State<_ThemeSwitchScrim> createState() => _ThemeSwitchScrimState();
}

class _ThemeSwitchScrimState extends State<_ThemeSwitchScrim>
    with SingleTickerProviderStateMixin {
  late final _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _alpha = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.3).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30),
    TweenSequenceItem(
        tween: Tween(begin: 0.3, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 70),
  ]).animate(_ctrl);
  Brightness? _last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Theme.of(context).brightness;
    if (_last != null && b != _last) _ctrl.forward(from: 0);
    _last = b;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) => _ctrl.isAnimating
              ? Container(color: Colors.black.withValues(alpha: _alpha.value))
              : const SizedBox.shrink(),
        ),
      ),
    ]);
  }
}
