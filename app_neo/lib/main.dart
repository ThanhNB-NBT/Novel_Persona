import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'errorlog.dart';
import 'neo_theme.dart';
import 'neo_widgets.dart';
import 'notify.dart';
import 'screens/admin.dart';
import 'screens/edit_profile.dart';
import 'screens/errors.dart';
import 'screens/glossary.dart';
import 'screens/login.dart';
import 'screens/novel_detail.dart';
import 'screens/offline_library.dart';
import 'screens/reader.dart';
import 'screens/search.dart';
import 'screens/shell.dart';

// Key trong app_neo/.env (gitignore), chạy:
//   flutter run -d <android-device> --dart-define-from-file=.env
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  prefs = await SharedPreferences.getInstance();
  AppErrorLog.install();
  await initNotifications();
  chapterNotifier.start();
  runApp(const ProviderScope(child: NeoApp()));
}

// Route mới thêm ở phase sau; mọi trang dùng MaterializePage (fade + scanline).
final _router = GoRouter(routes: [
  GoRoute(path: '/', pageBuilder: (_, _) => MaterializePage(child: const NeoShell())),
  GoRoute(path: '/login', pageBuilder: (_, _) => MaterializePage(child: const LoginScreen())),
  GoRoute(path: '/search', pageBuilder: (_, _) => MaterializePage(child: const SearchScreen())),
  GoRoute(path: '/offline', pageBuilder: (_, _) => MaterializePage(child: const OfflineLibraryScreen())),
  GoRoute(path: '/profile/edit', pageBuilder: (_, _) => MaterializePage(child: const EditProfileScreen())),
  GoRoute(path: '/errors', pageBuilder: (_, _) => MaterializePage(child: const ErrorLogScreen())),
  GoRoute(path: '/admin', pageBuilder: (_, _) => MaterializePage(child: const AdminScreen())),
  GoRoute(
    path: '/admin/novel/:id',
    pageBuilder: (_, s) => MaterializePage(
        child: AdminNovelScreen(novelId: int.parse(s.pathParameters['id']!))),
  ),
  GoRoute(
    path: '/novel/:id',
    pageBuilder: (_, s) => MaterializePage(
        child: NovelDetailScreen(novelId: int.parse(s.pathParameters['id']!))),
  ),
  GoRoute(
    path: '/novel/:id/glossary',
    pageBuilder: (_, s) => MaterializePage(
        child: GlossaryScreen(novelId: int.parse(s.pathParameters['id']!))),
  ),
  GoRoute(
    path: '/novel/:id/read/:index',
    pageBuilder: (_, s) => MaterializePage(
        child: ReaderScreen(
      novelId: int.parse(s.pathParameters['id']!),
      chapterIndex: int.parse(s.pathParameters['index']!),
    )),
  ),
]);

class NeoApp extends StatelessWidget {
  const NeoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NEO Terminal',
      debugShowCheckedModeBanner: false,
      theme: neoTheme,
      routerConfig: _router,
    );
  }
}
