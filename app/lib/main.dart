import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'errorlog.dart';
import 'notify.dart';
import 'theme.dart';
import 'screens/admin/admin.dart';
import 'screens/account/edit_profile.dart';
import 'screens/admin/errors.dart';
import 'screens/novel/glossary.dart';
import 'screens/account/login.dart';
import 'screens/library/offline_library.dart';
import 'screens/novel/novel_detail.dart';
import 'screens/reader/reader.dart';
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
  chapterNotifier.start(); // thông báo khi chương trong tủ sách dịch xong
  runApp(const ProviderScope(child: NovelApp()));
}

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, _) => const RootShell()),
  GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
  GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
  GoRoute(path: '/profile/edit', builder: (_, _) => const EditProfileScreen()),
  GoRoute(path: '/offline', builder: (_, _) => const OfflineLibraryScreen()),
  GoRoute(path: '/errors', builder: (_, _) => const ErrorLogScreen()),
  GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
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
    builder: (_, s) => ReaderScreen(
      novelId: int.parse(s.pathParameters['id']!),
      chapterIndex: int.parse(s.pathParameters['index']!),
    ),
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
      routerConfig: _router,
    );
  }
}
